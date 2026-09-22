# TachiKindle

A Tachiyomi-style manga/comic reader plugin for KOReader, built for
jailbroken Kindles. Runs as a real KOReader plugin (`.koplugin`) --
no separate binary, no KUAL, no Java. Reads offline CBZ libraries and
downloads chapters directly from online manga sources.

## Features

- Offline library: browse/read `.cbz` files or folders of loose images
  under your KOReader library folders, same as any other book.
- Online sources: an in-app Extensions Manager downloads source
  definitions from a public catalog and lets you browse, search, and
  download chapters from real manga/comic sites straight to your
  device.
- Self-update: check for and apply plugin updates from GitHub directly
  on-device, no USB/computer required.
- Reading progress, favorites, and per-series metadata persist across
  sessions.

## Supported devices

Runs on any device KOReader itself supports. Verified on:

- Kindle Paperwhite (11th gen), jailbroken via SpringBreak (KindleModding
  `hdnext` stack), KOReader running as the primary reader app.

Any jailbroken Kindle capable of running KOReader should work the same
way; other KOReader-supported e-readers (Kobo, generic Linux, etc.)
should also work in principle but have not been tested by this project.

## Installing on your Kindle

1. Jailbreak your device and install KOReader (see
   [kindlemodding.org](https://kindlemodding.org) for jailbreak +
   KOReader installation steps for your device/firmware).
2. Copy `koplugin/tachikindle.koplugin/` to KOReader's `plugins/`
   directory on the device (typically
   `/mnt/us/koreader/plugins/tachikindle.koplugin/` on Kindle).
3. Restart KOReader (or the device). TachiKindle appears in KOReader's
   plugin/tools menu.
4. Open the Extensions Manager from TachiKindle's menu to browse and
   download online manga sources, or point KOReader at a folder of
   `.cbz`/image-folder comics for fully offline reading.

## Online sources

Source definitions are downloaded on-device from the companion
[tachikindle-sources](https://github.com/Darkgoatie/tachikindle-sources)
catalog repo via the in-app Extensions Manager -- they are not bundled
with the plugin itself (except a few reference sources kept in-repo
under `extensions/sources/en/` for development/testing).

Current catalog, with real status (verified live, not assumed):

| Source | Status |
|---|---|
| MangaDex | Working |
| Comick | Working |
| Asura Scans | Working |
| MangaBuddy | Working |
| MangaKatana | Working |
| BatCave | Blocked by Cloudflare's JS challenge (no bypass; KOReader has no JS engine) |
| Toonily | Blocked by Cloudflare's JS challenge (same limitation as BatCave) |

Each source's `.tkext.json` descriptor documents its own verification
status, known limitations, and the exact live checks it was built
against -- see `extensions/format/README.md` for the format and
`extensions/format/repo-protocol.md` for how the catalog/download
protocol works.

## Self-update

TachiKindle's own plugin code can update itself: "Check for updates"
in the plugin menu compares the installed build against the latest
commit on this repo's active development branch and, if newer,
downloads and applies it in place (KOReader restart required
afterward). This is independent from the Extensions Manager, which
manages *source* downloads from the separate catalog repo above.

## Building/developing

This is a plain KOReader plugin -- no cross-compilation or native
toolchain is needed to develop it. `koplugin/tachikindle.koplugin/`
can be copied straight onto any device running KOReader, or symlinked
into a desktop KOReader checkout for faster iteration.

### Tests

A real Lua test suite (no live network required) covers every source
adapter's parsing logic against fixtures derived from real, live-
verified site/API responses:

```
bash tests/run_extension_tests.sh
```

Requires a Lua 5.1-compatible interpreter (`lua5.1`, `lua`, or
`luajit`) plus KOReader's real bundled `htmlparser`/`json` modules on
`LUA_PATH` (see the script for `TK_LUA_DEPS_DIR`).

### Device access (for development)

SSH is via KOReader's built-in SSH server (Tools > Network > SSH
server), port 2222, key-based auth only. The Kindle's IP is
DHCP-leased -- check the device's network settings each session.

```
ssh-keygen -t ed25519 -f ~/.ssh/kindle_ed25519 -N ""
# copy the .pub key into the device's KOReader SSH authorized_keys,
# then toggle KOReader's SSH server off/on to reload it

ssh -i ~/.ssh/kindle_ed25519 -p 2222 root@<current-ip>
```

## Architecture

- `koplugin/tachikindle.koplugin/main.lua` -- plugin entry point, menu
  wiring
- `tachikindlesource.lua` -- generic source engine: HTTP fetch, CSS
  selector extraction (via KOReader's bundled `htmlparser`), pagination,
  the `.tkext.json` schema loader
- `tachikindlebrowser.lua` -- Extensions Manager UI: repo/catalog
  browsing, download/update/remove of installed sources
- `tachikindlesourcebrowser.lua` -- per-source browse/search/chapter UI
- `tachikindlereader.lua` -- chapter/page reading UI
- `tachikindlefavorites.lua` / `tachikindleprogress.lua` -- persisted
  favorites and reading position
- `tachikindleupdater.lua` -- self-update mechanism (see above)
- `sources/en/*.lua` -- per-source `source_script` implementations;
  most are thin passthroughs to the generic selector engine, some
  (MangaDex, Comick, Asura Scans, MangaBuddy, MangaKatana) implement
  custom logic where the target site needs more than CSS selectors
  (JSON APIs, embedded JS data blobs, etc.) -- see each source's
  `.tkext.json` for what and why.
- `extensions/format/` -- the `.tkext.json` schema, the catalog/
  repo-protocol docs, and the `source_script` authoring guide

## Known issues / not yet built

- BatCave and Toonily are Cloudflare-blocked (see table above) --
  fixture-tested but non-functional live until a JS-challenge-solving
  mechanism exists (none is currently planned; KOReader has no
  WebView/JS engine to lean on).
- Some titles on working sources may have most/all chapters hosted
  externally (e.g. licensed to Webtoon/MangaPlus/KManga) and will
  correctly show as "no chapters" via that source -- this is expected,
  not a bug.
- No CBR/RAR support for offline libraries -- CBZ and loose image
  folders only.
