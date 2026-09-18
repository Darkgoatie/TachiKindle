# ComicInKindle

A Tachiyomi-style manga/comic reader for jailbroken Kindles.

## Target

Device: Kindle Paperwhite (11th gen)
Firmware: 5.19.2
Jailbreak: SpringBreak v1.3.7 (KindleModding hdnext stack)
Toolchain: kindlehf (arm-kindlehf-linux-gnueabihf)
Launcher: Scriptlet (SH_Integration) — KUAL is obsolete on this stack, not used
USBNetwork: pre-installed, toggle with `;un` / `;uns` in the Kindle search bar

## Status

Planning complete, see `.hermes/plans/`. Development not yet started —
blocked on WSL2 finishing install (for the cross-compiler) and confirming
SSH connectivity over USBNetwork.

## Layout

See the implementation plan in `.hermes/plans/2026-09-18_ComicInKindle-implementation-plan.md`
for full directory structure, phase breakdown, and task list.
