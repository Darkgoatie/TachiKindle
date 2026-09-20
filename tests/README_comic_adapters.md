# Comic source ports

Four Keiyoushi sources have been adapted for the KOReader plugin:

| Source | ID | Adapter |
| --- | --- | --- |
| ReadComicOnline | `en.readcomiconline` | HTML metadata and a static Lua reader decoder |
| ReadAllComics | `en.readallcomics` | HTML metadata and image selectors |
| XOXO Comics | `en.xoxocomics` | HTML metadata, paginated chapters and lazy image URLs |
| BatCave | `en.batcave` | HTML metadata, chapter JSON and reader API POST |

Definitions live in `extensions/sources/en/` and are mirrored into
`extensions/testrepo/sources/en/`, whose `index.json` lists all four.
The matching bundled Lua modules live in
`koplugin/tachikindle.koplugin/adapters/`. Install the updated plugin together
with these definitions: an older plugin does not understand the `adapter`
field. No executable module is downloaded from an extension repository.

This is a local conversion, not a claim that the hosted repository has been
updated or the Kindle has been deployed. No comic images are included.

## Tests

Synthetic HTML/JSON and URL fixtures exercise the actual parsers; only the
network boundary is replaced. Runtime integration tests additionally isolate
KOReader-only modules. They cover allowlisted loading, method dispatch, POST
request construction, page caching and offline fallback. A separate integration
suite loads each actual descriptor together with its bundled adapter and checks
reader URL construction, API dispatch and offline reuse. BatCave's API request
is asserted against synthetic JSON rather than sent to the reader endpoint.

Run from the repository root on Lua 5.1 with `htmlparser`, `socket.url`, `json`
and test-only `mime` available:

```sh
lua5.1 tests/test_source_adapters.lua
lua5.1 tests/test_comic_source_loading.lua
lua5.1 tests/test_readallcomics.lua
lua5.1 tests/test_xoxocomics.lua
lua5.1 tests/test_readcomiconline_adapter.lua
lua5.1 tests/test_batcave_adapter.lua
luac5.1 -p koplugin/tachikindle.koplugin/tachikindlesource.lua koplugin/tachikindle.koplugin/adapters/*.lua
```

The local WSL test dependency directory is
`/mnt/c/Users/halit/AppData/Local/Temp/tk-comic-lua`; use
`LUA_PATH='/mnt/c/Users/halit/AppData/Local/Temp/tk-comic-lua/?.lua;;'`.
This is an environment-specific test path, not a runtime dependency.

Dependency provenance (already provided by KOReader on-device):

- `msva/lua-htmlparser` commit `5ce9a775a345cf458c0388d7288e246bb1b82bff`,
  pinned by koreader-base's `thirdparty/lua-htmlparser/CMakeLists.txt`.
- LuaSocket `socket.url` and test-only `mime`.
- Standalone tests use `rxi/json.lua`; the device uses KOReader's `json`.

All six test suites and Lua syntax checks pass locally. All four definitions
validate against `extensions/format/schema-1.0.json`. This is not an on-device
or live-reader test.

## Live verification

`python tests/probe_comic_adapters_metadata.py build/comic-adapter-live`
requests listing metadata only and records timestamps/status/errors in
`results.json`. It never requests reader pages or images, executes site JS,
or solves browser challenges. Response HTML is not committed as a fixture.

Observed 2026-09-20 from this development machine:

- ReadComicOnline and upstream mirror `rcostation.xyz`: DNS lookup failure.
- ReadAllComics: HTTP 522 in the first probe; timeout in the later probe.
- XOXO Comics: HTTP 403, "Just a moment" challenge.
- BatCave: HTTP 403, "Just a moment" challenge.

Consequently, none of the four is verified for live reading here.

## Limitations

Advanced filters, related-comic UI, browser guard solving and cookie sharing
are not implemented. See each definition's `limitations` field. XOXO's
upstream image-only 404-as-success behavior is not implemented. ReadAllComics
has no latest endpoint, matching its upstream source.

BatCave uses the runtime's `adapter.fetchPages(source, chapter_url)` hook to
POST string `news_id` and `chapter_id` values and parse `data.images`.
ReadComicOnline uses `parsePages` on its configured reader URL. Its decoder
is a fixed Lua translation of an inspected upstream snapshot, not arbitrary
JavaScript evaluation; future upstream obfuscation changes require an update.
The snapshot SHA-256 is recorded in the Lua header.

Null JSON selectors in adapter-based definitions are intentional: embedded
JSON and encoded reader arrays cannot be represented by CSS selectors.

The adapters retain upstream Apache-2.0 attribution and modification notices.
`koplugin/tachikindle.koplugin/adapters/LICENSE` contains the license for all
four; source-specific license copies are retained where supplied.
