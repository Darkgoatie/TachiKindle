# ComicInKindle

A Tachiyomi-style manga/comic reader for jailbroken Kindles.

## Target

Device: Kindle Paperwhite (11th gen), board malbec_bellatrix
Firmware: 5.19.2 (kernel 4.9.77-lab126, armv7l)
Jailbreak: SpringBreak v1.3.7 (KindleModding hdnext stack)
Toolchain: kindlehf (arm-kindlehf-linux-gnueabihf)
Screen: 1236x1648 @ 298.99dpi, 8bpp grayscale, MONO10
Launcher: Scriptlet (SH_Integration) — KUAL is obsolete on this stack, not used

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

## Status

Planning complete, see `.hermes/plans/`. SSH device access confirmed
working. Blocked on WSL2 finishing install for the cross-compiler
(Task 0.3) before any code can be built.

## Layout

See the implementation plan in `.hermes/plans/2026-09-18_ComicInKindle-implementation-plan.md`
for full directory structure, phase breakdown, and task list.
