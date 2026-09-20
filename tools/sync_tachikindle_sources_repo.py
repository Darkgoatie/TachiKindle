import argparse
import json
import shutil
from pathlib import Path

REQUIRED = [
    "id", "name", "lang", "base_url", "version_code", "source_script", "endpoints", "selectors",
]


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def is_downloadable_script(name) -> bool:
    return isinstance(name, str) and name.endswith(".lua") and "/" not in name


def local_koplugin_script_path(root: str, lang: str, name: str) -> Path:
    # Canonical bundled module naming convention: sources/en/weebcentral.lua
    return Path(root) / "koplugin" / "tachikindle.koplugin" / "sources" / lang / f"{name}.lua"


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync TachiKindle extension descriptors into tachikindle-sources repo")
    parser.add_argument(
        "--source",
        default="C:/Users/halit/Desktop/Projects/TachiKindle/extensions/sources",
        help="Directory containing <lang>/*.tkext.json descriptors",
    )
    parser.add_argument(
        "--project-root",
        default="C:/Users/halit/Desktop/Projects/TachiKindle",
        help="TachiKindle project root, used to locate bundled Lua scripts for downloadable source_script values",
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
    parser.add_argument(
        "--only",
        action="append",
        default=None,
        help="Extension id to include (repeatable). Omit to sync all descriptors found under --source.",
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
    copied_scripts = []
    for src in source_files:
        obj = load_json(src)
        if args.only and obj.get("id") not in args.only:
            continue
        missing = [k for k in REQUIRED if k not in obj]
        if missing:
            raise SystemExit(f"{src} missing required keys: {', '.join(missing)}")

        rel = src.relative_to(source_root).as_posix()
        dest = target_root / "sources" / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        copied.append(dest)

        script_name = obj.get("source_script")
        if is_downloadable_script(script_name):
            lang = rel.split("/")[0]
            base_name = script_name[:-4]  # strip .lua
            candidates = [
                local_koplugin_script_path(args.project_root, lang, base_name),
                local_koplugin_script_path(args.project_root, lang, base_name.lower()),
            ]
            script_src = next((c for c in candidates if c.is_file()), None)
            if not script_src:
                raise SystemExit(f"Downloadable script source not found for {obj['id']}: tried {candidates}")
            script_dest = dest.parent / script_name
            shutil.copy2(script_src, script_dest)
            copied_scripts.append(script_dest)

        entries.append({
            "id": obj["id"],
            "name": obj.get("name", obj["id"]),
            "lang": obj.get("lang", "?"),
            "version_code": int(obj.get("version_code", 1)),
            "content_warning": obj.get("content_warning", "SAFE"),
            "path": f"sources/{rel}",
        })

    if not entries:
        raise SystemExit("No descriptors matched --only filter; refusing to publish an empty index")

    # Remove stale descriptors and scripts no longer present in source.
    expected = {p.resolve() for p in copied}
    expected_scripts = {p.resolve() for p in copied_scripts}
    target_sources = target_root / "sources"
    for existing in target_sources.glob("*/*.tkext.json"):
        if existing.resolve() not in expected:
            existing.unlink()
    for existing in target_sources.glob("*/*.lua"):
        if existing.resolve() not in expected_scripts:
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

    print(f"Synced {len(entries)} extensions ({len(copied_scripts)} downloadable scripts) into {target_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
