/* font.h -- real anti-aliased TrueType text rendering via stb_truetype,
   replacing FBInk's built-in bitmap font. Renders into an 8bpp
   grayscale buffer compatible with fb_blit_gray (0=black, 255=white),
   alpha-blending each glyph's coverage against a caller-supplied
   background so text can sit on top of already-drawn UI (buttons,
   list rows) without a separate compositing pass. */
#ifndef TK_FONT_H
#define TK_FONT_H

#include <stddef.h>
#include <stdint.h>

/* Loads a TTF file into memory and initializes stb_truetype for it.
   Returns 0 on success. The font stays loaded for the process
   lifetime (call font_shutdown() to free it, mainly for tests). */
int font_init(const char *ttf_path);
void font_shutdown(void);

/* Measures the pixel width `s` would occupy at `size_px`, without
   drawing anything -- used for centering / hit-test layout. */
int font_measure_width(const char *s, int size_px);

/* Renders `s` at `size_px` into `dst` (an existing w*h 8bpp grayscale
   buffer, 0=black/255=white) with its top-left baseline-adjusted
   origin at (x, y) within dst. Glyphs are alpha-blended against
   whatever is already in `dst` at that position, so draw the
   background/border first, then call this. Returns the pixel width
   actually drawn (same as font_measure_width would report). */
int font_draw(uint8_t *dst, int dst_w, int dst_h,
               int x, int y, const char *s, int size_px);

#endif
