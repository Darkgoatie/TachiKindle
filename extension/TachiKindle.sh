#!/bin/sh
# Name: TachiKindle
# Author: Halit
# DontUseFBInk

EXTDIR="/mnt/us/tachikindle"
BIN="$EXTDIR/tachikindle"
LOG="$EXTDIR/tachikindle.log"

mkdir -p "$EXTDIR/library" "$EXTDIR/cache/thumbs"

restore_ui() {
    [ -x /usr/bin/lipc-set-prop ] && lipc-set-prop com.lab126.powerd preventScreenSaver 0
    if command -v start >/dev/null 2>&1 && [ -x /sbin/start ]; then
        start lab126_gui >>"$LOG" 2>&1
    elif [ -x /etc/init.d/framework ]; then
        /etc/init.d/framework start >>"$LOG" 2>&1
    fi
}
# Belt-and-suspenders: if this script itself gets killed (not just the
# binary crashing), the Kindle UI must still come back, and the binary
# must not be left running headless in the background. A jailbreak tool
# that can strand the user on a black screen loses their trust for good.
on_signal() {
    [ -n "$BIN_PID" ] && kill "$BIN_PID" 2>/dev/null
    restore_ui
    exit 143
}
trap on_signal TERM INT

# Stop the Kindle UI so it stops fighting us for the framebuffer.
# Confirmed on-device (2026-09-19): /etc/init.d/framework does not exist
# on this firmware -- stop/start lab126_gui is the real path here, not a
# fallback (see README "Target" section).
if command -v stop >/dev/null 2>&1 && [ -x /sbin/stop ]; then
    stop lab126_gui >>"$LOG" 2>&1
elif [ -x /etc/init.d/framework ]; then
    /etc/init.d/framework stop >>"$LOG" 2>&1
fi

[ -x /usr/bin/lipc-set-prop ] && lipc-set-prop com.lab126.powerd preventScreenSaver 1

"$BIN" >>"$LOG" 2>&1 &
BIN_PID=$!
wait "$BIN_PID"
RC=$?

restore_ui
exit $RC
