#!/bin/sh
# Builds a synthetic 500-chapter library (20 series x 25 chapters) for
# performance testing (plan Phase 6, Task 6.3). Each chapter is a tiny
# valid CBZ so archive_open succeeds, since we're measuring scan speed
# not decode speed.
set -e
cd "$(dirname "$0")/.."

OUT=/tmp/perf_library
rm -rf "$OUT"
mkdir -p "$OUT"

mkdir -p /tmp/perf_src
printf 'a' > /tmp/perf_src/1.jpg

for s in $(seq 1 20); do
  mkdir -p "$OUT/Series$s"
  for c in $(seq 1 25); do
    (cd /tmp/perf_src && zip -q /tmp/perf_ch.cbz 1.jpg)
    mv /tmp/perf_ch.cbz "$OUT/Series$s/Ch$c.cbz"
  done
done

rm -rf /tmp/perf_src
echo "wrote $OUT ($(find "$OUT" -name '*.cbz' | wc -l) chapters)"
