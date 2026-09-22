# TachiKindle

A Tachiyomi-style manga/comic reader plugin for KOReader, built for
jailbroken Kindles (and any other device KOReader runs on). Runs as a
real KOReader plugin (`.koplugin`) -- no separate binary, no KUAL, no
Java. Reads offline `.cbz`/image-folder libraries and downloads
chapters directly from real online manga/comic sites, all from
on-device menus.

- [Features](#features)
- [Supported devices](#supported-devices)
- [Installation](#installation)
- [Usage guide](#usage-guide)
  - [Main menu](#main-menu)
  - [Extensions Manager: installing sources](#extensions-manager-installing-sources)
  - [Browsing and reading](#browsing-and-reading)
  - [Favorites](#favorites)
  - [Downloading chapters for offline reading](#downloading-chapters-for-offline-reading)
  - [Offline Library](#offline-library)
  - [Continue Reading and Reading Analytics](#continue-reading-and-reading-analytics)
  - [Self-update](#self-update)
- [Online sources](#online-sources)
- [Troubleshooting](#troubleshooting)
- [Developing / contributing](#developing--contributing)
- [Architecture](#architecture)
- [Known issues / not yet built](#known-issues--not-yet-built)
- [License](#license)

## Features

- **Offline library**: browse and read `.cbz` files or folders of
  loose images, same as any book in KOReader.
- **Online sources**: an in-app Extensions Manager downloads source
  definitions from a public catalog and lets you browse, search, and
  read (or download) chapters from real manga/comic sites.
- **Favorites**: star any manga from any source; comes back in one
  tap from the Favorites screen even if you don't remember the title.
- **Offline downloads**: queue chapters for full offline caching, so
  you can read without a live connection later.
- **Continue Reading**: every chapter you open is tracked with your
  exact page position, resumable from the main menu.
- **Reading Analytics**: a simple read/unread overview across your
  sources.
- **Self-update**: check for and apply plugin code updates directly
  from GitHub, on-device, no USB/computer required.

## Supported devices

Runs on any device KOReader itself supports. Verified on:

- Kindle Paperwhite (11th gen), jailbroken via SpringBreak (KindleModding
  `hdnext` stack), KOReader running as the primary reader app.

Any jailbroken Kindle capable of running KOReader should work the same
way; other KOReader-supported e-readers (Kobo, generic Linux, Android,
desktop, etc.) should also work in principle but have not been tested
by this project.

## Installation

1. Jailbreak your device and install KOReader if you haven't already
   -- see [kindlemodding.org](https://kindlemodding.org) for
   jailbreak + KOReader install steps for your specific
   device/firmware.
2. Get the plugin files, either:
   - Download the latest source zip from the
     [Releases page](https://github.com/Darkgoatie/TachiKindle/releases)
     and extract it, or
   - `git clone https://github.com/Darkgoatie/TachiKindle`
3. Copy the `koplugin/tachikindle.koplugin/` folder onto your device's
   KOReader plugins directory. On a jailbroken Kindle this is
   typically:
   ```
   /mnt/us/koreader/plugins/tachikindle.koplugin/
   ```
   (Copy the whole folder over USB mass storage, or `scp` it if you
   have KOReader's SSH server enabled -- see
   [Developing / contributing](#developing--contributing) below.)
4. Restart KOReader (or the whole device). Open KOReader's main menu
   -- "TachiKindle" appears as its own top-level entry (grouped under
   "More tools" if your KOReader menu layout collapses extras there).
5. From the TachiKindle menu, tap **Extensions Manager** to download
   your first online source, or point KOReader's regular file browser
   at a folder of `.cbz`/image-folder comics for fully offline
   reading (TachiKindle's own Offline Library screen also indexes
   chapters you've downloaded through it -- see below).

## Usage guide

### Main menu

Opening TachiKindle (from KOReader's main menu, or via the
`TachiKindleOpen` action if you've bound it to a gesture/button) shows
seven entries:

| Menu item | What it does |
|---|---|
| **Browse Sources** | Lists every source you've installed. Tap one to browse/search its manga list. |
| **Continue Reading** | Every chapter you've opened, with your last page position, newest first. Tap to resume exactly where you left off. |
| **Reading Analytics** | A read/unread overview across your sources. |
| **Favorites** | Every manga you've starred, across all sources, with the source name shown next to each entry. |
| **Offline Library** | Chapters you've explicitly downloaded for offline reading, organized by series. |
| **Extensions Manager** | Add/remove source catalogs (repos) and install/update/remove individual sources. |
| **Check for updates** | Checks for a newer build of the plugin itself and offers to install it. |

### Extensions Manager: installing sources

1. Tap **Extensions Manager**. By default it already points at the
   public [tachikindle-sources](https://github.com/Darkgoatie/tachikindle-sources)
   catalog -- tap that row to see the list of available sources.
2. Each row shows the source's name, language, content rating (e.g.
   `SAFE`/`MIXED`), and version. A prefix shows install state: `✓`
   already installed and current, `↑` an update is available, nothing
   if not installed yet.
3. Tap a source row to open its action dialog: **Download** (first
   install), **Update** (a newer version is available), or
   **Reinstall** (already installed and current, re-fetch anyway), plus
   **Remove** if it's installed, and **Cancel**.
4. Once downloaded, the source appears under **Browse Sources** in the
   main menu immediately -- no restart needed.

Tap the hamburger icon (top-left) inside the Extensions Manager for
repo-level actions:

- **Add repo** -- add a different/custom catalog by its raw base URL
  (e.g. `https://raw.githubusercontent.com/user/repo/main`), if you
  want to point at a fork or your own private catalog.
- **Installed extensions** -- see everything currently installed
  across all repos, with tap-to-remove.
- **Remove selected repo** -- select a repo row first (tap once to
  highlight, without opening it), then use this to remove that catalog
  from your repo list. This only removes the *catalog*, not sources
  you've already downloaded from it.

### Browsing and reading

1. **Browse Sources** > tap a source > you land on its manga list
   (popular/latest, depending on the source). Use the source's search
   if it supports one.
2. Tap a manga to see its chapter list.
3. Tap a chapter to read it immediately online -- pages load lazily as
   you swipe, nothing is written to disk in this mode. Swipe
   left/right (or tap the very edges) to turn pages; tap the top strip
   to toggle the title bar; tap the top-left corner to exit back to
   the chapter list.
4. Your page position is saved automatically as you read and appears
   in **Continue Reading** afterward.

### Favorites

Hold (long-press) any manga row -- in a source's manga list, in
Favorites itself, or in search results -- to toggle it as a favorite.
A star (`★`) prefix marks favorited titles everywhere they appear.
Favorites persist even if the manga's source is later removed (it's
shown greyed with a "source missing" state until reinstalled).

Note: holding a *source* row (not a manga) in Browse Sources instead
opens a "Remove extension" confirmation -- that's how you uninstall a
source without going through the Extensions Manager.

### Downloading chapters for offline reading

Hold (long-press) a chapter row (in a manga's chapter list, or in the
Offline Library) to open its action dialog:

- **Download offline** -- fetches and caches every page of that
  chapter to local storage so it can be read with no network at all
  afterward.
- **Redownload** -- re-fetches and overwrites an already-downloaded
  chapter's cache (useful if a previous download was incomplete/corrupt).
- **Verify cache** -- re-checks how many of a chapter's pages are
  actually saved on disk (useful if a download was interrupted).
- **Delete cache** -- frees the space back up.
- **Add to download queue** -- queues it instead of downloading
  immediately (useful for grabbing several chapters back-to-back);
  check progress via **Offline Library > Download Queue**.
- **Mark as read / Mark as unread** -- toggles read status without
  downloading.
- **Mark read until here / Mark unread until here** -- applies to
  every chapter from that one through the end of the list, for
  quickly catching up on (or resetting) a whole series at once.

### Offline Library

Lists every series with at least one chapter downloaded, grouped by
series name. Drill into a series to see its downloaded chapters, with
the same long-press actions as above (verify/delete cache, mark
read/unread). A **Download Queue** entry at the top shows anything
still pending.

### Continue Reading and Reading Analytics

**Continue Reading** lists every chapter you've opened, most-recent
first, with your saved page position (`current/total`) -- tap to jump
straight back in. **Reading Analytics** gives a simple read/unread
tally across everything you've read through TachiKindle.

### Self-update

**Check for updates** compares your installed plugin build against the
latest commit on this repo's active development branch (not a fixed
release version -- every push is treated as a new build). If a newer
build exists, you'll see a confirmation dialog with both the installed
and available build identifiers; tapping **Update now** downloads and
applies it in place. **KOReader must be restarted afterward** to load
the new code (plugins can't hot-reload). Your settings, favorites,
reading progress, and downloaded/installed sources are never touched
by this -- it only replaces the plugin's own code files.

This is completely separate from the Extensions Manager above, which
manages *source* downloads from a different catalog repo -- updating
the plugin itself does not add or update sources, and vice versa.

## Online sources

Source definitions are downloaded on-device from the companion
[tachikindle-sources](https://github.com/Darkgoatie/tachikindle-sources)
catalog repo via the Extensions Manager -- they are not bundled with
the plugin itself (except a few reference sources kept in-repo under
`extensions/sources/en/` for development/testing purposes).

Current catalog, with real status (verified against live sites/APIs,
not assumed):

| Source | Status |
|---|---|
| MangaDex | Working |
| Comick | Working |
| Asura Scans | Working |
| MangaBuddy | Working |
| MangaKatana | Working |
| WeebCentral | Working |
| BatCave | Blocked by Cloudflare's JS challenge (no bypass; KOReader has no JS engine) |
| Toonily | Blocked by Cloudflare's JS challenge (same limitation as BatCave) |

Each source's `.tkext.json` descriptor documents its own verification
status, known limitations, and the exact live checks it was built
against -- see `extensions/format/README.md` for the format and
`extensions/format/repo-protocol.md` for how the catalog/download
protocol works.

Some titles on otherwise-working sources may have most or all
chapters licensed to a different platform (Webtoon, MangaPlus, KManga,
etc.) and will correctly show "no chapters" through that source --
that's expected behavior, not a bug.

## Troubleshooting

- **A source shows no chapters for a title I know has chapters** --
  check if that title's chapters are hosted externally (see note
  above), or hold the source row in Browse Sources and re-download it
  in case its descriptor is stale.
- **A source's manga list/chapters/pages fail to load entirely** --
  the site may be Cloudflare-blocked (see the status table above) or
  temporarily down; it isn't necessarily a plugin bug.
- **"Check for updates" says up to date but you know new code shipped**
  -- make sure your installed plugin already has a `BUILD` file
  (present after any successful self-update, or after a fresh install
  from a release built after this feature shipped); a very old install
  predating this file will always report "unknown" and offer to
  update on first check, which is expected.
- **A downloaded source doesn't appear in Browse Sources after
  installing** -- restart KOReader once; some installs only refresh
  the in-memory source list on next launch.

## Developing / contributing

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

### Adding a new source

See `extensions/format/README.md` for the `.tkext.json` schema and
`extensions/format/source-script-format.md` for how a `source_script`
works. In short: most sites need only a descriptor with CSS selectors
(no Lua at all, using the generic engine in `tachikindlesource.lua`);
sites with a JSON API or non-selectable embedded data (see MangaDex,
Comick, Asura Scans, MangaBuddy, MangaKatana for real examples) need a
small `source_script` implementing 4 functions:
`fetch_manga_list`/`fetch_manga_details`/`fetch_chapter_list`/`fetch_page_list`.
Every source shipped in this repo documents, in its own descriptor's
`verification`/`_todo`/`limitations` fields, exactly what was checked
live and what wasn't -- follow that same discipline for new ones
rather than guessing at a site's shape.

## Architecture

- `koplugin/tachikindle.koplugin/main.lua` -- plugin entry point, menu
  wiring
- `tachikindlesource.lua` -- generic source engine: HTTP fetch, CSS
  selector extraction (via KOReader's bundled `htmlparser`), pagination,
  the `.tkext.json` schema loader
- `tachikindlebrowser.lua` -- Extensions Manager UI: repo/catalog
  browsing, download/update/remove of installed sources
- `tachikindlesourcebrowser.lua` -- per-source browse/search/chapter UI,
  favorites, offline library, download queue, continue reading,
  reading analytics
- `tachikindlereader.lua` -- online chapter/page reading UI (lazy
  page loading, no disk writes)
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

- BatCave and Toonily are Cloudflare-blocked (see the source status
  table above) -- fixture-tested but non-functional live until a
  JS-challenge-solving mechanism exists (none is currently planned;
  KOReader has no WebView/JS engine to lean on).
- No CBR/RAR support for offline libraries -- CBZ and loose image
  folders only.

## License

Apache License 2.0 -- see [LICENSE](LICENSE). Several sources in this
repo are ported from [keiyoushi/extensions-source](https://github.com/keiyoushi/extensions-source)
(also Apache-2.0); each ported source's `.tkext.json` documents its
specific upstream origin and attribution.
