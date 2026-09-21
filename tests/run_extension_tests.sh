#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

LUA_BIN="${LUA_BIN:-}"
if [[ -z "$LUA_BIN" ]]; then
  for candidate in lua5.1 lua luajit; do
    if command -v "$candidate" >/dev/null 2>&1; then
      LUA_BIN="$candidate"
      break
    fi
  done
fi

if [[ -z "$LUA_BIN" ]]; then
  echo "No Lua runtime found. Install lua5.1 (or set LUA_BIN=/path/to/lua)." >&2
  exit 127
fi

tests=(
  "tests/test_source_adapters.lua"
  "tests/test_comic_source_loading.lua"
  "tests/test_selector_extensions_smoke.lua"
  "tests/test_weebcentral_chapter_fallback.lua"
  "tests/test_readallcomics.lua"
  "tests/test_readcomiconline_adapter.lua"
  "tests/test_xoxocomics.lua"
  "tests/test_batcave_adapter.lua"
)

pass=0
fail=0
failed_tests=()

echo "Using Lua runtime: $LUA_BIN"

for t in "${tests[@]}"; do
  echo
  echo "==> $t"
  if "$LUA_BIN" "$t"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed_tests+=("$t")
  fi
done

echo
echo "Extension test summary: pass=$pass fail=$fail total=${#tests[@]}"

if (( fail > 0 )); then
  echo "Failed tests:"
  for t in "${failed_tests[@]}"; do
    echo "  - $t"
  done
  exit 1
fi

echo "All extension tests passed."
