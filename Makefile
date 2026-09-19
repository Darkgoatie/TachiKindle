CROSS   ?= arm-kindlehf-linux-gnueabihf-
CC       = $(CROSS)gcc
FBINK    = third_party/FBInk
SYSROOT  = /root/sysroot-kindlehf
CFLAGS   = -std=gnu11 -O2 -Wall -Wextra -Isrc -I$(FBINK) -Ithird_party/stb -Ithird_party/cjson -I$(SYSROOT)/include
LDFLAGS  = -static -L$(SYSROOT)/lib
LDLIBS   = $(FBINK)/Release/libfbink.a -lzip -lz -lm

SRCS = src/main.c src/app.c src/fb.c src/input.c src/widget.c src/log.c \
       src/library.c src/progress.c src/archive.c src/image.c \
       src/ui_library.c src/ui_chapters.c src/ui_reader.c src/signals.c \
       src/repo.c src/repo_store.c src/ui_repo.c third_party/cjson/cJSON.c

tachikindle: $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $@ $(LDLIBS) $(LDFLAGS)

clean:
	rm -f tachikindle

package: tachikindle
	rm -rf build/pkg
	mkdir -p build/pkg/tachikindle
	cp tachikindle build/pkg/tachikindle/tachikindle
	chmod +x build/pkg/tachikindle/tachikindle
	cp extension/TachiKindle.sh build/pkg/documents_TachiKindle.sh
	@echo "Copy build/pkg/tachikindle/ to /mnt/us/tachikindle/"
	@echo "Copy build/pkg/documents_TachiKindle.sh to /mnt/us/documents/TachiKindle.sh"

HOSTCC = gcc
HOSTCFLAGS = -std=gnu11 -g -O0 -Wall -Wextra -Isrc -Itests -Ithird_party/stb

perf_scan: tools/perf_scan.c src/library.c
	$(HOSTCC) -std=gnu11 -O2 -Isrc $^ -o $@

test: test_progress test_archive test_library test_image test_navigation test_reader_load test_repo test_repo_store
	./test_progress
	./test_archive
	./test_library
	./test_image
	./test_navigation
	./test_reader_load
	./test_repo
	./test_repo_store

test_archive: tests/test_archive.c src/archive.c
	$(HOSTCC) $(HOSTCFLAGS) $^ -o $@ -lzip

test_image: tests/test_image.c src/image.c
	$(HOSTCC) $(HOSTCFLAGS) $^ -o $@ -lm

test_repo: tests/test_repo.c src/repo.c third_party/cjson/cJSON.c
	$(HOSTCC) $(HOSTCFLAGS) -Ithird_party/cjson $^ -o $@

test_repo_store: tests/test_repo_store.c src/repo_store.c third_party/cjson/cJSON.c
	$(HOSTCC) $(HOSTCFLAGS) -Ithird_party/cjson $^ -o $@

test_navigation: tests/test_navigation.c tests/fb_stub.c src/app.c src/library.c src/progress.c src/archive.c src/ui_library.c src/ui_chapters.c src/ui_reader.c src/ui_repo.c src/repo.c src/repo_store.c src/image.c src/widget.c src/log.c src/input.c third_party/cjson/cJSON.c
	$(HOSTCC) $(HOSTCFLAGS) -Ithird_party/cjson $^ -o $@ -lzip -lm

test_reader_load: tests/test_reader_load.c src/archive.c src/image.c
	$(HOSTCC) $(HOSTCFLAGS) $^ -o $@ -lzip -lm

test_%: tests/test_%.c src/%.c
	$(HOSTCC) $(HOSTCFLAGS) $^ -o $@ $(HOSTLIBS)

clean-tests:
	rm -f test_progress test_archive test_library test_image
