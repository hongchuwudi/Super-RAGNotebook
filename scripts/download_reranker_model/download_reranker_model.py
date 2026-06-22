from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


MODEL_ID = "BAAI/bge-reranker-v2-m3"
DEFAULT_TARGET = r"models\bge-reranker-v2-m3"


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def resolve_target(target: str) -> Path:
    target_path = Path(target)
    if target_path.is_absolute():
        return target_path
    return project_root() / target_path


def find_actual_model_path(target: Path) -> Path | None:
    configs = list(target.rglob("config.json"))
    if not configs:
        return None

    for config in configs:
        model_dir = config.parent
        if (model_dir / "model.safetensors").exists():
            return model_dir
    return configs[0].parent


def print_usage() -> None:
    print()
    print("用法:")
    print("  scripts\\download_reranker_model.bat [--no-pause] [目标目录]")
    print()
    print("默认下载目录:")
    print(f"  {DEFAULT_TARGET}")
    print()
    print("示例:")
    print("  scripts\\download_reranker_model.bat")
    print("  scripts\\download_reranker_model.bat --no-pause")
    print(f"  scripts\\download_reranker_model.bat --no-pause {DEFAULT_TARGET}")


def parse_target(argv: list[str]) -> tuple[str | None, int | None]:
    args = [arg for arg in argv if arg != "--no-pause"]
    if any(arg in {"/?", "-h", "--help"} for arg in args):
        print_usage()
        return None, 0

    if len(args) > 1:
        print("错误: 只能指定一个目标目录。")
        print_usage()
        return None, 2

    return (args[0] if args else DEFAULT_TARGET), None


def main() -> int:
    target_arg, exit_code = parse_target(sys.argv[1:])
    if exit_code is not None:
        return exit_code

    target = resolve_target(target_arg)

    print()
    print("RAGNotebook 重排序模型下载脚本")
    print("--------------------------------")
    print(f"模型:   {MODEL_ID}")
    print(f"目录:   {target_arg}")
    print(f"Python: {sys.executable}")
    print()

    if importlib.util.find_spec("modelscope") is None:
        print('错误: 当前 Python 环境未安装 "modelscope"。')
        print('请先运行 "python start.py --install"，或安装后端依赖。')
        return 1

    from modelscope import snapshot_download

    target.mkdir(parents=True, exist_ok=True)
    print(f"下载目录: {target}")

    snapshot_path = snapshot_download(
        model_id=MODEL_ID,
        cache_dir=str(target),
        revision="master",
    )
    print(f"ModelScope 缓存目录: {snapshot_path}")

    actual_model_path = find_actual_model_path(target)
    if actual_model_path is None:
        print()
        print("错误: 下载失败，或未找到 config.json。")
        return 2

    print(f"实际模型目录: {actual_model_path}")
    print()
    print("完成。请确认 .env 中配置:")
    print(f"RERANKER_MODEL_PATH={target_arg}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
