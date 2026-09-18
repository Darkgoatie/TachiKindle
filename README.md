# TachiKindle

A Tachiyomi-style manga/comic reader for jailbroken Kindles.

## Target

Device: Kindle Paperwhite (11th gen), board malbec_bellatrix
Firmware: 5.19.2 (kernel 4.9.77-lab126, armv7l)
Jailbreak: SpringBreak v1.3.7 (KindleModding hdnext stack)
Toolchain: kindlehf (arm-kindlehf-linux-gnueabihf), built in WSL2 Ubuntu 26.04
Screen: 1236x1648 @ 298.99dpi, 8bpp grayscale, MONO10
Framebuffer: /dev/fb0 double-buffers (yres_virtual=3296=2x1648); when
reading it raw (screenshots), only take the first 1248*1648 bytes
(one page) via `dd bs=1248 count=1648`, or the capture is garbled/doubled.
Launcher: Scriptlet (SH_Integration) — KUAL is obsolete on this stack, not used
UI stop/start: `stop lab126_gui` / `start lab126_gui` — `/etc/init.d/framework`
does not exist on this firmware, don't rely on it as primary.

## Device access

SSH is via KOReader's built-in SSH server (Tools > Network > SSH server),
port 2222, key-based auth only. USBNetwork/usbnetlite do NOT work on this
jailbreak stack (they depend on MRPI, which hdnext doesn't ship) — don't
waste time on them, use KOReader's server instead.

- Key pair: `~/.ssh/kindle_ed25519` (already generated)
- Public key installed at: `/mnt/us/koreader/settings/SSH/authorized_keys`
- IP is DHCP-leased, NOT static — check `;711` in the Kindle search bar
  each session before connecting.
- Connect: `ssh -i ~/.ssh/kindle_ed25519 -p 2222 root@<current-ip>`
- Deploy binary: `KINDLE_IP=<current-ip> ./tools/deploy.sh`

Gotcha: if SSH/ping to the Kindle stop working after a network change on
this PC, check `Get-NetConnectionProfile` — if the WiFi profile shows
"Public" instead of "Private", Windows silently blocks LAN traffic to the
Kindle even though both devices show valid ARP entries. Fix (elevated
PowerShell): `Set-NetConnectionProfile -Name "<profile>" -NetworkCategory Private`

## Build

Cross-compiling happens in WSL2 (Ubuntu), not native Windows —
koxtoolchain doesn't build there and KindleModding's prebuilt release
targets Linux.

```
wsl -d Ubuntu
export PATH="$HOME/x-tools/arm-kindlehf-linux-gnueabihf/bin:$PATH"
cd /mnt/c/Users/halit/Desktop/Projects/TachiKindle
make
```

Toolchain source: `https://github.com/KindleModding/koxtoolchain` (prebuilt
`kindlehf.tar.gz` release, extracted to `~/x-tools/` inside WSL).
FBInk source: `https://github.com/KindleModding/FBInk` (their fork, kept
in sync with this jailbreak stack — vendored as a submodule at
`third_party/FBInk`, built with `make kindle` inside WSL).

libzip is cross-compiled (not vendored as a submodule) into
`/root/sysroot-kindlehf` inside WSL, following `toolchain-kindle.cmake`
at the repo root:
```
# zlib first (libzip depends on it), then libzip itself:
CC=arm-kindlehf-linux-gnueabihf-gcc AR=arm-kindlehf-linux-gnueabihf-ar \
  ./configure --static --prefix=/root/sysroot-kindlehf   # in zlib source dir
make && make install

cmake .. -DCMAKE_TOOLCHAIN_FILE=/path/to/repo/toolchain-kindle.cmake \
  -DCMAKE_INSTALL_PREFIX=/root/sysroot-kindlehf \
  -DBUILD_SHARED_LIBS=OFF -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF \
  -DENABLE_OPENSSL=OFF -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF \
  -DZLIB_LIBRARY=/root/sysroot-kindlehf/lib/libz.a -DZLIB_INCLUDE_DIR=/root/sysroot-kindlehf/include
make && make install   # in libzip source dir
```
The Makefile's `SYSROOT` variable points at `/root/sysroot-kindlehf` --
this is WSL-local and will need rebuilding if the WSL instance is ever
recreated (it is not part of this repo, deliberately, since it's build
output, not source).

## Status

Phase 0 complete and verified end-to-end on real hardware (2026-09-19):
cross-compiled a static ARM binary in WSL2, deployed it over SSH, it
stopped the Kindle UI, drew "TachiKindle: hello" on the actual e-ink
screen via FBInk, and the UI restarted cleanly. Toolchain, FBInk, SSH
access, and the stop/start UI lifecycle are all confirmed working.

Phase 1 complete (2026-09-19): host-side core built and TDD'd with plain
gcc inside WSL2 (no device needed) — progress store (atomic save, tolerant
load), CBZ archive reader (natural sort, exclusion rules, libzip), library
scanner (series/chapter discovery), image pipeline (stb_image decode,
aspect-fit scaling, Rec.709 grayscale, 16-level ordered dither). 21/21
tests passing (`make test`).

Phase 2 complete (2026-09-19): framebuffer wrapper (fb.c, FBInk-backed,
DU/GC16 refresh policy with periodic flash), evdev input (auto-detects
the touchscreen node, protocol B multitouch, tap/swipe classification),
widget primitives, and logging. Verified on device via a smoke test that
drew a list and correctly timed out waiting for touch.

Phase 3 complete (2026-09-19): the actual app — state machine (app.c),
library screen, chapter list (progress markers), and reader (tap-third
navigation, zoom modes, progress autosave, chapter auto-advance). Real
gcc integration tests (`test_navigation`, `test_reader_load`) verify
screen transitions and the archive->decode->grayscale chain without
hardware; the full binary was also deployed and run on the real Kindle,
confirmed opening a real CBZ and drawing a decoded page to the e-ink
screen (log-verified since it ran headless over SSH).

Phase 4 complete (2026-09-19): Scriptlet packaging via SH_Integration
(`extension/TachiKindle.sh` + `make package`). Verified on device: the
scriptlet stops lab126_gui, runs the binary, restores the UI on normal
exit AND on SIGTERM/SIGINT (confirmed by killing the wrapper mid-run and
checking the binary died + lab126_gui came back).

Phase 5 in progress: `tools/deploy.sh` (scp+chmod) and `tools/grab.sh`
(screenshot via raw /dev/fb0 read + ImageMagick, run from WSL) both
verified working — grab.sh caught a real bug (fb double-buffering) and
produced a correct screenshot of the live library screen showing the
"Demo" test series.

Next: Phase 6 (hardening: crash safety, memory ceiling, perf, battery).

Phase 6 complete (2026-09-19): signal handlers (SIGSEGV/SIGBUS/SIGTERM)
in signals.c shut down the framebuffer cleanly on a fatal crash, on top
of the launcher scriptlet's own trap (belt-and-suspenders, verified in
Phase 4). image_decode() now rejects images over 40 megapixels via
stb_image's header-only info parse before committing to a full decode,
protecting the device's limited RAM against a pathological source file.
Measured on real hardware with a synthetic 500-chapter (20 series x 25
chapters) library: cold scan in 7.7ms (target was under 2s), ~4.7MB peak
RSS with the library loaded and drawn, and under 1% CPU sampled over 3s
of idle event-loop time (confirms input_poll's select() actually blocks
rather than busy-waiting). No index caching was needed at this scale.

## Layout

See the implementation plan in `.hermes/plans/2026-09-18_TachiKindle-implementation-plan.md`
for full directory structure, phase breakdown, and task list.
