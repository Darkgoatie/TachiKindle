#ifndef CI_FB_H
#define CI_FB_H
#include <stdint.h>

int  fb_init(void);
void fb_shutdown(void);
int  fb_width(void);
int  fb_height(void);
void fb_clear(void);

/* Blit an 8bpp grayscale buffer (w*h bytes, one byte per pixel, 0=black,
   255=white) at (x, y) in device (post-rotation) coordinates. */
void fb_blit_gray(const uint8_t *buf, int w, int h, int x, int y);

void fb_text(int x, int y, const char *s, int size);
/* Same as fb_text, but the caller supplies the background gray value
   already drawn at (x,y) (0=black..255=white) so glyph anti-aliasing
   blends against it correctly instead of assuming a white box --
   needed for text drawn over a selected/dark button fill. */
void fb_text_on_bg(int x, int y, const char *s, int size, uint8_t bg);

/* Refresh policy, see README/plan for the waveform table this implements. */
void fb_refresh_partial(int x, int y, int w, int h);
void fb_refresh_full(void);
/* Call every N page turns from the reader; internally decides whether
   this refresh should also flash based on an internal counter. */
void fb_refresh_page_turn(void);

#endif
