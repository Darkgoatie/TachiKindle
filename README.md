# TachiKindle

A Tachiyomi-style manga/comic reader for jailbroken Kindles. Runs as a
native ARM binary launched by a Scriptlet — no KUAL, no Java.

## Supported devices

Built and verified against:

- Kindle Paperwhite (11th gen), board `malbec_bellatrix`
- Firmware 5.19.2 (kernel 4.9.77-lab126, armv7l, `kindlehf` ABI)
- Jailbroken via SpringBreak v1.3.7 (KindleModding `hdnext` stack)
- Screen: 1236x1648 @ 298.99dpi, 8bpp grayscale

Other `kindlehf`-class devices (FW >= 5.16.3, hard-float) should work
with the same build but have not been tested. Older devices need the
`kindlepw2` or `kindle5` toolchain instead — see the plan document for
the toolchain-selection table.

## Installing on your Kindle

1. Jailbreak your device (SpringBreak or another `hdnext`-stack jailbreak
   from [kindlemodding.org](https://kindlemodding.org)).
2. Download the latest release zip (or build it yourself, see below).
3. Connect the Kindle via USB.
4. Copy `tachikindle/` to the Kindle's root as `/mnt/us/tachikindle/`.
5. Copy `TachiKindle.sh` to `/mnt/us/documents/TachiKindle.sh`.
6. Eject, wait for the library to refresh, tap "TachiKindle" (it appears
   as a book, since that's how Scriptlets work on this jailbreak stack).
7. Put your comics under `/mnt/us/tachikindle/library/<Series Name>/`,
   either as `.cbz` files (one per chapter) or subfolders of loose
   images. Relaunch the app or use "Rescan Library" (once wired up --
   see Known Issues) to pick up new content.

If the app ever hangs or the screen goes black: the launcher script
restores the Kindle UI even if killed or if the binary crashes (verified,
see Phase 4/6 below) — but if something goes wrong anyway, SSH in (see
Device access) and run `start lab126_gui`.

## Building from source

Cross-compiling happens in **WSL2** (Ubuntu), not native Windows —
koxtoolchain doesn't build on Windows and KindleModding's prebuilt
release targets Linux.

```
wsl -d Ubuntu
export PATH="$HOME/x-tools/arm-kindlehf-linux-gnueabihf/bin:$PATH"
cd /mnt/c/Users/halit/Desktop/Projects/TachiKindle
make            # builds ./tachikindle
make package     # stages build/pkg/ ready to copy to the device
make test        # host-side unit + integration tests, plain gcc, no device needed
```

### One-time toolchain setup

```bash
# 1. Cross-compiler (prebuilt release)
cd ~
wget https://github.com/KindleModding/koxtoolchain/releases/latest/download/kindlehf.tar.gz
tar xf kindlehf.tar.gz    # -> ~/x-tools/arm-kindlehf-linux-gnueabihf

# 2. FBInk (vendored as a git submodule, build once)
cd third_party/FBInk && git submodule update --init --recursive
export CROSS_TC=arm-kindlehf-linux-gnueabihf
export PATH="$HOME/x-tools/arm-kindlehf-linux-gnueabihf/bin:$PATH"
make kindle

# 3. zlib + libzip, cross-built into a sysroot (not vendored -- see below)
cd ~ && wget https://zlib.net/zlib-1.3.1.tar.gz && tar xf zlib-1.3.1.tar.gz
cd zlib-1.3.1
CC=arm-kindlehf-linux-gnueabihf-gcc AR=arm-kindlehf-linux-gnueabihf-ar \
  ./configure --static --prefix=/root/sysroot-kindlehf
make && make install

cd ~ && wget https://libzip.org/download/libzip-1.11.2.tar.gz && tar xf libzip-1.11.2.tar.gz
cd libzip-1.11.2 && mkdir build && cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=/path/to/repo/toolchain-kindle.cmake \
  -DCMAKE_INSTALL_PREFIX=/root/sysroot-kindlehf \
  -DBUILD_SHARED_LIBS=OFF -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF \
  -DENABLE_OPENSSL=OFF -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF \
  -DZLIB_LIBRARY=/root/sysroot-kindlehf/lib/libz.a -DZLIB_INCLUDE_DIR=/root/sysroot-kindlehf/include
make && make install
```

The Makefile's `SYSROOT` variable points at `/root/sysroot-kindlehf` --
this lives inside the WSL filesystem, not this repo, and needs rebuilding
if the WSL instance is ever recreated.

## Device access (for development)

SSH is via **KOReader's built-in SSH server** (Tools > Network > SSH
server in KOReader), port 2222, key-based auth only.

USBNetwork/usbnetlite do **not** work on this jailbreak stack -- they
depend on MRPI, which the `hdnext` stack doesn't ship. Don't waste time
on them; KOReader's SSH server is the actual working path, confirmed
over WiFi.

```
ssh-keygen -t ed25519 -f ~/.ssh/kindle_ed25519 -N ""
# copy ~/.ssh/kindle_ed25519.pub into /mnt/us/koreader/settings/SSH/authorized_keys
# via USB mass storage, then toggle KOReader's SSH server off/on to reload it

ssh -i ~/.ssh/kindle_ed25519 -p 2222 root@<current-ip>
```

The Kindle's IP is DHCP-leased, not static -- check `;711` in the Kindle
search bar each session.

**Windows gotcha:** if SSH/ping to the Kindle stop working after a
network change on the dev PC, check `Get-NetConnectionProfile` -- if the
WiFi profile shows "Public" instead of "Private", Windows silently
blocks LAN traffic to the Kindle even though both devices show valid
ARP entries. Fix (elevated PowerShell):
`Set-NetConnectionProfile -Name "<profile>" -NetworkCategory Private`

### Dev tools

- `tools/deploy.sh` -- builds and scp's the binary to a running device
  (`KINDLE_IP=<ip> ./tools/deploy.sh`)
- `tools/grab.sh` -- screenshots the live e-ink screen for visual
  verification, run from WSL (`KINDLE_IP=<ip> ./tools/grab.sh out.png`).
  Reads `/dev/fb0` directly and converts with ImageMagick, since there's
  no `fbgrab` on this device. **The fb double-buffers**
  (`yres_virtual=3296=2x1648`) -- only the first `1248*1648` bytes are a
  real frame, or the capture comes out doubled/garbled.

## Architecture

- `src/main.c` -- entry point, signal handlers, event loop
- `src/app.c` / `app.h` -- screen state machine
- `src/fb.c` -- FBInk wrapper: framebuffer init, blitting, refresh
  policy (DU for list scroll, GC16 for page turns, flash every 6th turn)
- `src/input.c` -- evdev touch input: auto-detects the touchscreen node,
  protocol B multitouch, classifies taps/swipes
- `src/library.c` -- scans `/mnt/us/tachikindle/library/` into
  series/chapters, natural sort
- `src/archive.c` -- CBZ reading via libzip, natural sort, exclusion
  rules (`__MACOSX/`, `Thumbs.db`, `ComicInfo.xml`, dotfiles)
- `src/image.c` -- stb_image decode, aspect-fit scaling, grayscale,
  16-level ordered dither, 40-megapixel decode ceiling
- `src/progress.c` -- reading position, atomic (write-then-rename) save
- `src/ui_library.c` / `ui_chapters.c` / `ui_reader.c` -- the three screens
- `src/widget.c` -- shared e-ink UI primitives (boxes, lists, toasts)
- `src/signals.c` -- crash safety (SIGSEGV/SIGBUS/SIGTERM handlers)
- `extension/TachiKindle.sh` -- the Scriptlet launcher; stops/restarts
  `lab126_gui`, restores the UI even if killed or the binary crashes

See `.hermes/plans/2026-09-18_TachiKindle-implementation-plan.md` for
the full phase-by-phase build plan this followed.

## Known issues / not yet built

- **CBZ only.** CBR/RAR support was explicitly deferred (see the plan's
  scope section) -- needs vendoring unrar.
- **No cover thumbnails.** The library screen is a text list of series
  names, not a cover grid. Thumbnail generation (decode + cache) was
  deferred as speculative until a reader existed to open into -- it's
  now a reasonable next step.
- **No settings UI / rescan command.** Config is implicit (fixed paths
  under `/mnt/us/tachikindle/`); relaunching the app rescans the library
  automatically, there's no in-app "rescan" action yet.
- **Reader scaling is a known rough edge.** Pages are blitted at native
  decode resolution clipped to the screen, not resampled to fit --
  correct for already screen-sized scans, visibly wrong for
  oversized/undersized source images. Wiring in `stb_image_resize2`
  (already vendored) is the fix.
- **Touch coordinate calibration was not interactively verified.** The
  auto-detection (`ABS_MT_POSITION_X` probing) and event parsing are
  confirmed correct and the timeout path was verified live, but no one
  physically tapped the touchscreen during a real session to confirm
  swipe direction isn't inverted by a rotation quirk. Worth a first-use
  sanity check.
- **No online sources.** Deliberately out of scope for v1 -- see the
  plan's Phase 8 for what that would take (TLS, an HTML parser, a
  declarative per-site scraper format) and why it's a separate project
  once the offline reader is stable.

## Verified on real hardware (2026-09-19)

Every phase of the build plan was checked against the actual device, not
just compiled and assumed working:

- Toolchain, FBInk, and the stop/start UI lifecycle (Phase 0)
- Framebuffer + evdev input layers, including a live smoke test (Phase 2)
- Full navigation (library -> chapters -> reader, back at every level)
  via host-side integration tests, plus the real binary opening a real
  CBZ and drawing a decoded page on the e-ink screen (Phase 3)
- The Scriptlet launcher restoring the Kindle UI both on normal exit and
  after `kill -TERM`, confirmed the background binary actually dies too
  (Phase 4)
- The screenshot tool, which caught a real framebuffer double-buffering
  bug on first use (Phase 5)
- Crash-safety signal handlers, a 40-megapixel decode ceiling, and
  performance/memory/battery on a synthetic 500-chapter library: 7.7ms
  cold scan, ~4.7MB peak RSS, under 1% CPU idle (Phase 6)

26 assertions across 6 host-side test binaries pass via `make test`.
