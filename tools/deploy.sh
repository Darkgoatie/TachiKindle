#!/bin/sh
# Deploy the comicink binary to the Kindle over SSH (KOReader's built-in server, port 2222).
# The Kindle's IP is DHCP-leased and changes; check ;711 on-device each session.
#
# Usage: KINDLE_IP=192.168.1.45 ./tools/deploy.sh
KINDLE_IP="${KINDLE_IP:?set KINDLE_IP to the current value from ;711 on-device}"
KEY="${HOME}/.ssh/kindle_ed25519"

make || exit 1
ssh -i "$KEY" -p 2222 root@"$KINDLE_IP" 'mkdir -p /mnt/us/comicink/bin /mnt/us/comicink/library /mnt/us/comicink/cache/thumbs'
scp -i "$KEY" -P 2222 comicink root@"$KINDLE_IP":/mnt/us/comicink/bin/comicink
ssh -i "$KEY" -p 2222 root@"$KINDLE_IP" 'chmod +x /mnt/us/comicink/bin/comicink'
echo "deployed to $KINDLE_IP"
