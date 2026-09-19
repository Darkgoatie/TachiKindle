/* Host-only stand-in for fb.c, used solely by tests/test_navigation.c
   so the ui_*_draw()/handle() logic can be exercised without real
   Kindle hardware or FBInk. Not linked into the actual tachikindle
   binary -- see Makefile's test_navigation rule. */
#include "fb.h"
#include <stdio.h>

int fb_init(void) { return 0; }
void fb_shutdown(void) {}
int fb_width(void) { return 1236; }
int fb_height(void) { return 1648; }
void fb_clear(void) {}
void fb_blit_gray(const uint8_t *buf, int w, int h, int x, int y) {
    (void)buf; (void)w; (void)h; (void)x; (void)y;
}
void fb_text(int x, int y, const char *s, int size) {
    (void)x; (void)y; (void)s; (void)size;
}
void fb_text_on_bg(int x, int y, const char *s, int size, uint8_t bg) {
    (void)x; (void)y; (void)s; (void)size; (void)bg;
}
void fb_refresh_partial(int x, int y, int w, int h) {
    (void)x; (void)y; (void)w; (void)h;
}
void fb_refresh_full(void) {}
void fb_refresh_page_turn(void) {}
