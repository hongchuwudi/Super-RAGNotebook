#!/usr/bin/env bash
#
# Linux PostgreSQL 中文管理脚本
#
# 支持常见 Linux 发行版:
#   - Debian / Ubuntu
#   - RHEL / CentOS / Rocky / AlmaLinux / Oracle Linux / Fedora
#   - openSUSE / SUSE
#   - Arch Linux / Manjaro
#
# 支持功能:
#   - 自动识别发行版、包管理器、systemd 服务名和常见数据目录
#   - 安装 / 卸载 PostgreSQL
#   - 初始化数据目录
#   - 启动 / 停止 / 重启 / 重载 / 查看状态
#   - 开机自启管理
#   - 配置远程连接
#   - 数据库和用户管理
#   - 安装 PostgreSQL 扩展包，扩展子菜单内置 pgvector
#   - 为数据库启用扩展，默认启用 vector
#   - 备份 / 恢复 / 查看日志
#
# 推荐用法:
#   sudo bash scripts/manage_postgresql_linux.sh
#
# 可选自动化用法:
#   sudo bash scripts/manage_postgresql_linux.sh --pg-version 16 install
#   sudo bash scripts/manage_postgresql_linux.sh --pg-version 16 --source pgdg install
#
# 可选环境变量:
#   PG_VERSION=16              # PostgreSQL 主版本；安装时不设默认值，非交互安装必须指定
#   INSTALL_SOURCE=auto        # auto / system / pgdg，默认 auto
#   PG_SERVICE=postgresql-16   # 手动指定 systemd 服务名
#   PGDATA=/var/lib/pgsql/16/data
#   EXTENSION_NAME=pgvector    # 命令行 install-extension 指定扩展包；为空则进入子菜单
#   SQL_EXTENSION_NAME=vector   # enable-extension 默认 SQL 扩展名
#   ASSUME_YES=1               # 自动确认默认选项，谨慎使用

set -Eeuo pipefail

PG_VERSION="${PG_VERSION:-}"
INSTALL_SOURCE="${INSTALL_SOURCE:-auto}"
PG_SERVICE="${PG_SERVICE:-}"
PGDATA="${PGDATA:-}"
EXTENSION_NAME="${EXTENSION_NAME:-}"
SQL_EXTENSION_NAME="${SQL_EXTENSION_NAME:-vector}"
ASSUME_YES="${ASSUME_YES:-0}"

OS_ID="unknown"
OS_ID_LIKE=""
OS_NAME="unknown"
OS_VERSION_ID=""
OS_VERSION_CODENAME=""
OS_DETECTED=0
ACTION="menu"
STYLE_RESET=""
STYLE_BOLD=""
STYLE_DIM=""
STYLE_RED=""
STYLE_GREEN=""
STYLE_YELLOW=""
STYLE_BLUE=""
STYLE_CYAN=""

trap 'code=$?; echo; echo "错误: 脚本执行失败，退出码 ${code}，位置 ${BASH_SOURCE[0]}:${LINENO}"; exit "${code}"' ERR

init_style() {
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        STYLE_RESET=$'\033[0m'
        STYLE_BOLD=$'\033[1m'
        STYLE_DIM=$'\033[2m'
        STYLE_RED=$'\033[31m'
        STYLE_GREEN=$'\033[32m'
        STYLE_YELLOW=$'\033[33m'
        STYLE_BLUE=$'\033[34m'
        STYLE_CYAN=$'\033[36m'
    fi
}

info() {
    echo "提示: $*"
}

warn() {
    echo "警告: $*" >&2
}

die() {
    echo "错误: $*" >&2
    exit 1
}

run() {
    printf '\n>>>'
    printf ' %q' "$@"
    printf '\n'
    "$@"
}

ensure_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "该操作需要 root 权限，请使用 sudo 运行。"
    fi
}

pause_if_interactive() {
    if [[ -t 0 && "${ASSUME_YES}" != "1" ]]; then
        local _
        read -r -p "按 Enter 返回菜单..." _
    fi
}

confirm() {
    local question="$1"
    local default="${2:-N}"
    local suffix answer

    if [[ "${ASSUME_YES}" == "1" ]]; then
        [[ "${default^^}" == "Y" ]]
        return
    fi

    if [[ ! -t 0 ]]; then
        [[ "${default^^}" == "Y" ]]
        return
    fi

    if [[ "${default^^}" == "Y" ]]; then
        suffix="[Y/n]"
    else
        suffix="[y/N]"
    fi

    read -r -p "${question} ${suffix}: " answer
    answer="${answer:-${default}}"
    [[ "${answer^^}" == "Y" || "${answer^^}" == "YES" ]]
}

prompt_default() {
    local var_name="$1"
    local question="$2"
    local default="$3"
    local answer

    if [[ "${ASSUME_YES}" == "1" || ! -t 0 ]]; then
        printf -v "${var_name}" '%s' "${default}"
        return
    fi

    read -r -p "${question} [${default}]: " answer
    printf -v "${var_name}" '%s' "${answer:-${default}}"
}

read_secret() {
    local var_name="$1"
    local question="$2"
    local answer

    if [[ -t 0 ]]; then
        read -r -s -p "${question}: " answer
        echo
    else
        read -r answer
    fi

    printf -v "${var_name}" '%s' "${answer}"
}

is_valid_pg_version() {
    local value="$1"
    [[ "${value}" =~ ^[0-9]+$ ]]
}

validate_pg_version() {
    if [[ -z "${PG_VERSION}" ]]; then
        die "未指定 PostgreSQL 主版本。安装或初始化时请输入版本，或使用 --pg-version 16。"
    fi

    if ! is_valid_pg_version "${PG_VERSION}"; then
        die "PG_VERSION 只接受 PostgreSQL 主版本号，例如 16、15、14。当前值: ${PG_VERSION}"
    fi
}

validate_optional_pg_version() {
    [[ -z "${PG_VERSION}" ]] && return
    validate_pg_version
}

validate_identifier() {
    local value="$1"
    local label="$2"

    if ! [[ "${value}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        die "${label} 只能包含字母、数字、下划线，且不能以数字开头。当前值: ${value}"
    fi
}

validate_extension_name() {
    local value="$1"

    if ! [[ "${value}" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]; then
        die "扩展名只能包含字母、数字、下划线和中划线，且不能为空。当前值: ${value}"
    fi
}

sql_literal() {
    sed "s/'/''/g" <<<"$1"
}

normalize_install_source() {
    INSTALL_SOURCE="${INSTALL_SOURCE,,}"
    case "${INSTALL_SOURCE}" in
        auto|system|pgdg)
            ;;
        *)
            die "INSTALL_SOURCE 只能是 auto、system 或 pgdg。当前值: ${INSTALL_SOURCE}"
            ;;
    esac
}

detect_os() {
    if [[ "${OS_DETECTED}" == "1" ]]; then
        return
    fi

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_ID_LIKE="${ID_LIKE:-}"
        OS_NAME="${NAME:-unknown}"
        OS_VERSION_ID="${VERSION_ID:-}"
        OS_VERSION_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    fi

    OS_ID="${OS_ID,,}"
    OS_ID_LIKE="${OS_ID_LIKE,,}"
    OS_DETECTED=1
}

detect_distro_family() {
    detect_os

    case " ${OS_ID} ${OS_ID_LIKE} " in
        *" debian "*|*" ubuntu "*)
            echo "debian"
            ;;
        *" rhel "*|*" centos "*|*" fedora "*)
            echo "rhel"
            ;;
        *" suse "*|*" opensuse "*)
            echo "suse"
            ;;
        *" arch "*)
            echo "arch"
            ;;
        *)
            if command -v apt-get >/dev/null 2>&1; then
                echo "debian"
            elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
                echo "rhel"
            elif command -v zypper >/dev/null 2>&1; then
                echo "suse"
            elif command -v pacman >/dev/null 2>&1; then
                echo "arch"
            else
                echo "unknown"
            fi
            ;;
    esac
}

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        die "未找到支持的包管理器。当前脚本支持 apt、dnf、yum、zypper、pacman。"
    fi
}

detect_package_manager_or_unknown() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

detect_os_major() {
    detect_os

    local version_id="${OS_VERSION_ID%%.*}"
    if ! [[ "${version_id}" =~ ^[0-9]+$ ]]; then
        die "无法识别系统主版本号，请检查 /etc/os-release。"
    fi

    echo "${version_id}"
}

detect_arch() {
    uname -m
}

resolve_install_source() {
    local family="$1"

    normalize_install_source

    if [[ "${INSTALL_SOURCE}" != "auto" ]]; then
        echo "${INSTALL_SOURCE}"
        return
    fi

    case "${family}" in
        rhel)
            if [[ "${OS_ID}" == "fedora" ]]; then
                echo "system"
            else
                echo "pgdg"
            fi
            ;;
        debian|suse|arch)
            echo "system"
            ;;
        *)
            echo "system"
            ;;
    esac
}

systemctl_available() {
    command -v systemctl >/dev/null 2>&1
}

systemctl_unit_exists() {
    local service_name="$1"

    systemctl_available || return 1
    systemctl list-unit-files --type=service "${service_name}.service" 2>/dev/null \
        | awk '{print $1}' \
        | grep -qx "${service_name}.service"
}

detect_service_name() {
    local family source candidate
    local candidates=()

    if [[ -n "${PG_SERVICE}" ]]; then
        echo "${PG_SERVICE}"
        return
    fi

    detect_os
    family="$(detect_distro_family)"
    source="$(resolve_install_source "${family}")"

    if [[ -n "${PG_VERSION}" ]]; then
        candidates+=(
            "postgresql-${PG_VERSION}"
            "postgresql@${PG_VERSION}-main"
        )
    fi

    candidates+=(
        postgresql-18
        postgresql-17
        postgresql-16
        postgresql-15
        postgresql-14
        postgresql-13
        postgresql-12
        postgresql-11
        postgresql-10
        postgresql-9.6
        postgresql
    )

    for candidate in "${candidates[@]}"; do
        if systemctl_unit_exists "${candidate}"; then
            echo "${candidate}"
            return
        fi
    done

    case "${family}:${source}" in
        rhel:pgdg)
            if [[ -n "${PG_VERSION}" ]]; then
                echo "postgresql-${PG_VERSION}"
            else
                echo "postgresql"
            fi
            ;;
        *)
            echo "postgresql"
            ;;
    esac
}

find_debian_pg_version() {
    local version

    if command -v pg_lsclusters >/dev/null 2>&1; then
        version="$(pg_lsclusters --no-header 2>/dev/null | awk 'NR == 1 {print $1}')"
        if [[ "${version}" =~ ^[0-9]+$ ]]; then
            echo "${version}"
            return
        fi
    fi

    version="$(find /etc/postgresql -mindepth 2 -maxdepth 2 -name postgresql.conf 2>/dev/null \
        | sed -E 's|/etc/postgresql/([^/]+)/.*|\1|' \
        | sort -Vr \
        | head -n 1 || true)"
    if [[ "${version}" =~ ^[0-9]+$ ]]; then
        echo "${version}"
    fi
}

get_data_dir() {
    local family debian_version

    if [[ -n "${PGDATA}" ]]; then
        echo "${PGDATA}"
        return
    fi

    family="$(detect_distro_family)"

    case "${family}" in
        debian)
            debian_version="$(find_debian_pg_version || true)"
            if [[ -n "${debian_version}" && -d "/var/lib/postgresql/${debian_version}/main" ]]; then
                echo "/var/lib/postgresql/${debian_version}/main"
                return
            fi
            if [[ -n "${PG_VERSION}" ]]; then
                echo "/var/lib/postgresql/${PG_VERSION}/main"
            else
                echo "/var/lib/postgresql"
            fi
            ;;
        arch)
            echo "/var/lib/postgres/data"
            ;;
        rhel|suse)
            if [[ -n "${PG_VERSION}" && -d "/var/lib/pgsql/${PG_VERSION}/data" ]]; then
                echo "/var/lib/pgsql/${PG_VERSION}/data"
                return
            fi
            if [[ -d "/var/lib/pgsql/data" ]]; then
                echo "/var/lib/pgsql/data"
                return
            fi
            if [[ -n "${PG_VERSION}" && "$(resolve_install_source "${family}")" == "pgdg" ]]; then
                echo "/var/lib/pgsql/${PG_VERSION}/data"
            else
                echo "/var/lib/pgsql/data"
            fi
            ;;
        *)
            if [[ -n "${PG_VERSION}" && -d "/var/lib/postgresql/${PG_VERSION}/main" ]]; then
                echo "/var/lib/postgresql/${PG_VERSION}/main"
            elif [[ -n "${PG_VERSION}" && -d "/var/lib/pgsql/${PG_VERSION}/data" ]]; then
                echo "/var/lib/pgsql/${PG_VERSION}/data"
            elif [[ -d "/var/lib/postgres/data" ]]; then
                echo "/var/lib/postgres/data"
            elif [[ -d "/var/lib/pgsql/data" ]]; then
                echo "/var/lib/pgsql/data"
            elif [[ -d "/var/lib/postgresql" ]]; then
                echo "/var/lib/postgresql"
            else
                echo "/var/lib/pgsql/data"
            fi
            ;;
    esac
}

get_config_dir() {
    local data_dir debian_version

    data_dir="$(get_data_dir)"
    if [[ -f "${data_dir}/postgresql.conf" ]]; then
        echo "${data_dir}"
        return
    fi

    debian_version="$(find_debian_pg_version || true)"
    if [[ -n "${debian_version}" && -f "/etc/postgresql/${debian_version}/main/postgresql.conf" ]]; then
        echo "/etc/postgresql/${debian_version}/main"
        return
    fi

    if [[ -n "${PG_VERSION}" && -f "/etc/postgresql/${PG_VERSION}/main/postgresql.conf" ]]; then
        echo "/etc/postgresql/${PG_VERSION}/main"
        return
    fi

    echo "${data_dir}"
}

pg_bin() {
    local name="$1"

    if [[ -n "${PG_VERSION}" ]]; then
        local candidate="/usr/pgsql-${PG_VERSION}/bin/${name}"

        if [[ -x "${candidate}" ]]; then
            echo "${candidate}"
            return
        fi
    fi

    if command -v "${name}" >/dev/null 2>&1; then
        command -v "${name}"
        return
    fi

    echo "${name}"
}

run_as_postgres() {
    if [[ "$(id -u)" -eq 0 ]]; then
        if command -v runuser >/dev/null 2>&1; then
            runuser -u postgres -- "$@"
        else
            sudo -u postgres "$@"
        fi
    else
        sudo -u postgres "$@"
    fi
}

psql_as_postgres() {
    run_as_postgres "$(pg_bin psql)" -v ON_ERROR_STOP=1 "$@"
}

detect_installed_pg_major() {
    local psql_path version_text major debian_version

    debian_version="$(find_debian_pg_version || true)"
    if [[ "${debian_version}" =~ ^[0-9]+$ ]]; then
        echo "${debian_version}"
        return
    fi

    psql_path="$(pg_bin psql)"
    version_text="$("${psql_path}" --version 2>/dev/null || true)"
    major="$(sed -E 's/.* ([0-9]+)(\.[0-9]+)?.*/\1/' <<<"${version_text}")"

    if [[ "${major}" =~ ^[0-9]+$ ]]; then
        echo "${major}"
    elif [[ -n "${PG_VERSION}" ]]; then
        echo "${PG_VERSION}"
    fi
}

pkg_update() {
    local pm="$1"

    case "${pm}" in
        apt)
            run apt-get update
            ;;
        zypper)
            run zypper --non-interactive refresh
            ;;
        *)
            return 0
            ;;
    esac
}

pkg_install() {
    local pm="$1"
    shift

    case "${pm}" in
        apt)
            run env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
            ;;
        dnf|yum)
            run "${pm}" install -y "$@"
            ;;
        zypper)
            run zypper --non-interactive install "$@"
            ;;
        pacman)
            run pacman -Sy --noconfirm "$@"
            ;;
        *)
            die "不支持的包管理器: ${pm}"
            ;;
    esac
}

pkg_remove() {
    local pm="$1"
    shift

    case "${pm}" in
        apt)
            run env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$@"
            ;;
        dnf|yum)
            run "${pm}" remove -y "$@"
            ;;
        zypper)
            run zypper --non-interactive remove "$@"
            ;;
        pacman)
            run pacman -Rns --noconfirm "$@"
            ;;
        *)
            die "不支持的包管理器: ${pm}"
            ;;
    esac
}

try_pkg_install_one() {
    local pm="$1"
    local package_name="$2"

    if pkg_install "${pm}" "${package_name}"; then
        return 0
    fi

    warn "安装包 ${package_name} 失败，继续尝试下一个候选包。"
    return 1
}

choose_pg_version_for_install() {
    local version

    if [[ -n "${PG_VERSION}" ]]; then
        validate_pg_version
        return
    fi

    if [[ "${ASSUME_YES}" == "1" || ! -t 0 ]]; then
        die "安装 PostgreSQL 时必须指定主版本。请使用 --pg-version 16，或设置 PG_VERSION=16。"
    fi

    while true; do
        read -r -p "请输入要安装的 PostgreSQL 主版本号（例如 16、17、18）: " version
        if [[ -z "${version}" ]]; then
            warn "版本号不能为空，请输入 PostgreSQL 主版本号。"
            continue
        fi
        if ! is_valid_pg_version "${version}"; then
            warn "版本号只接受数字，例如 16、17、18。"
            continue
        fi
        PG_VERSION="${version}"
        return
    done
}

choose_install_settings() {
    local family="$1"
    local source effective_source

    prompt_default source "请选择安装源，auto=自动，system=系统仓库，pgdg=PostgreSQL 官方仓库" "${INSTALL_SOURCE}"
    INSTALL_SOURCE="${source,,}"
    normalize_install_source
    choose_pg_version_for_install

    if [[ "${INSTALL_SOURCE}" == "auto" ]]; then
        case "${family}" in
            debian|rhel)
                INSTALL_SOURCE="pgdg"
                ;;
        esac
    fi

    effective_source="$(resolve_install_source "${family}")"
    if [[ "${effective_source}" == "system" ]]; then
        warn "当前实际安装源为 system，部分发行版系统仓库可能只提供默认 PostgreSQL 包，未必能严格安装 ${PG_VERSION}。"
        warn "如需严格安装指定主版本，建议选择 --source pgdg。"
    fi
}

install_pgdg_rpm_repo() {
    local pm="$1"
    local os_major arch repo_url

    os_major="$(detect_os_major)"
    arch="$(detect_arch)"

    if [[ "${OS_ID}" == "fedora" ]]; then
        repo_url="https://download.postgresql.org/pub/repos/yum/reporpms/F-${os_major}-${arch}/pgdg-fedora-repo-latest.noarch.rpm"
    else
        repo_url="https://download.postgresql.org/pub/repos/yum/reporpms/EL-${os_major}-${arch}/pgdg-redhat-repo-latest.noarch.rpm"
    fi

    if rpm -q pgdg-redhat-repo >/dev/null 2>&1 || rpm -q pgdg-fedora-repo >/dev/null 2>&1; then
        info "已安装 PGDG RPM 仓库包，跳过仓库安装。"
    else
        info "正在安装 PGDG 仓库: ${repo_url}"
        pkg_install "${pm}" "${repo_url}"
    fi

    if [[ "${pm}" == "dnf" || "${pm}" == "yum" ]]; then
        info "正在尝试禁用系统自带 postgresql 模块，避免包冲突。"
        "${pm}" -qy module disable postgresql >/dev/null 2>&1 || warn "禁用 postgresql 模块失败，若后续安装冲突请手动执行: ${pm} -qy module disable postgresql"
    fi
}

install_pgdg_apt_repo() {
    local pm="$1"
    local codename key_dir keyring key_tmp source_file

    pkg_update "${pm}"
    pkg_install "${pm}" ca-certificates curl gnupg lsb-release

    detect_os
    codename="${OS_VERSION_CODENAME}"
    if [[ -z "${codename}" ]] && command -v lsb_release >/dev/null 2>&1; then
        codename="$(lsb_release -cs)"
    fi
    [[ -n "${codename}" ]] || die "无法识别 Debian/Ubuntu 发行版代号，不能自动配置 PGDG APT 仓库。"

    key_dir="/usr/share/postgresql-common/pgdg"
    keyring="${key_dir}/apt.postgresql.org.gpg"
    key_tmp="$(mktemp)"
    source_file="/etc/apt/sources.list.d/pgdg.list"

    run mkdir -p "${key_dir}"
    if [[ ! -f "${keyring}" ]]; then
        run curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o "${key_tmp}"
        run gpg --dearmor -o "${keyring}" "${key_tmp}"
        rm -f -- "${key_tmp}"
    fi

    printf 'deb [signed-by=%s] https://apt.postgresql.org/pub/repos/apt %s-pgdg main\n' "${keyring}" "${codename}" >"${source_file}"
    info "已写入 PGDG APT 仓库: ${source_file}"
    pkg_update "${pm}"
}

install_postgres_packages() {
    local family="$1"
    local source="$2"
    local pm="$3"

    case "${family}:${source}" in
        debian:pgdg)
            install_pgdg_apt_repo "${pm}"
            pkg_install "${pm}" "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}" postgresql-contrib
            ;;
        debian:system)
            pkg_update "${pm}"
            pkg_install "${pm}" postgresql postgresql-contrib
            ;;
        rhel:pgdg)
            install_pgdg_rpm_repo "${pm}"
            pkg_install "${pm}" "postgresql${PG_VERSION}-server" "postgresql${PG_VERSION}-contrib"
            ;;
        rhel:system)
            pkg_install "${pm}" postgresql-server postgresql-contrib
            ;;
        suse:*)
            pkg_update "${pm}"
            if ! pkg_install "${pm}" postgresql-server postgresql-contrib; then
                pkg_install "${pm}" "postgresql${PG_VERSION}-server" "postgresql${PG_VERSION}-contrib"
            fi
            ;;
        arch:*)
            pkg_install "${pm}" postgresql
            ;;
        *)
            die "暂不支持当前发行版自动安装 PostgreSQL。发行版: ${OS_NAME}，包管理器: ${pm}"
            ;;
    esac
}

initdb_postgres() {
    ensure_root
    validate_pg_version

    local family data_dir setup_tool initdb_tool
    family="$(detect_distro_family)"
    data_dir="$(get_data_dir)"

    if [[ -f "${data_dir}/PG_VERSION" ]]; then
        info "数据目录已初始化: ${data_dir}"
        return
    fi

    if [[ "${family}" == "debian" ]]; then
        if command -v pg_lsclusters >/dev/null 2>&1 && pg_lsclusters --no-header 2>/dev/null | awk '{print $1, $2}' | grep -qx "${PG_VERSION} main"; then
            info "Debian/Ubuntu PostgreSQL 集群已存在: ${PG_VERSION}/main"
            return
        fi
        if command -v pg_createcluster >/dev/null 2>&1; then
            run pg_createcluster "${PG_VERSION}" main --start
            return
        fi
        warn "未找到 pg_createcluster，继续尝试通用 initdb。"
    fi

    if [[ -d "${data_dir}" ]] && [[ -n "$(find "${data_dir}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        die "数据目录存在且非空，但没有 PG_VERSION 文件: ${data_dir}"
    fi

    setup_tool="/usr/pgsql-${PG_VERSION}/bin/postgresql-${PG_VERSION}-setup"
    if [[ -x "${setup_tool}" ]]; then
        run "${setup_tool}" initdb
        return
    fi

    if command -v postgresql-setup >/dev/null 2>&1; then
        if run postgresql-setup --initdb; then
            return
        fi
        run postgresql-setup initdb
        return
    fi

    initdb_tool="$(pg_bin initdb)"
    run install -d -o postgres -g postgres "${data_dir}"
    run_as_postgres "${initdb_tool}" -D "${data_dir}"
}

install_pgvector_package() {
    install_extension_package "pgvector"
}

install_extension_package() {
    ensure_root

    local extension_name="${1:-${EXTENSION_NAME:-}}"
    local family pm installed_any package_name candidates=()

    if [[ -z "${extension_name}" ]]; then
        if [[ -t 0 ]]; then
            install_extension_menu
            return
        fi
        die "未指定扩展包。请进入菜单选择，或使用 --extension 指定扩展包，或使用 install-vector 安装 pgvector。"
    fi
    extension_name="${extension_name,,}"

    detect_os
    family="$(detect_distro_family)"
    pm="$(detect_package_manager)"
    pkg_update "${pm}" || true

    case "${extension_name}" in
        pgvector|vector)
            validate_pg_version
            case "${family}" in
                debian)
                    candidates=(
                        "postgresql-${PG_VERSION}-pgvector"
                        postgresql-pgvector
                        pgvector
                    )
                    ;;
                rhel)
                    candidates=(
                        "pgvector_${PG_VERSION}"
                        "postgresql${PG_VERSION}-pgvector"
                        pgvector
                    )
                    ;;
                suse)
                    candidates=(
                        "postgresql${PG_VERSION}-pgvector"
                        postgresql-pgvector
                        pgvector
                    )
                    ;;
                arch)
                    candidates=(
                        pgvector
                        postgresql-pgvector
                    )
                    ;;
                *)
                    candidates=(pgvector postgresql-pgvector)
                    ;;
            esac
            ;;
        *)
            validate_extension_name "${extension_name}"
            prompt_default package_name "请输入扩展对应的软件包名" "${extension_name}"
            candidates=("${package_name}")
            ;;
    esac

    installed_any=0
    for package_name in "${candidates[@]}"; do
        if try_pkg_install_one "${pm}" "${package_name}"; then
            installed_any=1
            break
        fi
    done

    if [[ "${installed_any}" != "1" ]]; then
        warn "没有成功安装扩展包 ${extension_name}。"
        warn "不同发行版的扩展包命名可能不同，你可以使用 --extension 指定扩展包名后重试。"
        return 1
    fi

    info "扩展包 ${extension_name} 安装完成。"
}

show_extension_install_menu() {
    clear 2>/dev/null || true
    print_banner_rule
    printf '  %bPostgreSQL 扩展安装菜单%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    print_banner_rule
    printf '  %b常用扩展%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    menu_item 1 "安装 pgvector"
    print_menu_rule
    printf '  %b预留扩展位%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    menu_item 2 "预留"
    menu_item 3 "预留"
    menu_item 4 "预留"
    menu_item 5 "预留"
    menu_item 6 "预留"
    menu_item 7 "预留"
    menu_item 8 "预留"
    menu_item 9 "预留"
    print_menu_rule
    menu_item 0 "返回上一级"
    print_menu_rule
}

install_extension_menu() {
    local choice

    while true; do
        show_extension_install_menu
        read -r -p "请输入扩展选项: " choice

        case "${choice}" in
            1)
                install_pgvector_package
                ;;
            0)
                info "已返回上一级菜单。"
                return
                ;;
            2|3|4|5|6|7|8|9)
                warn "该扩展位暂未配置，后续可在这里加入其它扩展。"
                ;;
            *)
                warn "无效选项，请重新输入。"
                ;;
        esac

        pause_if_interactive
    done
}

install_postgres() {
    ensure_root
    detect_os

    local family source pm installed_major
    family="$(detect_distro_family)"
    pm="$(detect_package_manager)"

    choose_install_settings "${family}"
    source="$(resolve_install_source "${family}")"

    info "识别到系统: ${OS_NAME} ${OS_VERSION_ID:-}"
    info "发行版族: ${family}"
    info "包管理器: ${pm}"
    info "安装源: ${source}"

    install_postgres_packages "${family}" "${source}" "${pm}"

    installed_major="$(detect_installed_pg_major || true)"
    if [[ "${installed_major}" =~ ^[0-9]+$ ]]; then
        PG_VERSION="${installed_major}"
    fi

    initdb_postgres
    enable_postgres
    start_postgres

    if confirm "是否进入扩展安装菜单？默认不安装任何扩展。" "N"; then
        install_extension_menu
    fi

    info "PostgreSQL 安装流程完成。"
    status_postgres || true
}

start_postgres() {
    ensure_root
    local service_name
    service_name="$(detect_service_name)"

    if systemctl_available; then
        run systemctl start "${service_name}"
    else
        run service "${service_name}" start
    fi
}

stop_postgres() {
    ensure_root
    local service_name
    service_name="$(detect_service_name)"

    if systemctl_available; then
        run systemctl stop "${service_name}"
    else
        run service "${service_name}" stop
    fi
}

restart_postgres() {
    ensure_root
    local service_name
    service_name="$(detect_service_name)"

    if systemctl_available; then
        run systemctl restart "${service_name}"
    else
        run service "${service_name}" restart
    fi
}

reload_postgres() {
    ensure_root
    local service_name
    service_name="$(detect_service_name)"

    if systemctl_available; then
        run systemctl reload "${service_name}"
    else
        run service "${service_name}" reload
    fi
}

status_postgres() {
    local service_name
    service_name="$(detect_service_name)"

    if systemctl_available; then
        systemctl status "${service_name}" --no-pager -l || true
    else
        service "${service_name}" status || true
    fi
}

enable_postgres() {
    ensure_root
    local service_name
    service_name="$(detect_service_name)"

    systemctl_available || die "当前系统未检测到 systemctl，无法设置开机自启。"
    run systemctl enable "${service_name}"
}

disable_postgres() {
    ensure_root
    local service_name
    service_name="$(detect_service_name)"

    systemctl_available || die "当前系统未检测到 systemctl，无法关闭开机自启。"
    run systemctl disable "${service_name}"
}

safe_remove_data_dir() {
    local data_dir="$1"
    local confirm_text

    if [[ -z "${data_dir}" || "${data_dir}" == "/" ]]; then
        die "拒绝删除危险目录: ${data_dir}"
    fi

    case "${data_dir}" in
        /var/lib/pgsql/*|/var/lib/postgresql/*|/var/lib/postgres/*)
            ;;
        *)
            die "拒绝删除非 PostgreSQL 默认范围的数据目录: ${data_dir}"
            ;;
    esac

    case "${data_dir}" in
        /var/lib/pgsql|/var/lib/postgresql|/var/lib/postgres)
            die "拒绝删除 PostgreSQL 根目录: ${data_dir}"
            ;;
    esac

    echo "即将永久删除数据目录: ${data_dir}"
    read -r -p "请输入 DELETE 确认删除: " confirm_text
    if [[ "${confirm_text}" != "DELETE" ]]; then
        info "未输入 DELETE，已取消删除数据目录。"
        return
    fi

    run rm -rf -- "${data_dir}"
    info "数据目录已删除: ${data_dir}"
}

uninstall_postgres() {
    ensure_root
    detect_os
    normalize_install_source

    local family source pm data_dir installed_major
    if [[ -z "${PG_VERSION}" ]]; then
        installed_major="$(detect_installed_pg_major || true)"
        if is_valid_pg_version "${installed_major}"; then
            PG_VERSION="${installed_major}"
            info "已检测到 PostgreSQL 主版本: ${PG_VERSION}"
        fi
    fi
    validate_optional_pg_version

    if ! confirm "确认卸载 PostgreSQL 软件包？服务会先停止，默认保留数据目录。" "N"; then
        info "已取消卸载。"
        return
    fi

    stop_postgres || true

    family="$(detect_distro_family)"
    source="$(resolve_install_source "${family}")"
    pm="$(detect_package_manager)"
    data_dir="$(get_data_dir)"

    case "${family}:${source}" in
        debian:pgdg)
            if [[ -n "${PG_VERSION}" ]]; then
                pkg_remove "${pm}" "postgresql-${PG_VERSION}-pgvector" "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}" postgresql-contrib postgresql || true
            else
                warn "未指定或检测到 PostgreSQL 主版本，跳过版本化 PGDG 包名。"
                pkg_remove "${pm}" postgresql-contrib postgresql || true
            fi
            ;;
        debian:system)
            pkg_remove "${pm}" postgresql-contrib postgresql || true
            ;;
        rhel:pgdg)
            if [[ -n "${PG_VERSION}" ]]; then
                pkg_remove "${pm}" "pgvector_${PG_VERSION}" "postgresql${PG_VERSION}-server" "postgresql${PG_VERSION}-contrib" "postgresql${PG_VERSION}" "postgresql${PG_VERSION}-libs" || true
            else
                warn "未指定或检测到 PostgreSQL 主版本，跳过版本化 PGDG 包名。"
            fi
            ;;
        rhel:system)
            pkg_remove "${pm}" postgresql-server postgresql-contrib postgresql || true
            ;;
        suse:*)
            if [[ -n "${PG_VERSION}" ]]; then
                pkg_remove "${pm}" postgresql-server postgresql-contrib "postgresql${PG_VERSION}-server" "postgresql${PG_VERSION}-contrib" || true
            else
                pkg_remove "${pm}" postgresql-server postgresql-contrib || true
            fi
            ;;
        arch:*)
            pkg_remove "${pm}" postgresql || true
            ;;
        *)
            warn "未知发行版族，跳过软件包卸载。"
            ;;
    esac

    if [[ -d "${data_dir}" ]] && confirm "是否同时删除数据目录 ${data_dir}？默认不删除。" "N"; then
        safe_remove_data_dir "${data_dir}"
    else
        info "已保留数据目录: ${data_dir}"
    fi

    if [[ "${family}" == "rhel" ]] && command -v rpm >/dev/null 2>&1; then
        if rpm -q pgdg-redhat-repo >/dev/null 2>&1 && confirm "是否移除 PGDG RPM 仓库包？" "N"; then
            pkg_remove "${pm}" pgdg-redhat-repo
        fi
        if rpm -q pgdg-fedora-repo >/dev/null 2>&1 && confirm "是否移除 PGDG Fedora 仓库包？" "N"; then
            pkg_remove "${pm}" pgdg-fedora-repo
        fi
    fi

    info "卸载流程完成。"
}

enable_extension_for_database() {
    ensure_root

    local db_name="${1:-}"
    local extension_sql_name="${2:-}"

    if [[ -z "${db_name}" ]]; then
        prompt_default db_name "请输入要启用扩展的数据库名" "rag_notebook"
    fi
    if [[ -z "${extension_sql_name}" ]]; then
        prompt_default extension_sql_name "请输入 SQL 扩展名，pgvector 对应 vector" "${SQL_EXTENSION_NAME}"
    fi

    validate_identifier "${db_name}" "数据库名"
    validate_extension_name "${extension_sql_name}"

    psql_as_postgres -d "${db_name}" -c "CREATE EXTENSION IF NOT EXISTS \"${extension_sql_name}\";"
    info "已在数据库 ${db_name} 中启用扩展 ${extension_sql_name}。"
}

enable_pgvector_for_database() {
    local db_name="${1:-}"
    enable_extension_for_database "${db_name}" "vector"
}

list_databases_for_menu() {
    psql_as_postgres -d postgres -Atc \
        "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY CASE WHEN datname = 'rag_notebook' THEN 0 ELSE 1 END, datname;"
}

show_database_select_menu() {
    local index=1
    local db_name

    clear 2>/dev/null || true
    print_banner_rule
    printf '  %b选择要启用扩展的数据库%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    print_banner_rule

    printf '  %b当前检测到的数据库%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    for db_name in "$@"; do
        menu_item "${index}" "${db_name}"
        index=$((index + 1))
    done

    print_menu_rule
    menu_item 98 "手动输入数据库名"
    menu_item 0 "返回上一级"
    print_menu_rule
}

show_extension_enable_menu() {
    local db_name="$1"

    clear 2>/dev/null || true
    print_banner_rule
    printf '  %b为数据库启用扩展%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    print_banner_rule
    printf '  当前数据库: %s\n' "${db_name}"
    print_menu_rule
    printf '  %b常用扩展%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    menu_item 1 "vector（pgvector 向量检索）"
    menu_item 2 "pg_trgm（三元组模糊检索）"
    menu_item 3 "uuid-ossp（UUID 生成）"
    menu_item 4 "unaccent（去重音文本处理）"
    menu_item 5 "citext（大小写不敏感文本）"
    menu_item 6 "hstore（键值存储）"
    menu_item 7 "btree_gin（GIN 索引增强）"
    menu_item 8 "btree_gist（GiST 索引增强）"
    print_menu_rule
    menu_item 98 "手动输入 SQL 扩展名"
    menu_item 0 "返回数据库选择"
    print_menu_rule
}

enable_extension_choice_menu() {
    local db_name="$1"
    local choice extension_sql_name

    while true; do
        show_extension_enable_menu "${db_name}"
        read -r -p "请选择要启用的扩展编号: " choice

        case "${choice}" in
            1) extension_sql_name="vector" ;;
            2) extension_sql_name="pg_trgm" ;;
            3) extension_sql_name="uuid-ossp" ;;
            4) extension_sql_name="unaccent" ;;
            5) extension_sql_name="citext" ;;
            6) extension_sql_name="hstore" ;;
            7) extension_sql_name="btree_gin" ;;
            8) extension_sql_name="btree_gist" ;;
            98)
                prompt_default extension_sql_name "请输入 SQL 扩展名" "${SQL_EXTENSION_NAME}"
                ;;
            0)
                return
                ;;
            *)
                warn "无效选项，请重新输入。"
                pause_if_interactive
                continue
                ;;
        esac

        enable_extension_for_database "${db_name}" "${extension_sql_name}"
        pause_if_interactive
    done
}

enable_extension_menu() {
    ensure_root

    local choice db_name database_list
    local databases=()

    if ! database_list="$(list_databases_for_menu 2>/dev/null)"; then
        die "无法读取数据库列表，请确认 PostgreSQL 正在运行且 postgres 用户可连接。"
    fi
    if [[ -z "${database_list}" ]]; then
        die "未读取到可连接的业务数据库。"
    fi
    mapfile -t databases <<<"${database_list}"

    while true; do
        show_database_select_menu "${databases[@]}"
        read -r -p "请选择数据库编号: " choice

        case "${choice}" in
            0)
                info "已返回上一级菜单。"
                return
                ;;
            98)
                prompt_default db_name "请输入数据库名" "rag_notebook"
                ;;
            ''|*[!0-9]*)
                warn "无效选项，请重新输入。"
                pause_if_interactive
                continue
                ;;
            *)
                if ((choice < 1 || choice > ${#databases[@]})); then
                    warn "无效选项，请重新输入。"
                    pause_if_interactive
                    continue
                fi
                db_name="${databases[choice - 1]}"
                ;;
        esac

        validate_identifier "${db_name}" "数据库名"
        enable_extension_choice_menu "${db_name}"
    done
}

role_exists() {
    local role_name="$1"
    local exists

    exists="$(psql_as_postgres -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${role_name}';" | tr -d '[:space:]' || true)"
    [[ "${exists}" == "1" ]]
}

database_exists() {
    local db_name="$1"
    local exists

    exists="$(psql_as_postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '${db_name}';" | tr -d '[:space:]' || true)"
    [[ "${exists}" == "1" ]]
}

set_role_password() {
    local role_name="$1"
    local label="$2"
    local password password_sql

    validate_identifier "${role_name}" "${label}"
    role_exists "${role_name}" || die "角色不存在: ${role_name}"
    read_secret password "请输入 ${role_name} 的新密码"
    [[ -n "${password}" ]] || die "密码不能为空。"
    password_sql="$(sql_literal "${password}")"

    psql_as_postgres -d postgres -c "ALTER ROLE \"${role_name}\" WITH PASSWORD '${password_sql}';"
    info "已更新角色 ${role_name} 的密码。"
}

set_postgres_password() {
    ensure_root
    set_role_password "postgres" "postgres 用户名"
}

create_database_user() {
    ensure_root

    local db_user db_password db_password_sql
    prompt_default db_user "请输入数据库用户名" "rag"
    read_secret db_password "请输入数据库用户密码"

    [[ -n "${db_password}" ]] || die "密码不能为空。"
    validate_identifier "${db_user}" "数据库用户名"
    db_password_sql="$(sql_literal "${db_password}")"

    if role_exists "${db_user}"; then
        die "角色已存在: ${db_user}"
    fi

    psql_as_postgres -d postgres -c "CREATE ROLE \"${db_user}\" WITH LOGIN PASSWORD '${db_password_sql}';"
    info "已创建数据库用户 ${db_user}。"
}

change_database_user_password() {
    ensure_root

    local db_user
    prompt_default db_user "请输入要修改密码的数据库用户名" "rag"
    set_role_password "${db_user}" "数据库用户名"
}

delete_database_user() {
    ensure_root

    local db_user
    prompt_default db_user "请输入要删除的数据库用户名" "rag"
    validate_identifier "${db_user}" "数据库用户名"

    [[ "${db_user}" != "postgres" ]] || die "拒绝删除 postgres 超级用户。"
    role_exists "${db_user}" || die "角色不存在: ${db_user}"
    if ! confirm "确认删除数据库用户 ${db_user}？如果该用户仍拥有对象，删除会失败。" "N"; then
        info "已取消删除用户。"
        return
    fi

    psql_as_postgres -d postgres -c "DROP ROLE \"${db_user}\";"
    info "已删除数据库用户 ${db_user}。"
}

list_database_users() {
    ensure_root

    psql_as_postgres -d postgres -c \
        "SELECT rolname AS role_name, rolcanlogin AS can_login, rolsuper AS superuser, rolcreatedb AS can_create_db, rolcreaterole AS can_create_role FROM pg_roles ORDER BY rolname;"
}

set_database_user_login() {
    ensure_root

    local db_user login_sql action_text
    db_user="$1"
    login_sql="$2"
    action_text="$3"

    validate_identifier "${db_user}" "数据库用户名"
    [[ "${db_user}" != "postgres" ]] || die "拒绝修改 postgres 超级用户登录状态。"
    role_exists "${db_user}" || die "角色不存在: ${db_user}"

    psql_as_postgres -d postgres -c "ALTER ROLE \"${db_user}\" ${login_sql};"
    info "已${action_text}数据库用户 ${db_user}。"
}

lock_database_user() {
    local db_user
    prompt_default db_user "请输入要锁定登录的数据库用户名" "rag"
    set_database_user_login "${db_user}" "NOLOGIN" "锁定"
}

unlock_database_user() {
    local db_user
    prompt_default db_user "请输入要恢复登录的数据库用户名" "rag"
    set_database_user_login "${db_user}" "LOGIN" "恢复登录"
}

grant_user_database_privileges() {
    ensure_root

    local db_name db_user
    prompt_default db_name "请输入要授权的数据库名" "rag_notebook"
    prompt_default db_user "请输入要授权的数据库用户名" "rag"
    validate_identifier "${db_name}" "数据库名"
    validate_identifier "${db_user}" "数据库用户名"
    database_exists "${db_name}" || die "数据库不存在: ${db_name}"
    role_exists "${db_user}" || die "角色不存在: ${db_user}"

    psql_as_postgres -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE \"${db_name}\" TO \"${db_user}\";"
    psql_as_postgres -d "${db_name}" -c "GRANT ALL ON SCHEMA public TO \"${db_user}\";" || true
    info "已为用户 ${db_user} 授权数据库 ${db_name}。"
}

revoke_user_database_privileges() {
    ensure_root

    local db_name db_user
    prompt_default db_name "请输入要撤销权限的数据库名" "rag_notebook"
    prompt_default db_user "请输入要撤销权限的数据库用户名" "rag"
    validate_identifier "${db_name}" "数据库名"
    validate_identifier "${db_user}" "数据库用户名"
    database_exists "${db_name}" || die "数据库不存在: ${db_name}"
    role_exists "${db_user}" || die "角色不存在: ${db_user}"

    if ! confirm "确认撤销用户 ${db_user} 在数据库 ${db_name} 上的常规权限？" "N"; then
        info "已取消撤销权限。"
        return
    fi

    psql_as_postgres -d "${db_name}" -c "REVOKE ALL ON SCHEMA public FROM \"${db_user}\";" || true
    psql_as_postgres -d postgres -c "REVOKE ALL PRIVILEGES ON DATABASE \"${db_name}\" FROM \"${db_user}\";"
    info "已撤销用户 ${db_user} 在数据库 ${db_name} 上的常规权限。"
}

create_database_only() {
    ensure_root

    local db_name db_owner
    prompt_default db_name "请输入数据库名" "rag_notebook"
    prompt_default db_owner "请输入数据库所有者" "postgres"
    validate_identifier "${db_name}" "数据库名"
    validate_identifier "${db_owner}" "数据库所有者"
    database_exists "${db_name}" && die "数据库已存在: ${db_name}"
    role_exists "${db_owner}" || die "角色不存在: ${db_owner}"

    run_as_postgres "$(pg_bin createdb)" -O "${db_owner}" "${db_name}"
    info "已创建数据库 ${db_name}，所有者 ${db_owner}。"
}

delete_database_only() {
    ensure_root

    local db_name confirm_text
    prompt_default db_name "请输入要删除的数据库名" "rag_notebook"
    validate_identifier "${db_name}" "数据库名"
    case "${db_name}" in
        postgres|template0|template1)
            die "拒绝删除系统数据库: ${db_name}"
            ;;
    esac
    database_exists "${db_name}" || die "数据库不存在: ${db_name}"

    echo "即将永久删除数据库: ${db_name}"
    read -r -p "请输入数据库名确认删除: " confirm_text
    if [[ "${confirm_text}" != "${db_name}" ]]; then
        info "确认文本不匹配，已取消删除数据库。"
        return
    fi

    psql_as_postgres -d postgres -c "DROP DATABASE \"${db_name}\";"
    info "已删除数据库 ${db_name}。"
}

list_databases_detail() {
    ensure_root

    psql_as_postgres -d postgres -c \
        "SELECT d.datname AS database_name, pg_catalog.pg_get_userbyid(d.datdba) AS owner, pg_size_pretty(pg_database_size(d.datname)) AS size FROM pg_database d WHERE d.datallowconn AND NOT d.datistemplate ORDER BY d.datname;"
}

change_database_owner() {
    ensure_root

    local db_name db_owner
    prompt_default db_name "请输入数据库名" "rag_notebook"
    prompt_default db_owner "请输入新的数据库所有者" "rag"
    validate_identifier "${db_name}" "数据库名"
    validate_identifier "${db_owner}" "数据库所有者"
    database_exists "${db_name}" || die "数据库不存在: ${db_name}"
    role_exists "${db_owner}" || die "角色不存在: ${db_owner}"

    psql_as_postgres -d postgres -c "ALTER DATABASE \"${db_name}\" OWNER TO \"${db_owner}\";"
    info "已将数据库 ${db_name} 的所有者改为 ${db_owner}。"
}

rename_database() {
    ensure_root

    local old_name new_name
    prompt_default old_name "请输入当前数据库名" "rag_notebook"
    prompt_default new_name "请输入新的数据库名" "rag_notebook_new"
    validate_identifier "${old_name}" "当前数据库名"
    validate_identifier "${new_name}" "新的数据库名"
    database_exists "${old_name}" || die "数据库不存在: ${old_name}"
    database_exists "${new_name}" && die "目标数据库名已存在: ${new_name}"

    psql_as_postgres -d postgres -c "ALTER DATABASE \"${old_name}\" RENAME TO \"${new_name}\";"
    info "已将数据库 ${old_name} 重命名为 ${new_name}。"
}

show_database_sizes() {
    ensure_root

    psql_as_postgres -d postgres -c \
        "SELECT datname AS database_name, pg_size_pretty(pg_database_size(datname)) AS size FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY pg_database_size(datname) DESC;"
}

show_database_connections() {
    ensure_root

    psql_as_postgres -d postgres -c \
        "SELECT datname AS database_name, usename AS user_name, state, count(*) AS connections FROM pg_stat_activity GROUP BY datname, usename, state ORDER BY datname, usename, state;"
}

terminate_database_connections() {
    ensure_root

    local db_name
    prompt_default db_name "请输入要断开连接的数据库名" "rag_notebook"
    validate_identifier "${db_name}" "数据库名"
    case "${db_name}" in
        postgres|template0|template1)
            die "拒绝批量断开系统数据库连接: ${db_name}"
            ;;
    esac
    database_exists "${db_name}" || die "数据库不存在: ${db_name}"

    if ! confirm "确认断开数据库 ${db_name} 的所有其他连接？" "N"; then
        info "已取消断开连接。"
        return
    fi

    psql_as_postgres -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${db_name}' AND pid <> pg_backend_pid();"
    info "已请求断开数据库 ${db_name} 的其他连接。"
}

show_database_privileges() {
    ensure_root

    local db_name
    prompt_default db_name "请输入要查看权限的数据库名" "rag_notebook"
    validate_identifier "${db_name}" "数据库名"
    database_exists "${db_name}" || die "数据库不存在: ${db_name}"

    psql_as_postgres -d postgres -c \
        "SELECT datname AS database_name, pg_catalog.pg_get_userbyid(datdba) AS owner, datacl AS access_privileges FROM pg_database WHERE datname = '${db_name}';"
}

show_database_user_management_menu() {
    clear 2>/dev/null || true
    print_banner_rule
    printf '  %b数据库和用户管理%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    print_banner_rule
    printf '  %b用户管理 1-9%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    menu_item 1 "初始化/重置 postgres 密码"
    menu_item 2 "新建用户"
    menu_item 3 "更改用户密码"
    menu_item 4 "删除用户"
    menu_item 5 "查看用户列表"
    menu_item 6 "锁定用户登录"
    menu_item 7 "恢复用户登录"
    menu_item 8 "授予用户数据库权限"
    menu_item 9 "撤销用户数据库权限"
    print_menu_rule
    printf '  %b数据库管理 10-19%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    menu_item 10 "新建数据库"
    menu_item 11 "删除数据库"
    menu_item 12 "查看数据库列表"
    menu_item 13 "修改数据库所有者"
    menu_item 14 "重命名数据库"
    menu_item 15 "一键创建数据库和用户"
    menu_item 16 "查看数据库大小"
    menu_item 17 "查看数据库连接"
    menu_item 18 "断开指定数据库连接"
    menu_item 19 "查看数据库权限"
    menu_item 0 "返回上一级"
    print_menu_rule
}

database_user_management_menu() {
    local choice

    while true; do
        show_database_user_management_menu
        read -r -p "请选择管理操作编号: " choice

        case "${choice}" in
            1) set_postgres_password ;;
            2) create_database_user ;;
            3) change_database_user_password ;;
            4) delete_database_user ;;
            5) list_database_users ;;
            6) lock_database_user ;;
            7) unlock_database_user ;;
            8) grant_user_database_privileges ;;
            9) revoke_user_database_privileges ;;
            10) create_database_only ;;
            11) delete_database_only ;;
            12) list_databases_detail ;;
            13) change_database_owner ;;
            14) rename_database ;;
            15) create_database_and_user ;;
            16) show_database_sizes ;;
            17) show_database_connections ;;
            18) terminate_database_connections ;;
            19) show_database_privileges ;;
            0) info "已返回上一级菜单。"; return ;;
            *) warn "无效选项，请重新输入。" ;;
        esac

        pause_if_interactive
    done
}

create_database_and_user() {
    ensure_root

    local db_name db_user db_password db_password_sql
    prompt_default db_name "请输入数据库名" "rag_notebook"
    prompt_default db_user "请输入数据库用户名" "rag"
    read_secret db_password "请输入数据库用户密码"

    [[ -n "${db_password}" ]] || die "密码不能为空。"
    validate_identifier "${db_name}" "数据库名"
    validate_identifier "${db_user}" "数据库用户名"
    db_password_sql="$(sql_literal "${db_password}")"

    if role_exists "${db_user}"; then
        info "角色 ${db_user} 已存在，正在更新密码。"
        psql_as_postgres -d postgres -c "ALTER ROLE \"${db_user}\" WITH LOGIN PASSWORD '${db_password_sql}';"
    else
        info "正在创建角色 ${db_user}。"
        psql_as_postgres -d postgres -c "CREATE ROLE \"${db_user}\" WITH LOGIN PASSWORD '${db_password_sql}';"
    fi

    if database_exists "${db_name}"; then
        info "数据库 ${db_name} 已存在，跳过创建。"
    else
        info "正在创建数据库 ${db_name}。"
        run_as_postgres "$(pg_bin createdb)" -O "${db_user}" "${db_name}"
    fi

    psql_as_postgres -d "${db_name}" -c "GRANT ALL PRIVILEGES ON DATABASE \"${db_name}\" TO \"${db_user}\";"
    psql_as_postgres -d "${db_name}" -c "GRANT ALL ON SCHEMA public TO \"${db_user}\";" || true

    if confirm "是否为数据库 ${db_name} 启用 pgvector 扩展？" "Y"; then
        enable_pgvector_for_database "${db_name}"
    fi

    info "数据库和用户处理完成。"
}

configure_remote_access() {
    ensure_root

    local config_dir conf_file hba_file listen_addr cidr auth_method default_auth major hba_line
    config_dir="$(get_config_dir)"
    conf_file="${config_dir}/postgresql.conf"
    hba_file="${config_dir}/pg_hba.conf"

    [[ -f "${conf_file}" ]] || die "未找到 postgresql.conf: ${conf_file}"
    [[ -f "${hba_file}" ]] || die "未找到 pg_hba.conf: ${hba_file}"

    major="$(detect_installed_pg_major)"
    if [[ "${major}" =~ ^[0-9]+$ ]] && (( major >= 10 )); then
        default_auth="scram-sha-256"
    else
        default_auth="md5"
    fi

    prompt_default listen_addr "监听地址，* 表示监听所有网卡" "*"
    prompt_default cidr "允许访问的客户端 CIDR" "0.0.0.0/0"
    prompt_default auth_method "认证方式" "${default_auth}"

    [[ "${listen_addr}" != *"'"* ]] || die "监听地址不能包含单引号。"
    [[ "${cidr}" != *" "* ]] || die "CIDR 不能包含空格。"
    case "${auth_method}" in
        scram-sha-256|md5|password|trust|cert|ident)
            ;;
        *)
            die "不支持的认证方式: ${auth_method}"
            ;;
    esac

    info "正在备份配置文件。"
    run cp -a "${conf_file}" "${conf_file}.bak.$(date +%Y%m%d%H%M%S)"
    run cp -a "${hba_file}" "${hba_file}.bak.$(date +%Y%m%d%H%M%S)"

    if grep -Eq "^[#[:space:]]*listen_addresses[[:space:]]*=" "${conf_file}"; then
        run sed -ri "s|^[#[:space:]]*listen_addresses[[:space:]]*=.*|listen_addresses = '${listen_addr}'|" "${conf_file}"
    else
        printf "\nlisten_addresses = '%s'\n" "${listen_addr}" >>"${conf_file}"
    fi

    hba_line="host    all             all             ${cidr}            ${auth_method}"
    if grep -Fqx "${hba_line}" "${hba_file}"; then
        info "pg_hba.conf 中已存在相同访问规则，跳过追加。"
    else
        printf "\n# Added by manage_postgresql_linux.sh\n%s\n" "${hba_line}" >>"${hba_file}"
        info "已追加访问规则: ${hba_line}"
    fi

    if confirm "配置已修改，是否立即重启 PostgreSQL？" "Y"; then
        restart_postgres
    else
        warn "配置需要重启或 reload 后才会生效。"
    fi
}

backup_database() {
    ensure_root

    local db_name output_dir output_file dump_tool
    prompt_default db_name "请输入要备份的数据库名" "rag_notebook"
    validate_identifier "${db_name}" "数据库名"

    output_dir="/var/backups/postgresql"
    output_file="${output_dir}/${db_name}_$(date +%Y%m%d_%H%M%S).dump"
    dump_tool="$(pg_bin pg_dump)"

    run mkdir -p "${output_dir}"
    info "正在备份数据库 ${db_name} 到 ${output_file}"
    run_as_postgres "${dump_tool}" -Fc "${db_name}" >"${output_file}"
    run chmod 600 "${output_file}"
    info "备份完成: ${output_file}"
}

restore_database() {
    ensure_root

    local db_name input_file restore_tool psql_tool
    prompt_default db_name "请输入要恢复到的数据库名" "rag_notebook"
    prompt_default input_file "请输入备份文件路径" ""

    validate_identifier "${db_name}" "数据库名"
    [[ -f "${input_file}" ]] || die "备份文件不存在: ${input_file}"

    if ! confirm "恢复会覆盖或追加数据到数据库 ${db_name}，确认继续？" "N"; then
        info "已取消恢复。"
        return
    fi

    restore_tool="$(pg_bin pg_restore)"
    psql_tool="$(pg_bin psql)"

    case "${input_file}" in
        *.dump|*.backup|*.pgdump)
            run_as_postgres "${restore_tool}" --clean --if-exists -d "${db_name}" "${input_file}"
            ;;
        *)
            run_as_postgres "${psql_tool}" -v ON_ERROR_STOP=1 -d "${db_name}" -f "${input_file}"
            ;;
    esac

    info "恢复完成。"
}

show_logs() {
    local service_name lines
    service_name="$(detect_service_name)"
    prompt_default lines "请输入要查看的日志行数" "100"
    [[ "${lines}" =~ ^[0-9]+$ ]] || die "日志行数必须是数字。"

    if systemctl_available && command -v journalctl >/dev/null 2>&1; then
        journalctl -u "${service_name}" -n "${lines}" --no-pager
    else
        warn "未检测到 journalctl，请查看 PostgreSQL 数据目录下的 log 目录或系统日志。"
    fi
}

get_service_active_status() {
    local service_name="$1"
    local raw

    if systemctl_available; then
        raw="$(systemctl is-active "${service_name}" 2>/dev/null || true)"
        case "${raw}" in
            active) echo "运行中" ;;
            activating) echo "启动中" ;;
            deactivating) echo "停止中" ;;
            inactive) echo "已停止" ;;
            failed) echo "异常" ;;
            unknown|"") echo "未找到" ;;
            *) echo "${raw}" ;;
        esac
        return
    fi

    if command -v service >/dev/null 2>&1; then
        if service "${service_name}" status >/dev/null 2>&1; then
            echo "运行中"
        else
            echo "已停止或未知"
        fi
        return
    fi

    echo "无法检测"
}

get_service_enabled_status() {
    local service_name="$1"
    local raw

    if ! systemctl_available; then
        echo "无法检测"
        return
    fi

    raw="$(systemctl is-enabled "${service_name}" 2>/dev/null || true)"
    case "${raw}" in
        enabled) echo "已启用" ;;
        disabled) echo "未启用" ;;
        masked) echo "已屏蔽" ;;
        static) echo "静态" ;;
        indirect) echo "间接" ;;
        generated) echo "生成" ;;
        transient) echo "临时" ;;
        alias) echo "别名" ;;
        unknown|"") echo "未找到" ;;
        *) echo "${raw}" ;;
    esac
}

get_pg_ready_status() {
    local pg_isready_path ready_text

    pg_isready_path="$(pg_bin pg_isready)"
    if [[ -x "${pg_isready_path}" ]] || command -v "${pg_isready_path}" >/dev/null 2>&1; then
        ready_text="$("${pg_isready_path}" -t 1 2>/dev/null || true)"
        case "${ready_text}" in
            *"accepting connections"*) echo "可连接" ;;
            *"rejecting connections"*) echo "拒绝连接" ;;
            *"no response"*) echo "无响应" ;;
            "") echo "无法检测" ;;
            *) echo "${ready_text}" ;;
        esac
        return
    fi

    echo "未检测"
}

get_psql_version_summary() {
    local psql_path version_text

    psql_path="$(pg_bin psql)"
    if [[ -x "${psql_path}" ]] || command -v "${psql_path}" >/dev/null 2>&1; then
        version_text="$("${psql_path}" --version 2>/dev/null || true)"
        echo "${version_text:-无法读取}"
        return
    fi

    echo "未安装"
}

status_color() {
    local value="$1"

    case "${value}" in
        运行中|已启用|可连接)
            printf '%s' "${STYLE_GREEN}"
            ;;
        启动中|停止中|静态|间接|生成|临时|别名|未检测|无法检测|未知)
            printf '%s' "${STYLE_YELLOW}"
            ;;
        已停止|已停止或未知|异常|未启用|已屏蔽|未找到|拒绝连接|无响应|未安装)
            printf '%s' "${STYLE_RED}"
            ;;
        *)
            printf '%s' "${STYLE_CYAN}"
            ;;
    esac
}

print_status_value() {
    local value="$1"
    local color

    color="$(status_color "${value}")"
    printf '%b%s%b' "${color}" "${value}" "${STYLE_RESET}"
}

print_banner_rule() {
    printf '%b%s%b\n' "${STYLE_BLUE}" "============================================================" "${STYLE_RESET}"
}

print_menu_rule() {
    printf '%b%s%b\n' "${STYLE_DIM}" "------------------------------------------------------------" "${STYLE_RESET}"
}

menu_item() {
    local number="$1"
    local text="$2"

    printf '  %b[%2s]%b %s\n' "${STYLE_CYAN}" "${number}" "${STYLE_RESET}" "${text}"
}

show_banner() {
    local service_name data_dir family source pm active_status enabled_status ready_status psql_version

    detect_os
    family="$(detect_distro_family)"
    source="$(resolve_install_source "${family}")"
    pm="$(detect_package_manager_or_unknown)"
    service_name="$(detect_service_name)"
    data_dir="$(get_data_dir)"
    active_status="$(get_service_active_status "${service_name}")"
    enabled_status="$(get_service_enabled_status "${service_name}")"
    ready_status="$(get_pg_ready_status)"
    psql_version="$(get_psql_version_summary)"

    clear 2>/dev/null || true
    print_banner_rule
    printf '  %bLinux PostgreSQL 中文管理工具%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    print_banner_rule
    printf '  当前状态: 服务 '
    print_status_value "${active_status}"
    printf ' | 自启 '
    print_status_value "${enabled_status}"
    printf ' | 连接 '
    print_status_value "${ready_status}"
    printf '\n'
    print_menu_rule
    printf '  系统: %s %s | 发行版族: %s | 包管理器: %s\n' "${OS_NAME}" "${OS_VERSION_ID:-}" "${family}" "${pm}"
    printf '  安装源: %s (实际: %s) | 目标版本: %s\n' "${INSTALL_SOURCE}" "${source}" "${PG_VERSION:-未指定}"
    printf '  服务名: %s\n' "${service_name}"
    printf '  psql: %s\n' "${psql_version}"
    printf '  数据目录: %s\n' "${data_dir}"
    print_menu_rule
}

show_detected_info() {
    local service_name data_dir config_dir family source pm psql_path psql_version active_status enabled_status ready_status

    detect_os
    family="$(detect_distro_family)"
    source="$(resolve_install_source "${family}")"
    pm="$(detect_package_manager_or_unknown)"
    service_name="$(detect_service_name)"
    data_dir="$(get_data_dir)"
    config_dir="$(get_config_dir)"
    active_status="$(get_service_active_status "${service_name}")"
    enabled_status="$(get_service_enabled_status "${service_name}")"
    ready_status="$(get_pg_ready_status)"
    psql_path="$(pg_bin psql)"
    psql_version="未检测到 psql"

    if [[ -x "${psql_path}" ]] || command -v "${psql_path}" >/dev/null 2>&1; then
        psql_version="$("${psql_path}" --version 2>/dev/null || echo "无法读取 psql 版本")"
    fi

    echo "系统名称: ${OS_NAME}"
    echo "系统版本: ${OS_VERSION_ID:-未知}"
    echo "发行版 ID: ${OS_ID}"
    echo "发行版族: ${family}"
    echo "包管理器: ${pm}"
    echo "安装源: ${INSTALL_SOURCE} (实际: ${source})"
    echo "目标 PG 主版本: ${PG_VERSION:-未指定}"
    echo "服务名: ${service_name}"
    echo "服务状态: ${active_status}"
    echo "开机自启: ${enabled_status}"
    echo "连接探测: ${ready_status}"
    echo "数据目录: ${data_dir}"
    echo "配置目录: ${config_dir}"
    echo "psql: ${psql_version}"
}

show_menu() {
    printf '  %b基础操作%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    menu_item 1 "启动 PostgreSQL"
    menu_item 2 "停止 PostgreSQL"
    menu_item 3 "重启 PostgreSQL"
    menu_item 4 "重载配置"
    menu_item 5 "查看运行状态"
    menu_item 6 "设置开机自启"
    menu_item 7 "关闭开机自启"
    menu_item 8 "查看服务日志"
    menu_item 9 "查看系统识别信息"
    print_menu_rule
    printf '  %b安装 / 设置 / 数据维护%b\n' "${STYLE_BOLD}" "${STYLE_RESET}"
    menu_item 10 "安装 PostgreSQL（选择版本）"
    menu_item 11 "卸载 PostgreSQL"
    menu_item 12 "初始化数据目录"
    menu_item 13 "扩展安装菜单"
    menu_item 14 "为数据库启用扩展菜单"
    menu_item 15 "数据库和用户管理"
    menu_item 16 "配置远程连接"
    menu_item 17 "备份数据库"
    menu_item 18 "恢复数据库"
    menu_item 19 "查看帮助说明"
    print_menu_rule
    menu_item 0 "退出"
    print_menu_rule
}

main_menu() {
    local choice

    while true; do
        show_banner
        show_menu
        read -r -p "请选择操作编号: " choice

        case "${choice}" in
            1) start_postgres ;;
            2) stop_postgres ;;
            3) restart_postgres ;;
            4) reload_postgres ;;
            5) status_postgres ;;
            6) enable_postgres ;;
            7) disable_postgres ;;
            8) show_logs ;;
            9) show_detected_info ;;
            10) install_postgres ;;
            11) uninstall_postgres ;;
            12) initdb_postgres ;;
            13) install_extension_menu; continue ;;
            14) enable_extension_menu; continue ;;
            15) database_user_management_menu; continue ;;
            16) configure_remote_access ;;
            17) backup_database ;;
            18) restore_database ;;
            19) usage ;;
            0) echo "已退出。"; exit 0 ;;
            *) warn "无效选项，请重新输入。" ;;
        esac

        pause_if_interactive
    done
}

usage() {
    cat <<EOF
用法:
  sudo bash scripts/manage_postgresql_linux.sh [选项] [命令]

不输入命令时会进入中文数字菜单，推荐日常使用:
  0      退出
  1-9    PostgreSQL 基础操作，例如启动、停止、重启、状态、自启、日志
  10-19  安装、卸载、扩展、数据库用户、远程连接、备份恢复等设置操作

命令:
  menu              打开中文菜单，默认命令
  install           安装 PostgreSQL，交互模式会要求输入主版本
  uninstall         卸载 PostgreSQL
  initdb            初始化数据目录
  start             启动服务
  stop              停止服务
  restart           重启服务
  reload            重载配置
  status            查看状态
  enable            设置开机自启
  disable           关闭开机自启
  config            配置远程连接
  create-db         创建数据库和用户，兼容旧快捷命令
  db-user-menu      打开数据库和用户管理菜单
  install-extension 打开扩展安装子菜单；也可配合 --extension 指定扩展包
  enable-extension  为数据库启用扩展，默认 vector
  install-vector    安装 pgvector 扩展包，兼容别名
  enable-vector     为数据库启用 pgvector，兼容别名
  backup            备份数据库
  restore           恢复数据库
  logs              查看日志
  info              查看系统识别信息
  help              查看帮助

选项:
  -y, --yes                    使用默认选项自动确认，危险操作仍可能要求输入 DELETE
  --pg-version VERSION         指定 PostgreSQL 主版本，例如 16；非交互 install 必填
  --source SOURCE              指定安装源: auto、system 或 pgdg
  --service SERVICE            指定服务名，例如 postgresql-16
  --extension EXTENSION        指定 install-extension 要安装的扩展包，例如 pgvector
  --sql-extension EXTENSION    指定 enable-extension 默认 SQL 扩展名，例如 vector
  -h, --help                   查看帮助

示例:
  sudo bash scripts/manage_postgresql_linux.sh
  # 进入菜单后直接输入数字，例如 1 启动、3 重启、10 安装、13 进入扩展安装菜单
  sudo bash scripts/manage_postgresql_linux.sh install
  # 安装时会要求输入 PostgreSQL 主版本，不再默认使用固定版本
  sudo bash scripts/manage_postgresql_linux.sh --pg-version 16 --source pgdg install
  sudo bash scripts/manage_postgresql_linux.sh db-user-menu
  sudo bash scripts/manage_postgresql_linux.sh install-extension
  sudo bash scripts/manage_postgresql_linux.sh enable-extension
  sudo bash scripts/manage_postgresql_linux.sh status
EOF
}

parse_args() {
    ACTION="menu"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                ASSUME_YES=1
                shift
                ;;
            --pg-version)
                [[ $# -ge 2 ]] || die "--pg-version 缺少参数。"
                PG_VERSION="$2"
                shift 2
                ;;
            --source)
                [[ $# -ge 2 ]] || die "--source 缺少参数。"
                INSTALL_SOURCE="$2"
                shift 2
                ;;
            --service)
                [[ $# -ge 2 ]] || die "--service 缺少参数。"
                PG_SERVICE="$2"
                shift 2
                ;;
            --extension)
                [[ $# -ge 2 ]] || die "--extension 缺少参数。"
                EXTENSION_NAME="$2"
                shift 2
                ;;
            --sql-extension)
                [[ $# -ge 2 ]] || die "--sql-extension 缺少参数。"
                SQL_EXTENSION_NAME="$2"
                shift 2
                ;;
            -h|--help|help)
                ACTION="help"
                shift
                ;;
            *)
                ACTION="$1"
                shift
                ;;
        esac
    done
}

dispatch() {
    detect_os
    normalize_install_source
    validate_optional_pg_version

    case "${ACTION}" in
        menu) main_menu ;;
        1) start_postgres ;;
        2) stop_postgres ;;
        3) restart_postgres ;;
        4) reload_postgres ;;
        5) status_postgres ;;
        6) enable_postgres ;;
        7) disable_postgres ;;
        8) show_logs ;;
        9) show_detected_info ;;
        10) install_postgres ;;
        11) uninstall_postgres ;;
        12) initdb_postgres ;;
        13) install_extension_menu ;;
        14) enable_extension_menu ;;
        15) database_user_management_menu ;;
        16) configure_remote_access ;;
        17) backup_database ;;
        18) restore_database ;;
        19) usage ;;
        0) echo "已退出。" ;;
        install) install_postgres ;;
        uninstall) uninstall_postgres ;;
        initdb) initdb_postgres ;;
        start) start_postgres ;;
        stop) stop_postgres ;;
        restart) restart_postgres ;;
        reload) reload_postgres ;;
        status) status_postgres ;;
        enable) enable_postgres ;;
        disable) disable_postgres ;;
        config) configure_remote_access ;;
        create-db) create_database_and_user ;;
        db-user-menu) database_user_management_menu ;;
        install-extension) install_extension_package ;;
        enable-extension) enable_extension_for_database ;;
        install-vector) install_pgvector_package ;;
        enable-vector) enable_pgvector_for_database ;;
        backup) backup_database ;;
        restore) restore_database ;;
        logs) show_logs ;;
        info) show_detected_info ;;
        help) usage ;;
        *)
            usage
            die "未知命令: ${ACTION}"
            ;;
    esac
}

parse_args "$@"
init_style
dispatch
