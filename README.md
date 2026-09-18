# TachiKindle

A Tachiyomi-style manga/comic reader for jailbroken Kindles.

## Target

Device: Kindle Paperwhite (11th gen), board malbec_bellatrix
Firmware: 5.19.2 (kernel 4.9.77-lab126, armv7l)
Jailbreak: SpringBreak v1.3.7 (KindleModding hdnext stack)
Toolchain: kindlehf (arm-kindlehf-linux-gnueabihf), built in WSL2 Ubuntu 26.04
Screen: 1236x1648 @ 298.99dpi, 8bpp grayscale, MONO10
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

Next: Phase 2 (framebuffer + input device layer, needs the Kindle).

## Layout

See the implementation plan in `.hermes/plans/2026-09-18_TachiKindle-implementation-plan.md`
for full directory structure, phase breakdown, and task list.
