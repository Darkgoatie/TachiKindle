CROSS   ?= arm-kindlehf-linux-gnueabihf-
CC       = $(CROSS)gcc
FBINK    = third_party/FBInk
CFLAGS   = -std=gnu11 -O2 -Wall -Wextra -I$(FBINK)
LDFLAGS  = -static
LDLIBS   = $(FBINK)/Release/libfbink.a -lm

tachikindle: src/main.c
	$(CC) $(CFLAGS) $< -o $@ $(LDLIBS) $(LDFLAGS)

clean:
	rm -f tachikindle

HOSTCC = gcc
HOSTCFLAGS = -std=gnu11 -g -O0 -Wall -Wextra -Isrc -Itests -Ithird_party/stb

test: test_progress test_archive test_library test_image
	./test_progress
	./test_archive
	./test_library
	./test_image

test_archive: tests/test_archive.c src/archive.c
	$(HOSTCC) $(HOSTCFLAGS) $^ -o $@ -lzip

test_image: tests/test_image.c src/image.c
	$(HOSTCC) $(HOSTCFLAGS) $^ -o $@ -lm

test_%: tests/test_%.c src/%.c
	$(HOSTCC) $(HOSTCFLAGS) $^ -o $@ $(HOSTLIBS)

clean-tests:
	rm -f test_progress test_archive test_library test_image
