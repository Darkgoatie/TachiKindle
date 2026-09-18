#!/bin/sh
set -e
cd "$(dirname "$0")/.."

mkdir -p tests/fixtures
rm -rf tests/fixtures/src tests/fixtures/simple.cbz
mkdir -p tests/fixtures/src

# 3 tiny fake "images" -- content doesn't matter, archive.c only needs to
# list/extract, decoding is image.c's job (tested separately in Task 1.8)
cd tests/fixtures/src
printf 'fake-page-one'   > page001.png
printf 'fake-page-two'   > page002.png
printf 'fake-page-three' > page003.png
# non-image junk that must be excluded
printf 'not an image'    > Thumbs.db
printf '<xml/>'          > ComicInfo.xml
mkdir -p __MACOSX
printf 'mac junk'        > __MACOSX/._page001.png
cd ..
zip -q -r simple.cbz src
rm -rf src
cd ../..
echo "wrote tests/fixtures/simple.cbz"

# --- library fixture tree ---
rm -rf tests/fixtures/library
mkdir -p tests/fixtures/library/Alpha tests/fixtures/library/Beta/Vol01 tests/fixtures/library/Empty

mkdir -p /tmp/ci_ch_src
printf 'a' > /tmp/ci_ch_src/1.jpg
(cd /tmp/ci_ch_src && zip -q /tmp/ch1.cbz 1.jpg)
mv /tmp/ch1.cbz tests/fixtures/library/Alpha/Ch1.cbz
rm -rf /tmp/ci_ch_src

mkdir -p /tmp/ci_ch_src
printf 'a' > /tmp/ci_ch_src/1.jpg
(cd /tmp/ci_ch_src && zip -q /tmp/ch2.cbz 1.jpg)
mv /tmp/ch2.cbz tests/fixtures/library/Alpha/Ch2.cbz
rm -rf /tmp/ci_ch_src

mkdir -p /tmp/ci_ch_src
printf 'a' > /tmp/ci_ch_src/1.jpg
(cd /tmp/ci_ch_src && zip -q /tmp/ch10.cbz 1.jpg)
mv /tmp/ch10.cbz tests/fixtures/library/Alpha/Ch10.cbz
rm -rf /tmp/ci_ch_src

printf 'b' > tests/fixtures/library/Beta/Vol01/001.jpg
printf 'b' > tests/fixtures/library/Beta/Vol01/002.jpg

echo "wrote tests/fixtures/library/"
