import importlib.util
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[2] / "scripts" / "seed_demo_data.py"
SPEC = importlib.util.spec_from_file_location("seed_demo_data", SCRIPT_PATH)
seed_demo_data = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(seed_demo_data)

FIXTURE_DIR = seed_demo_data.FIXTURE_DIR
load_manifest = seed_demo_data.load_manifest
validate_manifest = seed_demo_data.validate_manifest


def test_demo_manifest_is_valid():
    manifest = load_manifest()

    errors = validate_manifest(manifest)

    assert errors == []


def test_demo_dataset_covers_primary_surfaces():
    manifest = load_manifest()

    assert manifest["user"]["username"] == "demo_user"
    assert len(manifest["notes"]) >= 8
    assert len(manifest["knowledge_files"]) >= 2
    assert len(manifest["chat_sessions"]) == 2
    assert {item["status"] for item in manifest["quick_test_sessions"]} == {"active", "completed"}
    assert len(manifest["mind_maps"]) >= 1


def test_demo_knowledge_fixture_files_exist():
    manifest = load_manifest()

    for item in manifest["knowledge_files"]:
        path = FIXTURE_DIR / "knowledge" / item["filename"]
        assert path.is_file()
        assert path.read_text(encoding="utf-8").strip()
