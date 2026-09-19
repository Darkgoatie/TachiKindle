#include "fb.h"
#include "fbink.h"
#include "font.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* Font search order: our own bundled copy first (deployed alongside
   the binary via tools/deploy.sh so we don't depend on KOReader
   being installed), then KOReader's copy as a fallback for anyone
   who deletes the bundled file or breaks the install --
   /mnt/base-us/koreader/fonts/noto/NotoSans-Regular.ttf is confirmed
   present on-device (checked 2026-09-19) but not guaranteed to stay
   that way if the user uninstalls/updates KOReader. */
#define BUNDLED_FONT_PATH "/mnt/us/tachikindle/assets/NotoSans-Regular.ttf"
#define FALLBACK_FONT_PATH "/mnt/base-us/koreader/fonts/noto/NotoSans-Regular.ttf"

static int fbfd = -1;
static FBInkConfig cfg;
static FBInkState state;
static int page_turn_counter = 0;
static int font_ready = 0;

/* Flash every 6th page turn to clear accumulated ghosting; DU for quick
   list/selection redraws, GC16 for page turns otherwise. See the plan's
   refresh policy table (Phase 2, Task 2.1) for the reasoning. */
#define FLASH_EVERY_N_TURNS 6

int fb_init(void) {
    memset(&cfg, 0, sizeof(cfg));
    cfg.is_cleared = false;

    fbfd = fbink_open();
    if (fbfd < 0) return -1;
    if (fbink_init(fbfd, &cfg) < 0) return -1;

    fbink_get_state(&cfg, &state);
    page_turn_counter = 0;

    font_ready = (font_init(BUNDLED_FONT_PATH) == 0) ||
                 (font_init(FALLBACK_FONT_PATH) == 0);
    /* No font found: fb_text falls back to FBInk's built-in bitmap
       font (see below) rather than failing fb_init outright -- a
       missing TTF shouldn't take down the whole app. */

    return 0;
}

void fb_shutdown(void) {
    if (font_ready) font_shutdown();
    if (fbfd >= 0) {
        fbink_close(fbfd);
        fbfd = -1;
    }
}

int fb_width(void) {
    return (int)state.view_width;
}

int fb_height(void) {
    return (int)state.view_height;
}

void fb_clear(void) {
    FBInkConfig c = cfg;
    c.is_flashing = true;
    fbink_cls(fbfd, &c, NULL, false);
}

void fb_blit_gray(const uint8_t *buf, int w, int h, int x, int y) {
    FBInkConfig c = cfg;
    c.ignore_alpha = true;
    /* Y (8bpp grayscale, no alpha): len == w*h exactly, per fbink_print_raw_data's contract */
    fbink_print_raw_data(fbfd, buf, w, h, (size_t)w * (size_t)h,
                          (short int)x, (short int)y, &c);
}

void fb_text(int x, int y, const char *s, int size) {
    fb_text_on_bg(x, y, s, size, 0xFF);
}

void fb_text_on_bg(int x, int y, const char *s, int size, uint8_t bg) {
    if (!font_ready) {
        FBInkConfig c = cfg;
        c.fontmult = (unsigned char)size;
        c.is_centered = false;
        c.row = 0;
        c.col = 0;
        c.hoffset = (short int)x;
        c.voffset = (short int)y;
        fbink_print(fbfd, s, &c);
        return;
    }

    int size_px = size * 16;
    int w = font_measure_width(s, size_px) + 4;
    int h = size_px + (size_px / 2);
    if (w <= 0 || h <= 0) return;

    uint8_t *scratch = malloc((size_t)w * (size_t)h);
    if (!scratch) return;
    /* Match whatever's already drawn at this spot (a button's fill
       color, typically) so the glyph blend in font_draw darkens
       against the real background instead of stamping a plain white
       box over dark/selected buttons. */
    memset(scratch, bg, (size_t)w * (size_t)h);

    font_draw(scratch, w, h, 2, 0, s, size_px);
    fb_blit_gray(scratch, w, h, x, y);
    free(scratch);
}

void fb_refresh_partial(int x, int y, int w, int h) {
    FBInkConfig c = cfg;
    c.wfm_mode = WFM_DU;
    c.is_flashing = false;
    fbink_refresh(fbfd, (uint32_t)y, (uint32_t)x, (uint32_t)w, (uint32_t)h, &c);
}

void fb_refresh_full(void) {
    FBInkConfig c = cfg;
    c.wfm_mode = WFM_GC16;
    c.is_flashing = true;
    fbink_refresh(fbfd, 0, 0, (uint32_t)fb_width(), (uint32_t)fb_height(), &c);
}

void fb_refresh_page_turn(void) {
    page_turn_counter++;
    FBInkConfig c = cfg;
    c.wfm_mode = WFM_GC16;
    c.is_flashing = (page_turn_counter % FLASH_EVERY_N_TURNS == 0);
    fbink_refresh(fbfd, 0, 0, (uint32_t)fb_width(), (uint32_t)fb_height(), &c);
}
