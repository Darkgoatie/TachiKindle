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
echo "wrote tests/fixtures/simple.cbz"
