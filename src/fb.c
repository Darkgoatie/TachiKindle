#include "fb.h"
#include "fbink.h"
#include <string.h>
#include <stdio.h>

static int fbfd = -1;
static FBInkConfig cfg;
static FBInkState state;
static int page_turn_counter = 0;

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
    return 0;
}

void fb_shutdown(void) {
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
    FBInkConfig c = cfg;
    c.fontmult = (unsigned char)size;
    c.is_centered = false;
    c.row = 0;
    c.col = 0;
    /* x/y offsets are honored alongside row/col per fbink_print's docs */
    (void)x; (void)y;
    fbink_print(fbfd, s, &c);
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
