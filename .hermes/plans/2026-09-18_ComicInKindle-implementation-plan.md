# ComicInKindle — Implementation Plan

> **For Hermes:** Use subagent-driven-development to implement this plan task-by-task.

**Goal:** A Tachiyomi-style manga/comic reader that launches from KUAL on a jailbroken Kindle — browse a local library, open CBZ/CBR/PDF series, read page-by-page with e-ink-appropriate rendering, and resume where you left off.

**Architecture:** A single statically-linked ARM binary written in C. It takes over the framebuffer via FBInk, reads touch/key input from Linux evdev, and is launched by a **Scriptlet** (a `.sh` file dropped in `/mnt/us/documents/`, indexed as a book by SH_Integration) that stops the Kindle UI first. All state (library index, reading progress) lives in flat files under `/mnt/us/comicink/`. No Java, no Kindlet, no network in v1.

**Tech Stack:** C11 · FBInk (rendering + EPDC refresh control) · libzip (CBZ) · stb_image (JPEG/PNG decode) · Linux evdev (input) · KindleModding's `koxtoolchain` fork (`kindlehf` for FW ≥ 5.16.3, hard-float) · Make

**Confirmed device (2026-09-18):** Kindle Paperwhite, 11th gen, FW 5.19.2, jailbroken via **SpringBreak v1.3.7** (KindleModding, `hdnext` stack). This stack has **replaced KUAL** with Scriptlets + KPM — see Phase 4 rewrite below. USBNetwork ships pre-installed; toggle with `;un` / `;uns` in the search bar, no install step needed.

---

## 1. Current Context & Assumptions

**Repo state:** `C:\Users\halit\Desktop\Projects\ComicInKindle` contains only an empty `IDEA.md.txt`. No git repo yet.

**Assumptions that must be confirmed before Phase 0 (see Open Questions):**
- Target device is a Kindle on FW ≥ 5.16.3 (hard-float → `kindlehf` toolchain). If the device is older, swap to `kindlepw2` (soft-float) — this changes the toolchain triple and ABI flags but nothing above the build layer.
- The jailbreak includes **SH Integration** (`.sh` launchers appear as books) and either classic KUAL or KUAL Next is installed.
- USBNet or wifi SSH access to the device is available for the dev loop. Without it, iteration drops to sneakernet-over-USB and gets painful.

**Why C and not Lua-on-KOReader:** KOReader already has a comic reader, so a plugin would be reinventing it inside someone else's app. A standalone binary is the "own app" the goal asks for, boots in under a second, and has no runtime dependency beyond libc. The cost is that we write our own UI toolkit — which is why Phase 2 exists.

**Why not Python:** Python 3 on a Kindle takes 2–4s to cold start and image decode in pure Python is unusably slow for 1448x1072 pages.

---

## 2. Scope

### In scope for v1.0
- Local library scan of `/mnt/us/comicink/library/`
- CBZ (zip) and plain image-folder series; CBR deferred
- Grid library view with cover thumbnails
- Chapter list per series
- Page reader: next/prev, fit-to-screen, resume position
- Two-level zoom (fit page / fit width + pan)
- Persistent reading progress per series
- KUAL menu entry that launches and cleanly restores the Kindle UI on exit

### Explicitly out of scope for v1.0 (YAGNI)
- Online sources / extension catalogue (the actual Tachiyomi killer feature — Phase 8 stretch)
- CBR/RAR (needs unrar, licensing and size cost)
- PDF (needs mupdf, doubles binary size)
- Downloads, tracking, MAL/AniList sync
- Settings UI (config is a text file in v1)

---

## 3. Directory Layout

```
ComicInKindle/
├── Makefile
├── README.md
├── IDEA.md
├── src/
│   ├── main.c              # entry, event loop, screen state machine
│   ├── app.h               # app state struct, screen enum
│   ├── fb.c / fb.h         # FBInk wrapper: init, blit, refresh policy
│   ├── input.c / input.h   # evdev reader -> normalized events
│   ├── archive.c/.h        # CBZ open, list entries, extract to memory
│   ├── image.c / image.h   # decode + scale + grayscale + dither
│   ├── library.c / .h      # scan dirs, build/refresh index
│   ├── progress.c / .h     # read/write progress file
│   ├── ui_library.c        # grid view
│   ├── ui_chapters.c       # chapter list view
│   ├── ui_reader.c         # page reader
│   ├── widget.c / .h       # shared draw helpers: text, box, list, button
│   └── log.c / log.h
├── third_party/
│   ├── FBInk/              # submodule
│   ├── libzip/             # submodule or vendored
│   └── stb/                # stb_image.h, stb_image_resize2.h
├── extension/              # the Scriptlet, copied in by `make package`
│   └── ComicInKindle.sh    # single .sh file — metadata is comment headers, no manifest needed
├── tests/
│   ├── test_archive.c
│   ├── test_library.c
│   ├── test_progress.c
│   ├── test_image.c
│   └── minunit.h
├── tools/
│   ├── deploy.sh           # scp binary to device + restart
│   ├── grab.sh             # pull a framebuffer screenshot back
│   └── mkfixtures.sh       # generate test CBZ files
└── .hermes/plans/
```

**Why host-buildable modules matter:** `archive.c`, `library.c`, `progress.c`, and `image.c` have zero Kindle dependencies. They compile and unit-test natively on the dev machine. Only `fb.c`, `input.c`, and the `ui_*.c` files need a device or emulator. Keep that boundary clean — it's what makes TDD possible here.

---

## 4. On-Device Layout

```
/mnt/us/comicink/
├── library/
│   ├── Berserk/
│   │   ├── cover.jpg              (optional; else first page of ch 1)
│   │   ├── Ch001.cbz
│   │   └── Ch002.cbz
│   └── Blame/
│       └── Vol01/                 (loose-image chapter also supported)
│           ├── 001.jpg
│           └── 002.jpg
├── bin/
│   └── comicink                   (the built binary)
├── cache/
│   └── thumbs/<hash>.raw          (pre-scaled 8bpp grayscale thumbnails)
├── progress.tsv                   (series<TAB>chapter<TAB>page<TAB>mtime)
├── config.cfg
└── comicink.log

/mnt/us/documents/ComicInKindle.sh   (the Scriptlet — appears as a book, launches everything)
```

`/mnt/us` is the USB-visible partition, so the user drags CBZ files in over USB with no SSH needed. This is the whole distribution story — do not put content anywhere else.

---

## Phase 0 — Environment & Skeleton

### Task 0.1: Initialize repository

**Files:** Create `.gitignore`, `README.md`; rename `IDEA.md.txt` → `IDEA.md`

**Step 1:** Run

```bash
cd /c/Users/halit/Desktop/Projects/ComicInKindle
git init
mv IDEA.md.txt IDEA.md
```

**Step 2:** Create `.gitignore`:

```
build/
*.o
*.a
extension/bin/comicink
tests/fixtures/*.cbz
third_party/*/
!third_party/stb/
```

**Step 3:** Commit.

```bash
git add -A && git commit -m "initial repo skeleton"
```

**Expected:** `git log --oneline` shows one commit.

---

### Task 0.2: Confirm the target device and pick the toolchain — DONE

**Objective:** Lock the ABI before writing any code, because it is expensive to change later.

**Confirmed:** Kindle Paperwhite 11th gen, FW 5.19.2 (board `malbec_bellatrix`), kernel 4.9.77-lab126, `kindlehf` triple (`arm-kindlehf-linux-gnueabihf`), flags `-march=armv7-a -mtune=cortex-a7 -mfpu=neon -mfloat-abi=hard -mthumb`.

**Screen (confirmed via `eips -i` over SSH, 2026-09-18):** 1236x1648 @ 298.99dpi, 8bpp grayscale, MONO10 packed pixels, `line_length` 1248 (padded), rotate=3. This is the resolution to target for all UI layout in Phase 3.

**SSH access confirmed working:** via KOReader's built-in SSH server (port 2222, key-based auth only — no password). Device reachable over WiFi at a DHCP-leased IP (check via `;711` on-device each session, it is not static). Key pair generated at `~/.ssh/kindle_ed25519`, public key placed in `/mnt/us/koreader/settings/SSH/authorized_keys`. usbnetlite/USBNetwork were abandoned as a dead end for this device (see below) — KOReader's SSH server is the actual working path.

**Important — Windows network profile gotcha:** this network's WiFi profile was set to "Public" in Windows, which silently blocks outbound LAN connections (ping, SSH) to other devices on the same subnet, including the Kindle, even though both devices show valid ARP entries. Fixed via (elevated PowerShell): `Set-NetConnectionProfile -Name "<profile>" -NetworkCategory Private`. If SSH/ping to the Kindle mysteriously stops working again after a network change, check this first before assuming a device-side problem.

**Record in README.md under "Target":**

```
## Target
Device: Kindle Paperwhite (11th gen)
Firmware: 5.19.2
Jailbreak: SpringBreak v1.3.7 (KindleModding hdnext stack)
Toolchain: kindlehf (arm-kindlehf-linux-gnueabihf)
Launcher: Scriptlet (SH_Integration), NOT KUAL — KUAL is obsolete on hdnext
```

---

### Task 0.3: Install the cross toolchain

**Objective:** Get a working `arm-kindle*-gcc`.

**Note:** koxtoolchain does not build on Windows. Use WSL2 (Ubuntu) — it also gives us the vfb emulator later, so this is the right place to live for the whole project.

**Step 1:** In WSL2:

```bash
sudo apt update
sudo apt install -y build-essential git autoconf automake bison flex texinfo \
  help2man gawk libtool libtool-bin libncurses-dev unzip wget cmake pkg-config
```

**Step 2:** Prefer the **prebuilt** toolchain over a build. KindleModding maintains their own fork with prebuilt releases matching current firmware:

```bash
cd ~
# Check https://github.com/KindleModding/koxtoolchain/releases for the current asset name
wget https://github.com/KindleModding/koxtoolchain/releases/latest/download/kindlehf.tar.gz
tar xf kindlehf.tar.gz          # unpacks into ~/x-tools/arm-kindlehf-linux-gnueabihf
echo 'export PATH="$HOME/x-tools/arm-kindlehf-linux-gnueabihf/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Fallback if no prebuilt asset matches:

```bash
git clone https://github.com/KindleModding/koxtoolchain ~/koxtoolchain
cd ~/koxtoolchain && ./gen-tc.sh kindlehf     # ~40 min
```

**Step 3:** Verify:

```bash
arm-kindlehf-linux-gnueabihf-gcc --version
```

**Expected:** prints a gcc version, exit 0.

**Step 4:** Smoke-test a real binary:

```bash
echo 'int main(){return 0;}' > /tmp/t.c
arm-kindlehf-linux-gnueabihf-gcc -static /tmp/t.c -o /tmp/t
file /tmp/t
```

**Expected:** `ELF 32-bit LSB executable, ARM, EABI5 ... statically linked`

---

### Task 0.4: Vendor FBInk and build it for Kindle

**Files:** `third_party/FBInk/`

**Step 1:** Use KindleModding's fork (kept in sync with the `hdnext` jailbreak stack) rather than upstream NiLuJe/FBInk directly:

```bash
git submodule add https://github.com/KindleModding/FBInk third_party/FBInk
cd third_party/FBInk
git submodule update --init --recursive
```

**Step 2:** Build the static Kindle library:

```bash
make kindle   # stripped static build; equivalent to KINDLE=1 + static
```

**Step 3:** Verify:

```bash
ls -la Release/libfbink.a
arm-kindlehf-linux-gnueabihf-nm Release/libfbink.a | grep -c fbink_init
```

**Expected:** `libfbink.a` exists; grep count ≥ 1.

**Step 4:** Commit the submodule pointer.

**Pitfall:** FBInk's build picks the cross compiler from `CROSS_TC`/`CROSS_COMPILE`. If it silently builds an x86 lib, you get link errors much later that look unrelated. Always run the `file`/`nm` check.

---

### Task 0.5: Hello-world on the actual screen

**Objective:** Prove the full chain — compile, deploy, draw, restore — before writing any app logic. This is the single highest-value task in the plan; everything after it is incremental.

**Files:** Create `src/main.c`, `Makefile`

**Step 1:** `src/main.c`:

```c
#include <stdio.h>
#include <unistd.h>
#include "fbink.h"

int main(void) {
    FBInkConfig cfg = { 0 };
    cfg.is_centered = true;
    cfg.is_halfway  = true;
    cfg.is_cleared  = true;

    int fbfd = fbink_open();
    if (fbfd < 0) { fprintf(stderr, "fbink_open failed\n"); return 1; }
    if (fbink_init(fbfd, &cfg) < 0) { fprintf(stderr, "fbink_init failed\n"); return 1; }

    fbink_print(fbfd, "ComicInKindle: hello", &cfg);
    sleep(5);

    cfg.is_cleared = true;
    fbink_cls(fbfd, &cfg, NULL, false);
    fbink_close(fbfd);
    return 0;
}
```

**Step 2:** Minimal `Makefile`:

```make
CROSS   ?= arm-kindlehf-linux-gnueabihf-
CC       = $(CROSS)gcc
FBINK    = third_party/FBInk
CFLAGS   = -std=gnu11 -O2 -Wall -Wextra -I$(FBINK)
LDFLAGS  = -static
LDLIBS   = $(FBINK)/Release/libfbink.a -lm

comicink: src/main.c
	$(CC) $(CFLAGS) $< -o $@ $(LDLIBS) $(LDFLAGS)

clean:
	rm -f comicink
```

**Step 3:** Build and check:

```bash
make
file comicink
```

**Expected:** statically linked ARM ELF.

**Step 4:** Deploy and run on device:

```bash
scp comicink root@<kindle-ip>:/mnt/us/
ssh root@<kindle-ip> '/etc/init.d/framework stop; /mnt/us/comicink; /etc/init.d/framework start'
```

**Expected:** The Kindle screen clears, shows "ComicInKindle: hello" centered for 5 seconds, then the normal UI comes back.

**Step 5:** Commit.

**Pitfalls:**
- If the Kindle UI redraws over your text, the framework was not actually stopped. On some firmwares it is `stop lab126_gui` instead of `/etc/init.d/framework stop`. Try both, record which one works in `README.md`.
- If you get stuck on a black screen, `ssh` in and run `/etc/init.d/framework start`. Always have a second terminal open.
- Never test this without a way back in. Confirm SSH works before stopping the framework the first time.

---

## Phase 1 — Host-Side Core (pure logic, fully TDD)

Everything in this phase builds and tests on the dev machine with the native `gcc`. No Kindle needed.

### Task 1.1: Test harness

**Files:** Create `tests/minunit.h`, add a `test` target to the Makefile.

**Step 1:** `tests/minunit.h` — a ~40-line assert-and-count header (no external framework; we are not adding a dependency for this).

```c
#ifndef MINUNIT_H
#define MINUNIT_H
#include <stdio.h>
#include <string.h>
extern int mu_tests_run, mu_tests_failed;
#define mu_assert(msg, test) do { \
    if (!(test)) { printf("  FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__); \
                   mu_tests_failed++; return; } } while (0)
#define mu_run(fn) do { printf("running %s\n", #fn); mu_tests_run++; fn(); } while (0)
#define MU_MAIN_BEGIN int mu_tests_run = 0, mu_tests_failed = 0; int main(void) {
#define MU_MAIN_END printf("%d run, %d failed\n", mu_tests_run, mu_tests_failed); \
                    return mu_tests_failed ? 1 : 0; }
#endif
```

**Step 2:** Makefile addition:

```make
HOSTCC = gcc
HOSTCFLAGS = -std=gnu11 -g -O0 -Wall -Wextra -Isrc -Itests -Ithird_party/stb

test: test_archive test_library test_progress test_image
	./test_archive && ./test_library && ./test_progress && ./test_image

test_%: tests/test_%.c src/%.c
	$(HOSTCC) $(HOSTCFLAGS) $^ -o $@ $(HOSTLIBS)
```

**Step 3:** Verify the harness fails when it should — write a throwaway test asserting `1 == 2`, run it, confirm exit code 1, then delete it.

**Step 4:** Commit.

---

### Task 1.2: Progress store — write the failing test

**Files:** Create `tests/test_progress.c`

The progress file is TSV: `series\tchapter\tpage\tmtime\n`. TSV not JSON because we are not linking a JSON parser for four fields, and it stays human-editable on the device.

```c
#include "minunit.h"
#include "progress.h"

static void test_roundtrip(void) {
    progress_t p = {0};
    progress_init(&p);
    progress_set(&p, "Berserk", "Ch003.cbz", 42);
    mu_assert("save ok", progress_save(&p, "/tmp/ci_prog.tsv") == 0);

    progress_t q = {0};
    progress_init(&q);
    mu_assert("load ok", progress_load(&q, "/tmp/ci_prog.tsv") == 0);
    mu_assert("page restored", progress_get_page(&q, "Berserk", "Ch003.cbz") == 42);
    progress_free(&p); progress_free(&q);
}

static void test_missing_returns_zero(void) {
    progress_t p = {0}; progress_init(&p);
    mu_assert("unknown -> 0", progress_get_page(&p, "Nope", "Nope") == 0);
    progress_free(&p);
}

static void test_update_overwrites(void) {
    progress_t p = {0}; progress_init(&p);
    progress_set(&p, "A", "1", 5);
    progress_set(&p, "A", "1", 9);
    mu_assert("overwritten", progress_get_page(&p, "A", "1") == 9);
    mu_assert("single entry", progress_count(&p) == 1);
    progress_free(&p);
}

static void test_corrupt_line_skipped(void) {
    FILE *f = fopen("/tmp/ci_bad.tsv", "w");
    fputs("garbage-with-no-tabs\nA\t1\t7\t0\n", f); fclose(f);
    progress_t p = {0}; progress_init(&p);
    mu_assert("load tolerates junk", progress_load(&p, "/tmp/ci_bad.tsv") == 0);
    mu_assert("good line kept", progress_get_page(&p, "A", "1") == 7);
    progress_free(&p);
}

MU_MAIN_BEGIN
    mu_run(test_roundtrip);
    mu_run(test_missing_returns_zero);
    mu_run(test_update_overwrites);
    mu_run(test_corrupt_line_skipped);
MU_MAIN_END
```

**Run:** `make test_progress` → **Expected: compile error, `progress.h` not found.** That is the correct RED state.

---

### Task 1.3: Progress store — implement

**Files:** Create `src/progress.h`, `src/progress.c`

```c
/* progress.h */
#ifndef CI_PROGRESS_H
#define CI_PROGRESS_H
#include <stddef.h>

typedef struct {
    char  *series;
    char  *chapter;
    int    page;
    long   mtime;
} progress_entry_t;

typedef struct {
    progress_entry_t *entries;
    size_t            count;
    size_t            cap;
} progress_t;

void   progress_init(progress_t *p);
void   progress_free(progress_t *p);
int    progress_load(progress_t *p, const char *path);
int    progress_save(const progress_t *p, const char *path);
void   progress_set(progress_t *p, const char *series, const char *chapter, int page);
int    progress_get_page(const progress_t *p, const char *series, const char *chapter);
size_t progress_count(const progress_t *p);
#endif
```

Implementation notes (write the body to satisfy the tests, nothing more):
- `progress_save` writes to `path.tmp` then `rename()`. Non-negotiable: the Kindle loses power mid-write and a truncated progress file must not eat the user's position.
- `progress_load` on a missing file returns 0 with an empty set — first run is not an error.
- Lines without exactly 4 tab-separated fields are skipped, not fatal.

**Run:** `make test_progress` → **Expected: `4 run, 0 failed`**

**Commit:** `git commit -m "progress store with atomic save"`

---

### Task 1.4: CBZ archive reader — failing test

**Files:** Create `tests/test_archive.c`, `tools/mkfixtures.sh`

**Step 1:** `tools/mkfixtures.sh` builds deterministic test archives:

```bash
#!/bin/sh
set -e
mkdir -p tests/fixtures/src
cd tests/fixtures/src
# 3 tiny valid PNGs, deliberately out of lexical order
for n in 003 001 002; do
  printf 'fake' > page$n.png
done
convert -size 8x8 xc:white page001.png 2>/dev/null || true
cd .. && zip -q -r simple.cbz src/*.png && rm -rf src
```

**Step 2:** The tests:

```c
static void test_open_lists_entries(void) {
    archive_t a;
    mu_assert("open", archive_open(&a, "tests/fixtures/simple.cbz") == 0);
    mu_assert("3 pages", archive_page_count(&a) == 3);
    archive_close(&a);
}

static void test_pages_are_natural_sorted(void) {
    archive_t a; archive_open(&a, "tests/fixtures/simple.cbz");
    mu_assert("p0", strstr(archive_page_name(&a, 0), "001"));
    mu_assert("p1", strstr(archive_page_name(&a, 1), "002"));
    mu_assert("p2", strstr(archive_page_name(&a, 2), "003"));
    archive_close(&a);
}

static void test_non_images_excluded(void) { /* Thumbs.db, ComicInfo.xml, __MACOSX/ must not count */ }
static void test_extract_to_memory(void)   { /* buffer non-NULL, size > 0 */ }
static void test_open_missing_fails(void)  { /* returns < 0, does not crash */ }
static void test_open_corrupt_fails(void)  { /* truncated zip returns < 0 */ }
```

**Run:** RED.

---

### Task 1.5: CBZ archive reader — implement

**Files:** Create `src/archive.h`, `src/archive.c`; add libzip

**Critical detail — natural sort:** Comic pages are named `1.jpg, 2.jpg, ..., 10.jpg`. Plain `strcmp` orders `10` before `2` and the reader shows pages in the wrong order. Implement `natcmp()` that compares digit runs numerically. This is the single most common bug in home-made comic readers.

**Critical detail — exclusions:** Skip directory entries, anything under `__MACOSX/`, dotfiles, `Thumbs.db`, and `ComicInfo.xml`. Accept only `.jpg .jpeg .png .webp .gif .bmp` by case-insensitive extension.

**Memory model:** `archive_read_page()` returns a malloc'd buffer the caller frees. Do not cache whole archives in RAM — a 200MB volume will not fit.

**Build libzip for ARM** (needs zlib first):

```bash
cd third_party/libzip && mkdir build && cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=../../toolchain-kindle.cmake \
         -DBUILD_SHARED_LIBS=OFF -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF \
         -DENABLE_ZSTD=OFF -DENABLE_OPENSSL=OFF -DBUILD_TOOLS=OFF \
         -DBUILD_REGRESS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF
make -j
```

Every `ENABLE_*=OFF` is deliberate — each one is a dependency we would otherwise have to cross-compile for no benefit.

**Run:** `make test_archive` → **Expected: 6 run, 0 failed**

---

### Task 1.6: Library scanner — failing test

**Files:** `tests/test_library.c`

```c
static void test_scan_finds_series(void);        /* 2 dirs -> 2 series */
static void test_series_lists_chapters(void);    /* .cbz files, natural sorted */
static void test_loose_image_dir_is_chapter(void);
static void test_empty_dir_ignored(void);
static void test_nonexistent_root_is_empty_not_crash(void);
```

Fixture tree built by `mkfixtures.sh`:

```
tests/fixtures/library/
├── Alpha/{Ch1.cbz, Ch2.cbz, Ch10.cbz}
├── Beta/Vol01/{001.jpg, 002.jpg}
└── Empty/
```

`Ch10.cbz` is there specifically to catch natural-sort regressions at the library level too.

---

### Task 1.7: Library scanner — implement

**Files:** `src/library.h`, `src/library.c`

Model:

```c
typedef struct { char *name; char *path; int is_dir_chapter; } chapter_t;
typedef struct { char *name; char *path; chapter_t *chapters; size_t n_chapters;
                 char *cover_path; } series_t;
typedef struct { series_t *series; size_t n_series; } library_t;

int library_scan(library_t *lib, const char *root);
void library_free(library_t *lib);
```

Rules: one directory under `root` = one series. Inside it, each `.cbz` = one chapter; each subdirectory containing images = one chapter. Cover is `cover.jpg`/`cover.png` if present, else page 0 of chapter 0, resolved lazily.

Scan cost matters — a 500-chapter library must not stat every page. Only open archives when a cover is actually needed.

**Run:** `make test_library` → **Expected: 5 run, 0 failed**

---

### Task 1.8: Image pipeline — failing test, then implement

**Files:** `tests/test_image.c`, `src/image.h`, `src/image.c`

This is where e-ink quality is won or lost.

**Pipeline:** decode (stb_image) → scale to fit (stb_image_resize2, Mitchell filter) → grayscale (Rec.709 luma) → dither to 16 levels (ordered 8x8 Bayer) → 8bpp buffer ready for `fbink_print_raw_data`.

**Why ordered and not Floyd–Steinberg:** error diffusion is serial and slow on a 1GHz ARM core, and its noise pattern ghosts badly across partial e-ink refreshes. Ordered dithering is ~10x faster, deterministic, and cache-friendly. Make it a compile-time switch so it can be A/B'd on device.

Tests:

```c
static void test_decode_png(void);            /* w,h,channels correct */
static void test_scale_preserves_aspect(void);/* 1000x500 into 600x800 -> 600x300 */
static void test_grayscale_is_8bpp(void);     /* out channels == 1 */
static void test_dither_only_16_levels(void); /* every byte % 17 == 0 */
static void test_decode_garbage_returns_null(void);
```

`test_dither_only_16_levels` is the one that catches a subtly wrong quantizer, which otherwise shows up as mud on the device three weeks later.

**Run:** `make test_image` → **Expected: 5 run, 0 failed**

**Commit.** At this point the entire core is tested and no Kindle has been touched since Task 0.5.

---

## Phase 2 — Device Layer

### Task 2.1: Framebuffer wrapper

**Files:** `src/fb.h`, `src/fb.c`

```c
int  fb_init(void);
void fb_shutdown(void);
int  fb_width(void);
int  fb_height(void);
void fb_clear(void);
void fb_blit_gray(const uint8_t *buf, int w, int h, int x, int y);
void fb_text(int x, int y, const char *s, int size);
void fb_refresh_partial(int x, int y, int w, int h);
void fb_refresh_full(void);
```

**Refresh policy — the thing that makes it feel like a real app:**

| Situation | Waveform | Flash |
|---|---|---|
| UI list scroll, selection move | `DU` (2-level, fastest) | no |
| Page turn in reader | `GC16` | no |
| Every 6th page turn | `GC16` | **yes** (clears accumulated ghosting) |
| Entering/leaving a screen | `GC16` | yes |

Hardcoding a full flash on every page turn makes the app feel slower than the stock reader. Never flashing makes pages progressively muddier. The counter-based compromise is what stock readers do.

**Verification:** on-device visual test — draw a page, turn 10 times, confirm flash on the 6th.

---

### Task 2.2: Input

**Files:** `src/input.h`, `src/input.c`

Read `/dev/input/event*`, auto-detecting which node is the touchscreen by probing with `EVIOCGBIT` for `ABS_MT_POSITION_X` rather than hardcoding `event1` — the node number differs across models and this is a cheap way to avoid a per-device port.

Normalize into:

```c
typedef enum { EV_NONE, EV_TAP, EV_SWIPE_L, EV_SWIPE_R,
               EV_SWIPE_U, EV_SWIPE_D, EV_KEY_BACK, EV_QUIT } ev_type_t;
typedef struct { ev_type_t type; int x, y; } ci_event_t;

int input_init(void);
int input_poll(ci_event_t *out, int timeout_ms);   /* 0 = timeout, 1 = event */
void input_shutdown(void);
```

Handle multitouch protocol B (`ABS_MT_SLOT`/`ABS_MT_TRACKING_ID`) — just track slot 0, ignore the rest. Swipe threshold: 80px over < 400ms. Tap: < 20px movement.

**Pitfall:** touch coordinates may be rotated or inverted relative to the framebuffer depending on model. Write `tools/evtest.sh` to dump raw values first and calibrate before guessing.

**Verification:** on-device — tap each screen corner, confirm printed coordinates match.

---

### Task 2.3: Widget helpers

**Files:** `src/widget.h`, `src/widget.c`

`widget_list()` (scrollable text list with selection), `widget_grid()` (thumbnail grid), `widget_button()`, `widget_toast()`. Built on `fb_*` only. Keep it boring — a 1-bit-aesthetic UI with clear borders reads far better on e-ink than anything with gradients or thin lines.

Design rules for e-ink: minimum 2px borders, minimum 18pt text, no anti-aliased thin lines (they vanish after dithering), high-contrast black-on-white only.

---

## Phase 3 — Screens

### Task 3.1: Screen state machine

**Files:** `src/app.h`, rewrite `src/main.c`

```c
typedef enum { SCREEN_LIBRARY, SCREEN_CHAPTERS, SCREEN_READER, SCREEN_EXIT } screen_t;
typedef struct {
    screen_t   screen;
    library_t  lib;
    progress_t prog;
    int sel_series, sel_chapter, page;
    archive_t  cur_archive;
    int        open_archive;
} app_t;
```

Main loop: `input_poll()` → dispatch to the current screen's handler → handler mutates state and redraws → repeat until `SCREEN_EXIT`. One redraw per event, never a redraw loop — e-ink has no frame rate and drawing when nothing changed just burns battery and ghosts the panel.

---

### Task 3.2: Library grid view

**Files:** `src/ui_library.c`

3x3 cover grid, title under each. Tap = open series. Swipe up/down = page through the grid. Back key = exit app.

Thumbnails are generated once into `cache/thumbs/<djb2-hash-of-path>.raw` as pre-dithered 8bpp buffers, so second launch is instant. Generating 9 thumbnails from cold takes a few seconds — show a "Building thumbnails…" toast with a counter rather than appearing frozen.

---

### Task 3.3: Chapter list view

**Files:** `src/ui_chapters.c`

Scrollable list. Show a `•` marker on chapters with saved progress and `✓` on finished ones — the small thing that makes a library feel like Tachiyomi rather than a file browser. Tap = open reader at the saved page. Back = library.

---

### Task 3.4: Reader

**Files:** `src/ui_reader.c`

- Tap right third / swipe left → next page
- Tap left third / swipe right → prev page
- Tap center → toggle the overlay bar (page N/M, chapter name, battery)
- Back → save progress, return to chapter list
- Past last page → advance to next chapter automatically; past the last chapter → return to the chapter list

Save progress on every page turn (atomic write is cheap and the Kindle sleeps unpredictably).

**Prefetch:** decode page N+1 in the background while N is displayed. On a single-core device do this between input polls, not with a thread — the complexity is not worth it and a blocked decode is more responsive than a contended one. Target: < 600ms per page turn on a PW3.

---

### Task 3.5: Zoom and pan

Two modes only. `fit-page` (default) and `fit-width` (panning vertically with swipes). Manga pages at 1072px wide render legibly at fit-page on a 300dpi screen; double-page spreads do not, which is what fit-width is for. Resist adding free-form pinch zoom — it is a large amount of work for a mode nobody uses on e-ink.

---

## Phase 4 — Scriptlet Packaging (was: KUAL — KUAL is obsolete on this jailbreak stack)

**Reality check performed 2026-09-18:** SpringBreak on this device uses KindleModding's `hdnext` stack, which replaced KUAL with **Scriptlets** managed by SH_Integration. A Scriptlet is any `.sh` file placed in `/mnt/us/documents/` — SH_Integration indexes it as a "book," it appears in the Kindle library, and tapping it runs the script. This is actually simpler than KUAL's XML+JSON manifest pair.

### Task 4.1: Write the launcher scriptlet

**Files:** `extension/ComicInKindle.sh` (this file is what ships — no config.xml, no menu.json)

Metadata is plain comment lines at the top of the file, read by SH_Integration:

```sh
#!/bin/sh
# Name: ComicInKindle
# Author: Halit
# DontUseFBInk

EXTDIR="/mnt/us/comicink"
BIN="$EXTDIR/bin/comicink"
LOG="$EXTDIR/comicink.log"

mkdir -p "$EXTDIR/library" "$EXTDIR/cache/thumbs" "$EXTDIR/bin"

# Stop the Kindle UI so it stops fighting us for the framebuffer
if [ -x /etc/init.d/framework ]; then
    /etc/init.d/framework stop >>"$LOG" 2>&1
else
    stop lab126_gui >>"$LOG" 2>&1
fi

[ -x /usr/bin/lipc-set-prop ] && lipc-set-prop com.lab126.powerd preventScreenSaver 1

"$BIN" "$@" >>"$LOG" 2>&1
RC=$?

[ -x /usr/bin/lipc-set-prop ] && lipc-set-prop com.lab126.powerd preventScreenSaver 0

if [ -x /etc/init.d/framework ]; then
    /etc/init.d/framework start >>"$LOG" 2>&1
else
    start lab126_gui >>"$LOG" 2>&1
fi
exit $RC
```

**Why `# DontUseFBInk` here:** SH_Integration's default behavior pipes the script's stdout/stderr to FBInk and displays it as text — useful for simple scriptlets, actively wrong for us, since our binary takes over the framebuffer directly and SH_Integration writing text over it mid-run would corrupt the display. Explicitly opt out.

**Non-negotiable, unchanged from the old plan:** the framework restart must run even if the binary segfaults — `$?` is captured and the restart is unconditional. Consider a `trap` on TERM/INT too, so killing the scriptlet from the terminal still restores the UI.

**Verification:** copy `ComicInKindle.sh` alone (with just an `echo hi` body, no binary yet) into `/mnt/us/documents/`, confirm it appears in the Kindle library as "ComicInKindle" by "Halit", tap it, confirm it runs.

---

### Task 4.2: Package target

**Files:** Makefile addition

```make
package: comicink
	rm -rf build/pkg
	mkdir -p build/pkg/comicink/bin
	cp comicink build/pkg/comicink/bin/
	chmod +x build/pkg/comicink/bin/comicink
	cp extension/ComicInKindle.sh build/pkg/documents_ComicInKindle.sh
	@echo "Copy build/pkg/comicink/ to /mnt/us/comicink/"
	@echo "Copy build/pkg/documents_ComicInKindle.sh to /mnt/us/documents/ComicInKindle.sh"
```

No zip-and-merge dance like KUAL needed — two folders, one file, straight USB drag-and-drop. Document this exactly in the README since it is the entire install story now.

**Install instruction for the README:**
1. Connect Kindle via USB (or `scp` over USBNetwork, see Phase 5)
2. Copy `build/pkg/comicink/` to the Kindle root as `/mnt/us/comicink/`
3. Copy `build/pkg/documents_ComicInKindle.sh` to `/mnt/us/documents/ComicInKindle.sh`
4. Eject, wait for the library to refresh, tap "ComicInKindle"

---

## Phase 5 — Dev Loop Tooling

### Task 5.1: Deploy script

**Files:** `tools/deploy.sh`

SSH access is via KOReader's built-in SSH server (port 2222, key auth only). The Kindle's IP is DHCP-leased and not fixed — check `;711` on-device each session and export `KINDLE_IP` accordingly. USBNetwork/usbnetlite were tried and abandoned for this device (MRPI, which they depend on, is not present on the `hdnext` stack) — WiFi + KOReader's SSH server is the actual working path.

```sh
#!/bin/sh
KINDLE_IP="${KINDLE_IP:?set KINDLE_IP to the current value from ;711 on-device}"
KEY="${HOME}/.ssh/kindle_ed25519"
make || exit 1
scp -i "$KEY" -P 2222 comicink root@"$KINDLE_IP":/mnt/us/comicink/bin/comicink
ssh -i "$KEY" -p 2222 root@"$KINDLE_IP" 'chmod +x /mnt/us/comicink/bin/comicink'
echo "deployed"
```

### Task 5.2: Screenshot script

**Files:** `tools/grab.sh`

```sh
#!/bin/sh
KINDLE_IP="${KINDLE_IP:-192.168.15.244}"
ssh root@"$KINDLE_IP" 'fbgrab /tmp/s.png 2>/dev/null || /mnt/us/fbink/fbdepth -d 8 && cat /dev/fb0' > /tmp/raw
scp root@"$KINDLE_IP":/tmp/s.png ./shot.png && echo "shot.png"
```

Wire this into the loop so every UI change is verified by a real screenshot, not by describing what it should look like.

### Task 5.3: Host preview build (optional but high leverage)

Compile the `ui_*.c` files against a `fb_sdl.c` that implements the same `fb.h` interface with SDL2, plus a keyboard-to-`ci_event_t` shim. Because `fb.h` is the only device coupling in the UI layer, this is roughly 150 lines and turns a 60-second deploy cycle into a 2-second one.

Pipe every host screenshot through the e-ink simulator before judging it:

```bash
magick shot.png -colorspace Gray -dither FloydSteinberg -colors 16 eink.png
```

A design that looks fine on an RGB monitor and terrible at 16 grays is the default outcome, not the exception.

---

## Phase 6 — Hardening

### Task 6.1: Crash safety
- `SIGSEGV`/`SIGBUS`/`SIGTERM` handler that restores the framebuffer and re-exec's the framework before dying
- Write the last-known state to the log before exiting

### Task 6.2: Memory ceiling
- Hard cap decode buffers; refuse pages above a configured megapixel limit with an on-screen message rather than getting OOM-killed
- Free the previous page before decoding the next — measure with `/proc/self/status` `VmHWM` on device, target under 60MB

### Task 6.3: Large library performance
- Test with 500 chapters across 20 series
- Target: library screen draws in under 2s cold, under 500ms warm
- If scanning is slow, persist the index to `cache/index.tsv` keyed on directory mtime

### Task 6.4: Battery
- Confirm the app is not spinning: `input_poll` must genuinely block, not poll in a busy loop
- Measure drain over a 1-hour idle session with the app open — anything above ~2%/hour means a busy loop

---

## Phase 7 — Release

- `README.md`: install steps, supported devices, the library folder layout, how to get out if something hangs
- Tag `v1.0`, attach `comicink-1.0.zip`
- Known-issues list, honestly written

---

## Phase 8 — Stretch: Online Sources (the real Tachiyomi part)

Deliberately deferred. When picking this up:
- Needs TLS — link mbedtls, not OpenSSL (size)
- Source "extensions" as declarative JSON scrapers (selector + URL template) rather than embedding a scripting engine
- Download to `library/` so the offline reader path is unchanged — the reader should never know a chapter came from the network
- Wifi on a Kindle is aggressively power-managed; expect to wrestle `lipc` to keep a connection alive

Scope this as its own plan when v1 is stable. Bolting it on early will destabilize the reader.

---

## Testing & Validation Summary

| Layer | How | When |
|---|---|---|
| progress, archive, library, image | `make test` — native, TDD | every task in Phase 1 |
| fb, input | on-device manual + screenshot | every task in Phase 2 |
| Screens | SDL host preview, then device screenshot | every task in Phase 3 |
| Packaging | fresh install on a clean device | Phase 4 |
| Performance | 500-chapter fixture library | Phase 6 |
| Safety | kill -9 mid-read; confirm UI returns | Phase 6 |

**Definition of done for v1.0:** install the zip on a factory-fresh jailbroken device, drop 3 CBZ files in, launch from KUAL, read 20 pages across two chapters, exit, relaunch, and land on the page you left — with no SSH and no manual recovery at any point.

---

## Risks & Tradeoffs

| Risk | Impact | Mitigation |
|---|---|---|
| Framework restart fails after a crash → bricked-feeling device | High | Unconditional restart in `launch.sh` + signal handlers; never test without SSH open |
| Wrong toolchain ABI → binary won't run, error is cryptic | Medium | Task 0.2 locks it first; `file` check after every build |
| Touch coordinate rotation differs per model | Medium | Runtime device detection via FBInk's state; calibration dump tool |
| Page decode too slow (> 1.5s) | Medium | Prefetch; downscale during decode not after; consider libjpeg-turbo scaled decode |
| E-ink ghosting makes it look broken | Medium | Refresh policy table in 2.1; verify by photographing the device, not by screenshot |
| Scope creep into online sources | High | Phase 8 is explicitly a separate plan |
| OTA firmware update re-locks the device mid-project | High | Disable updates on the dev device before starting |

---

## Open Questions (answer before continuing past Phase 0)

1. ~~Which Kindle model and firmware?~~ **Answered:** Paperwhite 11th gen, FW 5.19.2, SpringBreak v1.3.7. Still need the exact panel resolution confirmed on-device (Task 0.2).
2. ~~SSH over USBNet or wifi?~~ **USBNetwork is pre-installed** on this jailbreak — no setup, just `;un` in the search bar. Still needs the actual connect-and-verify pass (Task 0.5 prerequisite).
3. **CBR support in v1, or CBZ-only?** — leaning CBZ-only per the plan default; user has not yet confirmed.
4. **Is the SDL host preview worth building (Task 5.3)?** ~150 lines, pays for itself if Phase 3 takes more than two sessions. Recommend yes.
5. ~~KUAL classic or KUAL Next?~~ **Neither — KUAL is obsolete on this stack.** Distribution is a Scriptlet in `/mnt/us/documents/`. Phase 4 has been rewritten accordingly.
6. **Tachiyomi-style online sources** were raised as a requirement. This is scoped as Phase 8 (stretch, after the offline reader is solid) — see that section for why bolting network scraping on early is a mistake. Confirm you're fine building the offline reader first.
