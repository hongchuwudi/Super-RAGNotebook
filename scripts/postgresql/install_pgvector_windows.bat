@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "NO_PAUSE="
if /I "%~1"=="--no-pause" (
    set "NO_PAUSE=1"
    shift /1
)

if /I "%~1"=="/?" goto Usage
if /I "%~1"=="--help" goto Usage
if /I "%~1"=="-h" goto Usage

set "PGVECTOR_REPO=https://github.com/pgvector/pgvector.git"
set "PGVECTOR_FALLBACK_VERSION=v0.8.3"
set "PGVECTOR_VERSION=%PGVECTOR_VERSION%"
if defined PGVECTOR_VERSION call :NormalizePgvectorVersion
set "WORK_DIR=%TEMP%\pgvector-install-%RANDOM%%RANDOM%"
set "SELECTED_PGROOT="
set "DETECTED_PGROOT="

echo.
echo pgvector Windows PostgreSQL 快速安装器
echo --------------------------------------
if defined PGVECTOR_VERSION (
    echo 版本: %PGVECTOR_VERSION%  ^(由 PGVECTOR_VERSION 指定^)
) else (
    echo 版本: 自动获取 pgvector 最新稳定版本
)
echo.

call :EnsureNmakeAvailable
if errorlevel 1 (
    echo 错误: 尝试加载 Visual Studio C++ 环境后仍未找到 nmake。
    echo 如果已安装 Visual Studio Build Tools，请用管理员身份打开 "x64 Native Tools Command Prompt for VS" 后重新运行本脚本。
    echo 如果尚未安装，请在 Visual Studio Installer 中安装 "使用 C++ 的桌面开发"。
    set "SCRIPT_EXIT_CODE=1"
    goto Finish
)

where git >nul 2>nul
if errorlevel 1 (
    echo 错误: PATH 中未找到 git。
    echo 请安装 Git for Windows，或将 git.exe 加入 PATH 后重新运行本脚本。
    set "SCRIPT_EXIT_CODE=1"
    goto Finish
)

net session >nul 2>nul
if errorlevel 1 (
    echo 警告: 当前窗口似乎不是以管理员身份运行。
    echo 如果 PostgreSQL 安装在 "Program Files" 下，执行 "nmake install" 时可能会因为权限不足而失败。
    echo.
)

if defined PGROOT (
    echo 检测到当前会话中的 PGROOT 环境变量:
    echo   "%PGROOT%"
    call :ValidatePgRoot "%PGROOT%"
    if errorlevel 1 (
        echo 警告: 当前 PGROOT 无效，将继续尝试自动探测 PostgreSQL 安装目录。
        echo.
    ) else (
        call :ConfirmOrEditPgRoot "%PGROOT%"
        if defined CONFIRMED_PGROOT set "SELECTED_PGROOT=!CONFIRMED_PGROOT!"
    )
)

if not defined SELECTED_PGROOT (
    call :DetectPgRoot
    if defined DETECTED_PGROOT (
        echo 检测到 PostgreSQL 根目录候选路径:
        echo   "!DETECTED_PGROOT!"
        call :ConfirmOrEditPgRoot "!DETECTED_PGROOT!"
        if defined CONFIRMED_PGROOT set "SELECTED_PGROOT=!CONFIRMED_PGROOT!"
    )
)

if not defined SELECTED_PGROOT (
    call :PromptPgRoot
    if errorlevel 1 (
        set "SCRIPT_EXIT_CODE=1"
        goto Finish
    )
)

call :ValidatePgRoot "%SELECTED_PGROOT%"
if errorlevel 1 (
    set "SCRIPT_EXIT_CODE=1"
    goto Finish
)

set "PGROOT=%SELECTED_PGROOT%"

call :EnsurePgrootEnvironmentVariable
if errorlevel 1 (
    set "SCRIPT_EXIT_CODE=1"
    goto Finish
)

call :ResolvePgvectorVersion
if errorlevel 1 (
    set "SCRIPT_EXIT_CODE=1"
    goto Finish
)

call :DetectInstalledPgvectorVersion
call :ConfirmInstallOrUpdate
if not defined SHOULD_INSTALL (
    set "SCRIPT_EXIT_CODE=0"
    goto Finish
)

echo.
echo 将使用 PGROOT:
echo   "%PGROOT%"
echo 目标 pgvector 版本:
echo   "%PGVECTOR_VERSION%"
echo.
echo 安装器会将 pgvector 克隆到:
echo   "%WORK_DIR%"

mkdir "%WORK_DIR%" >nul 2>nul
if errorlevel 1 (
    echo 错误: 创建工作目录失败:
    echo   "%WORK_DIR%"
    set "SCRIPT_EXIT_CODE=1"
    goto Finish
)

pushd "%WORK_DIR%"
echo.
echo 正在克隆 pgvector...
call :ValidatePgvectorVersion
if errorlevel 1 (
    popd
    set "SCRIPT_EXIT_CODE=1"
    goto Finish
)
echo 使用 Git tag: %PGVECTOR_VERSION%
git clone --depth 1 --branch "%PGVECTOR_VERSION%" "%PGVECTOR_REPO%" pgvector
if errorlevel 1 (
    popd
    echo 错误: 克隆 pgvector 失败。
    set "SCRIPT_EXIT_CODE=1"
    goto Finish
)

cd pgvector
echo.
echo 正在编译 pgvector...
nmake /F Makefile.win
if errorlevel 1 (
    popd
    echo 错误: 编译失败。
    echo 可能原因包括: 当前 pgvector 版本不兼容此 PostgreSQL 版本，或本机 C++ 编译环境不完整。
    echo 如需回退到指定版本，可先执行:
    echo   set PGVECTOR_VERSION=v0.8.3
    echo 然后重新运行本脚本。
    set "SCRIPT_EXIT_CODE=1"
    goto Finish
)

echo.
echo 正在将 pgvector 安装到 PGROOT...
nmake /F Makefile.win install
if errorlevel 1 (
    popd
    echo 错误: 安装失败。
    echo 如果 PGROOT 位于 "Program Files" 下，请用管理员身份重新运行本脚本。
    set "SCRIPT_EXIT_CODE=1"
    goto Finish
)
popd

echo.
if not defined OPERATION_NAME set "OPERATION_NAME=安装"
echo pgvector 文件已%OPERATION_NAME%成功。
echo.
echo 接下来需要在每个要使用 pgvector 的数据库中启用扩展，例如:
echo   "%PGROOT%\bin\psql.exe" -U postgres -d rag_notebook -c "CREATE EXTENSION IF NOT EXISTS vector;"
echo.
echo 如果数据库中已经启用过 vector 扩展，更新文件后还需要在对应数据库中执行:
echo   "%PGROOT%\bin\psql.exe" -U postgres -d rag_notebook -c "ALTER EXTENSION vector UPDATE;"
echo.
echo 可使用以下命令验证:
echo   "%PGROOT%\bin\psql.exe" -U postgres -d rag_notebook -c "SELECT extversion FROM pg_extension WHERE extname = 'vector';"
echo.
set "SCRIPT_EXIT_CODE=0"
goto Finish

:ResolvePgvectorVersion
if defined PGVECTOR_VERSION (
    call :ValidatePgvectorVersion
    if errorlevel 1 exit /b 1
    echo.
    echo 使用用户指定的 pgvector 版本: %PGVECTOR_VERSION%
    exit /b 0
)

if defined PG_MAJOR (
    if !PG_MAJOR! LSS 13 (
        echo 错误: 当前 PostgreSQL 主版本为 !PG_MAJOR!，pgvector 通常要求 PostgreSQL 13 或更高版本。
        exit /b 1
    )
)

echo.
echo 正在从 GitHub 获取 pgvector 最新稳定版本...
for /f "usebackq delims=" %%T in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$repo='%PGVECTOR_REPO%'; $tags = git ls-remote --tags --refs $repo 2>$null | ForEach-Object { if ($_ -match 'refs/tags/(v?\d+\.\d+\.\d+)$') { $Matches[1] } }; if ($tags) { $tags | Sort-Object { [version]($_.TrimStart('v')) } -Descending | Select-Object -First 1 }"`) do (
    set "PGVECTOR_VERSION=%%T"
)

if defined PGVECTOR_VERSION (
    call :ValidatePgvectorVersion
    if errorlevel 1 exit /b 1
    echo 已选择 pgvector 最新稳定版本: %PGVECTOR_VERSION%
    exit /b 0
)

echo 警告: 未能从 GitHub 获取 pgvector 最新版本，可能是网络不可用或 GitHub 无法访问。
echo 可手动设置 PGVECTOR_VERSION 指定版本，例如:
echo   set PGVECTOR_VERSION=v0.8.3
echo.
set /p "USE_FALLBACK_VERSION=是否使用保守回退版本 %PGVECTOR_FALLBACK_VERSION% 继续? [Y/N]: "
if not defined USE_FALLBACK_VERSION set "USE_FALLBACK_VERSION=Y"
if /I "%USE_FALLBACK_VERSION%"=="Y" (
    set "PGVECTOR_VERSION=%PGVECTOR_FALLBACK_VERSION%"
    call :ValidatePgvectorVersion
    if errorlevel 1 exit /b 1
    echo 将使用回退版本: !PGVECTOR_VERSION!
    exit /b 0
)
if /I "%USE_FALLBACK_VERSION%"=="YES" (
    set "PGVECTOR_VERSION=%PGVECTOR_FALLBACK_VERSION%"
    call :ValidatePgvectorVersion
    if errorlevel 1 exit /b 1
    echo 将使用回退版本: !PGVECTOR_VERSION!
    exit /b 0
)

echo 已取消安装。请联网后重试，或设置 PGVECTOR_VERSION 后再运行。
exit /b 1

:EnsurePgrootEnvironmentVariable
set "PERSISTED_PGROOT="
set "PERSISTED_PGROOT_SCOPE="
call :ReadPersistedPgroot "HKCU\Environment" "用户"
if not defined PERSISTED_PGROOT call :ReadPersistedPgroot "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "系统"

echo.
if not defined PERSISTED_PGROOT (
    echo 当前用户/系统环境变量中尚未找到名为 PGROOT 的持久化变量。
    echo 将把本次确认的 PostgreSQL 根目录写入当前用户环境变量 PGROOT:
    echo   "!PGROOT!"
    setx PGROOT "!PGROOT!" >nul
    if errorlevel 1 (
        echo 错误: 写入用户环境变量 PGROOT 失败。
        echo 你仍可以在当前窗口继续安装，但后续新终端可能无法自动获取 PGROOT。
        exit /b 1
    )
    echo 已写入用户环境变量 PGROOT。新打开的终端会自动生效。
    exit /b 0
)

echo 已检测到!PERSISTED_PGROOT_SCOPE!环境变量 PGROOT:
echo   "!PERSISTED_PGROOT!"
if /I "!PERSISTED_PGROOT!"=="!PGROOT!" (
    echo 环境变量 PGROOT 与本次确认路径一致。
    exit /b 0
)

echo 该值与本次确认的 PGROOT 不一致:
echo   本次确认: "!PGROOT!"
set "UPDATE_PGROOT_ENV="
set /p "UPDATE_PGROOT_ENV=是否将用户环境变量 PGROOT 更新为本次确认路径? [Y/N]: "
if /I "!UPDATE_PGROOT_ENV!"=="Y" goto WriteUserPgrootEnv
if /I "!UPDATE_PGROOT_ENV!"=="YES" goto WriteUserPgrootEnv
echo 已保留现有环境变量；当前脚本仍会使用本次确认的 PGROOT。
exit /b 0

:WriteUserPgrootEnv
setx PGROOT "!PGROOT!" >nul
if errorlevel 1 (
    echo 错误: 更新用户环境变量 PGROOT 失败。
    exit /b 1
)
echo 已更新用户环境变量 PGROOT。新打开的终端会自动生效。
exit /b 0

:ReadPersistedPgroot
set "READ_ENV_KEY=%~1"
set "READ_ENV_SCOPE=%~2"
for /f "tokens=2,*" %%A in ('reg query "%READ_ENV_KEY%" /v PGROOT 2^>nul ^| findstr /I "PGROOT"') do (
    if /I "%%A"=="REG_SZ" (
        set "PERSISTED_PGROOT=%%B"
        set "PERSISTED_PGROOT_SCOPE=%READ_ENV_SCOPE%"
        exit /b 0
    )
    if /I "%%A"=="REG_EXPAND_SZ" (
        set "PERSISTED_PGROOT=%%B"
        set "PERSISTED_PGROOT_SCOPE=%READ_ENV_SCOPE%"
        exit /b 0
    )
)
exit /b 0

:NormalizePgvectorVersion
if not defined PGVECTOR_VERSION exit /b 0
for %%V in ("!PGVECTOR_VERSION!") do set "PGVECTOR_VERSION=%%~V"
:NormalizePgvectorVersionTrimStart
if "!PGVECTOR_VERSION:~0,1!"==" " (
    set "PGVECTOR_VERSION=!PGVECTOR_VERSION:~1!"
    goto NormalizePgvectorVersionTrimStart
)
:NormalizePgvectorVersionTrimEnd
if "!PGVECTOR_VERSION:~-1!"==" " (
    set "PGVECTOR_VERSION=!PGVECTOR_VERSION:~0,-1!"
    goto NormalizePgvectorVersionTrimEnd
)
if "!PGVECTOR_VERSION:~0,1!"=="'" set "PGVECTOR_VERSION=!PGVECTOR_VERSION:~1!"
if "!PGVECTOR_VERSION:~-1!"=="'" set "PGVECTOR_VERSION=!PGVECTOR_VERSION:~0,-1!"
exit /b 0

:ValidatePgvectorVersion
call :NormalizePgvectorVersion
if not defined PGVECTOR_VERSION (
    echo 错误: pgvector 目标版本为空，已停止克隆。
    echo 可手动指定版本后重试，例如:
    echo   set PGVECTOR_VERSION=v0.8.3
    exit /b 1
)
echo(!PGVECTOR_VERSION!| findstr /R "^v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
if not errorlevel 1 exit /b 0
echo(!PGVECTOR_VERSION!| findstr /R "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
if not errorlevel 1 (
    set "PGVECTOR_VERSION=v!PGVECTOR_VERSION!"
    exit /b 0
)
echo 错误: pgvector 版本格式无效: "!PGVECTOR_VERSION!"
echo 版本应类似 v0.8.3 或 0.8.3。
exit /b 1

:DetectInstalledPgvectorVersion
set "PGVECTOR_INSTALLED_VERSION="
set "PGVECTOR_CONTROL_FILE=%PGROOT%\share\extension\vector.control"
if exist "%PGVECTOR_CONTROL_FILE%" (
    for /f "tokens=1,* delims==" %%A in ('findstr /I /B /C:"default_version" "%PGVECTOR_CONTROL_FILE%" 2^>nul') do (
        set "PGVECTOR_INSTALLED_VERSION=%%B"
    )
)
if defined PGVECTOR_INSTALLED_VERSION (
    set "PGVECTOR_VERSION_SAVED=!PGVECTOR_VERSION!"
    set "PGVECTOR_VERSION=!PGVECTOR_INSTALLED_VERSION!"
    call :NormalizePgvectorVersion
    set "PGVECTOR_INSTALLED_VERSION=!PGVECTOR_VERSION!"
    set "PGVECTOR_VERSION=!PGVECTOR_VERSION_SAVED!"
    set "PGVECTOR_VERSION_SAVED="
    if /I not "!PGVECTOR_INSTALLED_VERSION:~0,1!"=="v" set "PGVECTOR_INSTALLED_VERSION=v!PGVECTOR_INSTALLED_VERSION!"
)
exit /b 0

:ConfirmInstallOrUpdate
set "SHOULD_INSTALL="
set "OPERATION_NAME=安装"

echo.
if defined PGVECTOR_INSTALLED_VERSION (
    echo 检测到已安装 pgvector 文件版本: !PGVECTOR_INSTALLED_VERSION!
) else (
    echo 未检测到已安装的 pgvector 扩展文件，将执行全新安装。
)
echo 目标 pgvector 版本: %PGVECTOR_VERSION%

if not defined PGVECTOR_INSTALLED_VERSION (
    set /p "CONTINUE_INSTALL=是否继续安装? [Y/N]: "
    if not defined CONTINUE_INSTALL set "CONTINUE_INSTALL=Y"
    if /I "!CONTINUE_INSTALL!"=="Y" set "SHOULD_INSTALL=1"
    if /I "!CONTINUE_INSTALL!"=="YES" set "SHOULD_INSTALL=1"
    if defined SHOULD_INSTALL (
        set "OPERATION_NAME=安装"
    ) else (
        echo 已取消安装。
    )
    exit /b 0
)

call :CompareVersions "!PGVECTOR_INSTALLED_VERSION!" "%PGVECTOR_VERSION%"
if /I "!VERSION_COMPARE!"=="LT" (
    set "OPERATION_NAME=更新"
    set /p "CONTINUE_INSTALL=检测到可更新版本，是否从 !PGVECTOR_INSTALLED_VERSION! 更新到 %PGVECTOR_VERSION%? [Y/N]: "
    if not defined CONTINUE_INSTALL set "CONTINUE_INSTALL=Y"
    if /I "!CONTINUE_INSTALL!"=="Y" set "SHOULD_INSTALL=1"
    if /I "!CONTINUE_INSTALL!"=="YES" set "SHOULD_INSTALL=1"
    if not defined SHOULD_INSTALL echo 已取消更新。
    exit /b 0
)

if /I "!VERSION_COMPARE!"=="EQ" (
    set /p "REINSTALL_VERSION=当前已是目标版本，是否仍要重新安装? [Y/N]: "
    if /I "!REINSTALL_VERSION!"=="Y" set "SHOULD_INSTALL=1"
    if /I "!REINSTALL_VERSION!"=="YES" set "SHOULD_INSTALL=1"
    if defined SHOULD_INSTALL (
        set "OPERATION_NAME=重新安装"
    ) else (
        echo 当前已是目标版本，跳过安装。
        echo 如果数据库中的 vector 扩展版本仍较旧，请连接对应数据库执行:
        echo   "%PGROOT%\bin\psql.exe" -U postgres -d rag_notebook -c "ALTER EXTENSION vector UPDATE;"
    )
    exit /b 0
)

if /I "!VERSION_COMPARE!"=="GT" (
    set /p "DOWNGRADE_VERSION=已安装版本高于目标版本，是否仍要安装目标版本? [Y/N]: "
    if /I "!DOWNGRADE_VERSION!"=="Y" set "SHOULD_INSTALL=1"
    if /I "!DOWNGRADE_VERSION!"=="YES" set "SHOULD_INSTALL=1"
    if defined SHOULD_INSTALL (
        set "OPERATION_NAME=安装指定版本"
    ) else (
        echo 已跳过安装，保留当前较高版本。
    )
    exit /b 0
)

echo 警告: 无法比较已安装版本与目标版本，将按安装流程继续。
set /p "CONTINUE_INSTALL=是否继续安装? [Y/N]: "
if not defined CONTINUE_INSTALL set "CONTINUE_INSTALL=Y"
if /I "!CONTINUE_INSTALL!"=="Y" set "SHOULD_INSTALL=1"
if /I "!CONTINUE_INSTALL!"=="YES" set "SHOULD_INSTALL=1"
exit /b 0

:CompareVersions
set "VERSION_COMPARE=UNKNOWN"
set "VERSION_A=%~1"
set "VERSION_B=%~2"
for /f "usebackq delims=" %%C in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $a=[version]($env:VERSION_A.TrimStart('v')); $b=[version]($env:VERSION_B.TrimStart('v')); if ($a -lt $b) { 'LT' } elseif ($a -gt $b) { 'GT' } else { 'EQ' } } catch { 'UNKNOWN' }"`) do (
    set "VERSION_COMPARE=%%C"
)
set "VERSION_A="
set "VERSION_B="
exit /b 0

:EnsureNmakeAvailable
where nmake >nul 2>nul
if not errorlevel 1 (
    for /f "delims=" %%N in ('where nmake 2^>nul') do (
        echo 已找到 nmake:
        echo   %%N
        exit /b 0
    )
    exit /b 0
)

echo 当前 PATH 中未找到 nmake。
echo 正在尝试自动加载 Visual Studio C++ 构建环境...
call :LoadVsDevCmd
if errorlevel 1 exit /b 1

where nmake >nul 2>nul
if errorlevel 1 exit /b 1
for /f "delims=" %%N in ('where nmake 2^>nul') do (
    echo 加载 Visual Studio 环境后已找到 nmake:
    echo   %%N
    exit /b 0
)
exit /b 0

:LoadVsDevCmd
set "VS_INSTALL_DIR="
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"

if exist "%VSWHERE%" (
    for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do (
        set "VS_INSTALL_DIR=%%I"
    )
)

if not defined VS_INSTALL_DIR (
    for %%D in (
        "%ProgramFiles%\Microsoft Visual Studio\2022\Community"
        "%ProgramFiles%\Microsoft Visual Studio\2022\Professional"
        "%ProgramFiles%\Microsoft Visual Studio\2022\Enterprise"
        "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools"
        "%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools"
    ) do (
        if exist "%%~D\Common7\Tools\VsDevCmd.bat" (
            set "VS_INSTALL_DIR=%%~D"
            goto LoadVsDevCmdFound
        )
    )
)

:LoadVsDevCmdFound
if not defined VS_INSTALL_DIR (
    echo 未能自动检测到 Visual Studio C++ 工具。
    exit /b 1
)

if not exist "%VS_INSTALL_DIR%\Common7\Tools\VsDevCmd.bat" (
    echo 未找到 VsDevCmd.bat:
    echo   "%VS_INSTALL_DIR%\Common7\Tools\VsDevCmd.bat"
    exit /b 1
)

echo 正在加载:
echo   "%VS_INSTALL_DIR%\Common7\Tools\VsDevCmd.bat"
call "%VS_INSTALL_DIR%\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b 1
exit /b 0

:DetectPgRoot
set "DETECTED_PGROOT="
call :DetectFromTool pg_config
if defined DETECTED_PGROOT exit /b 0
call :DetectFromTool psql
if defined DETECTED_PGROOT exit /b 0
call :DetectFromRegistry
if defined DETECTED_PGROOT exit /b 0
call :DetectFromKnownPaths
exit /b 0

:DetectFromTool
set "TOOL_NAME=%~1"
for /f "delims=" %%P in ('where %TOOL_NAME% 2^>nul') do (
    for %%R in ("%%~dpP..") do set "CANDIDATE_PGROOT=%%~fR"
    call :ValidatePgRoot "!CANDIDATE_PGROOT!" >nul 2>nul
    if not errorlevel 1 (
        set "DETECTED_PGROOT=!CANDIDATE_PGROOT!"
        exit /b 0
    )
)
exit /b 0

:DetectFromRegistry
for %%K in ("HKLM\SOFTWARE\PostgreSQL\Installations" "HKLM\SOFTWARE\WOW6432Node\PostgreSQL\Installations") do (
    for /f "delims=" %%S in ('reg query %%~K 2^>nul') do (
        for /f "tokens=3,*" %%A in ('reg query "%%S" /v "Base Directory" 2^>nul ^| findstr /I "Base Directory"') do (
            if /I "%%A"=="REG_SZ" (
                set "CANDIDATE_PGROOT=%%B"
                call :ValidatePgRoot "!CANDIDATE_PGROOT!" >nul 2>nul
                if not errorlevel 1 (
                    set "DETECTED_PGROOT=!CANDIDATE_PGROOT!"
                    exit /b 0
                )
            )
        )
    )
)
exit /b 0

:DetectFromKnownPaths
for %%D in (
    "%ProgramFiles%\PostgreSQL\18"
    "%ProgramFiles%\PostgreSQL\17"
    "%ProgramFiles%\PostgreSQL\16"
    "%ProgramFiles%\PostgreSQL\15"
    "%ProgramFiles%\PostgreSQL\14"
    "%ProgramFiles%\PostgreSQL\13"
) do (
    call :ValidatePgRoot "%%~D" >nul 2>nul
    if not errorlevel 1 (
        set "DETECTED_PGROOT=%%~D"
        exit /b 0
    )
)
exit /b 0

:PromptPgRoot
echo.
echo 未能自动检测到 PostgreSQL 安装目录。
echo 请输入 PostgreSQL 根目录，例如:
echo   C:\Program Files\PostgreSQL\18
echo.

:PromptPgRootAgain
set "INPUT_PGROOT="
set /p "INPUT_PGROOT=PGROOT 路径: "
if not defined INPUT_PGROOT (
    echo 错误: PGROOT 路径不能为空。
    goto PromptPgRootAgain
)
for %%R in ("!INPUT_PGROOT!") do set "INPUT_PGROOT=%%~R"
call :ValidatePgRoot "!INPUT_PGROOT!"
if errorlevel 1 (
    echo 请重新输入有效的 PostgreSQL 根目录。
    goto PromptPgRootAgain
)
set "SELECTED_PGROOT=!INPUT_PGROOT!"
exit /b 0

:ConfirmOrEditPgRoot
set "PROPOSED_PGROOT=%~1"
set "CONFIRMED_PGROOT="

:ConfirmOrEditPgRootAgain
echo.
echo PostgreSQL 根目录候选路径:
echo   "!PROPOSED_PGROOT!"
echo.
echo 直接按 Enter 使用该路径并作为本次 PGROOT；如需更改，请直接输入新的 PostgreSQL 根目录。
echo.
set "PGROOT_CONFIRM_INPUT="
set /p "PGROOT_CONFIRM_INPUT=PGROOT 路径 [默认使用上方路径]: "
if not defined PGROOT_CONFIRM_INPUT (
    set "CONFIRMED_PGROOT=!PROPOSED_PGROOT!"
    exit /b 0
)
for %%R in ("!PGROOT_CONFIRM_INPUT!") do set "EDITED_PGROOT=%%~R"
call :ValidatePgRoot "!EDITED_PGROOT!"
if errorlevel 1 (
    echo 请输入有效的 PostgreSQL 根目录；留空则使用上方默认路径。
    goto ConfirmOrEditPgRootAgain
)
set "CONFIRMED_PGROOT=!EDITED_PGROOT!"
exit /b 0

:ValidatePgRoot
set "CHECK_PGROOT=%~1"
set "PG_VERSION_TEXT="
if not defined CHECK_PGROOT (
    echo 错误: PGROOT 为空。
    exit /b 1
)
if not exist "%CHECK_PGROOT%\" (
    echo 错误: PGROOT 目录不存在:
    echo   "%CHECK_PGROOT%"
    exit /b 1
)
if not exist "%CHECK_PGROOT%\bin\pg_config.exe" (
    echo 错误: 未找到 pg_config.exe:
    echo   "%CHECK_PGROOT%\bin\pg_config.exe"
    exit /b 1
)
if not exist "%CHECK_PGROOT%\bin\psql.exe" (
    echo 错误: 未找到 psql.exe:
    echo   "%CHECK_PGROOT%\bin\psql.exe"
    exit /b 1
)
if not exist "%CHECK_PGROOT%\include\server\postgres.h" (
    echo 错误: 未找到 PostgreSQL 服务端头文件:
    echo   "%CHECK_PGROOT%\include\server\postgres.h"
    echo 请安装包含服务端开发头文件的 PostgreSQL 发行包。
    exit /b 1
)
for /f "delims=" %%V in ('"%CHECK_PGROOT%\bin\pg_config.exe" --version 2^>nul') do set "PG_VERSION_TEXT=%%V"
if not defined PG_VERSION_TEXT (
    echo 错误: 无法运行 pg_config:
    echo   "%CHECK_PGROOT%\bin\pg_config.exe"
    exit /b 1
)
echo 已识别 %PG_VERSION_TEXT%
for /f "tokens=2" %%M in ("%PG_VERSION_TEXT%") do set "PG_MAJOR_TEXT=%%M"
for /f "tokens=1 delims=." %%M in ("!PG_MAJOR_TEXT!") do set "PG_MAJOR=%%M"
exit /b 0

:Usage
echo.
echo 用法:
echo   scripts\install_pgvector_windows.bat [--no-pause]
echo.
echo 可选环境变量:
echo   PGVECTOR_VERSION=v0.8.3  ^(指定版本；不设置时自动选择 GitHub 上最新稳定版本^)
echo.
echo 更新行为:
echo   - 已安装版本低于目标版本时会提示更新
echo   - 已安装版本等于目标版本时默认跳过，可选择重新安装
echo   - 更新扩展文件后，已启用 vector 的数据库还需执行 ALTER EXTENSION vector UPDATE
echo.
echo PGROOT 环境变量:
echo   - 确认 PGROOT 后，如用户/系统环境变量中没有 PGROOT，会自动写入当前用户环境变量
echo   - 如果已有 PGROOT 但路径不同，会询问是否更新用户环境变量
echo.
echo 环境要求:
echo   - 已安装 Windows 版 PostgreSQL
echo   - 已安装带 C++ 支持的 Visual Studio Build Tools
echo   - 建议从 "x64 Native Tools Command Prompt for VS" 运行
echo   - PATH 中可以找到 Git
echo.
set "SCRIPT_EXIT_CODE=0"
goto Finish

:Finish
if not defined SCRIPT_EXIT_CODE set "SCRIPT_EXIT_CODE=0"
echo.
if not defined NO_PAUSE (
    echo 按任意键关闭此窗口。
    pause >nul
)
exit /b %SCRIPT_EXIT_CODE%
