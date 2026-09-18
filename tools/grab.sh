#!/bin/sh
# Pull a screenshot from the Kindle framebuffer for visual verification.
# The panel is 1236x1648 @ 8bpp grayscale. Confirmed on-device (2026-09-19):
# /dev/fb0 double-buffers (yres_virtual=3296=2x1648, line_length=1248 with
# 12px padding past xres=1236) -- read only the first 1248*1648 bytes
# (one page) via dd, or the capture comes out doubled/garbled.
#
# Run this from WSL -- Windows has no ImageMagick installed, and the SSH
# key needs 600 perms which the Windows-side copy under /mnt/c can't hold.
#
# Usage (inside WSL): KINDLE_IP=192.168.1.45 ./tools/grab.sh [output.png]
set -e
KINDLE_IP="${KINDLE_IP:?set KINDLE_IP to the current value from ;711 on-device}"
KEY="${SSH_KEY:-$HOME/.ssh/kindle_ed25519}"
OUT="${1:-shot.png}"

RAW=$(mktemp)
ssh -i "$KEY" -p 2222 -o StrictHostKeyChecking=no "root@$KINDLE_IP" \
  'dd if=/dev/fb0 bs=1248 count=1648 2>/dev/null' > "$RAW"

# line_length (1248) > xres (1236): crop the 12px-per-row padding, or
# the image comes out sheared.
magick -depth 8 -size 1248x1648 gray:"$RAW" -crop 1236x1648+0+0 +repage "$OUT"
rm -f "$RAW"
echo "wrote $OUT"
