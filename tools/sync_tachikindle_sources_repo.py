import argparse
import json
import shutil
from pathlib import Path

REQUIRED = [
    "id", "name", "lang", "base_url", "version_code", "source_script", "endpoints", "selectors",
]


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync TachiKindle extension descriptors into tachikindle-sources repo")
    parser.add_argument(
        "--source",
        default="C:/Users/halit/Desktop/Projects/TachiKindle/extensions/sources",
        help="Directory containing <lang>/*.tkext.json descriptors",
    )
    parser.add_argument(
        "--target",
        default="C:/Users/halit/Desktop/Projects/tachikindle-sources",
        help="Local checkout of tachikindle-sources repo",
    )
    parser.add_argument(
        "--repo-name",
        default="TachiKindle Sources",
        help="repo_name value written into index.json",
    )
    args = parser.parse_args()

    source_root = Path(args.source)
    target_root = Path(args.target)
    if not source_root.is_dir():
        raise SystemExit(f"Source dir not found: {source_root}")
    if not (target_root / ".git").is_dir():
        raise SystemExit(f"Target repo missing .git: {target_root}")

    source_files = sorted(source_root.glob("*/*.tkext.json"))
    if not source_files:
        raise SystemExit(f"No descriptor files found under: {source_root}")

    entries = []
    copied = []
    for src in source_files:
        obj = load_json(src)
        missing = [k for k in REQUIRED if k not in obj]
        if missing:
            raise SystemExit(f"{src} missing required keys: {', '.join(missing)}")

        rel = src.relative_to(source_root).as_posix()
        dest = target_root / "sources" / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        copied.append(dest)

        entries.append({
            "id": obj["id"],
            "name": obj.get("name", obj["id"]),
            "lang": obj.get("lang", "?"),
            "version_code": int(obj.get("version_code", 1)),
            "content_warning": obj.get("content_warning", "SAFE"),
            "path": f"sources/{rel}",
        })

    # Remove stale descriptors no longer present in source.
    expected = {p.resolve() for p in copied}
    target_sources = target_root / "sources"
    for existing in target_sources.glob("*/*.tkext.json"):
        if existing.resolve() not in expected:
            existing.unlink()

    entries.sort(key=lambda e: (e["lang"], e["name"].lower(), e["id"]))
    index = {
        "repo_name": args.repo_name,
        "repo_format_version": 1,
        "extensions": entries,
    }
    (target_root / "index.json").write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    schema_src = Path("C:/Users/halit/Desktop/Projects/TachiKindle/extensions/format/schema-1.0.json")
    shutil.copy2(schema_src, target_root / "schema-1.0.json")

    print(f"Synced {len(entries)} extensions into {target_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
