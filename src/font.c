/* font.c -- see font.h */
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"
#include "font.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static unsigned char *g_ttf_buf = NULL;
static stbtt_fontinfo g_font;
static int g_loaded = 0;

int font_init(const char *ttf_path) {
    FILE *f = fopen(ttf_path, "rb");
    if (!f) return -1;

    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0) { fclose(f); return -1; }

    unsigned char *buf = malloc((size_t)sz);
    if (!buf) { fclose(f); return -1; }
    size_t rd = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    if (rd != (size_t)sz) { free(buf); return -1; }

    if (!stbtt_InitFont(&g_font, buf, stbtt_GetFontOffsetForIndex(buf, 0))) {
        free(buf);
        return -1;
    }

    g_ttf_buf = buf;
    g_loaded = 1;
    return 0;
}

void font_shutdown(void) {
    free(g_ttf_buf);
    g_ttf_buf = NULL;
    g_loaded = 0;
}

int font_measure_width(const char *s, int size_px) {
    if (!g_loaded || !s) return 0;

    float scale = stbtt_ScaleForPixelHeight(&g_font, (float)size_px);
    int width = 0;
    int codepoint;
    const unsigned char *p = (const unsigned char *)s;

    while ((codepoint = *p) != 0) {
        int advance, lsb;
        stbtt_GetCodepointHMetrics(&g_font, codepoint, &advance, &lsb);
        width += (int)((float)advance * scale);

        if (p[1]) {
            width += (int)(stbtt_GetCodepointKernAdvance(&g_font, codepoint, p[1]) * scale);
        }
        p++;
    }
    return width;
}

/* Alpha-blends one glyph's coverage bitmap into dst at (px, py),
   clipping against dst's bounds. coverage[i] is 0-255 opacity;
   0=background shows through unchanged, 255=full black ink. Caller
   guarantees dst is 8bpp grayscale (0=black, 255=white) matching
   fb_blit_gray's contract. */
static void blend_glyph(uint8_t *dst, int dst_w, int dst_h,
                         const unsigned char *coverage, int gw, int gh,
                         int px, int py) {
    for (int gy = 0; gy < gh; gy++) {
        int dy = py + gy;
        if (dy < 0 || dy >= dst_h) continue;
        for (int gx = 0; gx < gw; gx++) {
            int dx = px + gx;
            if (dx < 0 || dx >= dst_w) continue;

            unsigned char a = coverage[gy * gw + gx];
            if (a == 0) continue;

            uint8_t *pixel = &dst[dy * dst_w + dx];
            /* ink is black (0); blend toward black by `a`/255 */
            int bg = *pixel;
            int blended = bg - (bg * a) / 255;
            *pixel = (uint8_t)(blended < 0 ? 0 : blended);
        }
    }
}

int font_draw(uint8_t *dst, int dst_w, int dst_h,
               int x, int y, const char *s, int size_px) {
    if (!g_loaded || !s || !dst) return 0;

    float scale = stbtt_ScaleForPixelHeight(&g_font, (float)size_px);
    int ascent, descent, line_gap;
    stbtt_GetFontVMetrics(&g_font, &ascent, &descent, &line_gap);
    int baseline = (int)((float)ascent * scale);

    int pen_x = x;
    const unsigned char *p = (const unsigned char *)s;

    while (*p) {
        int codepoint = *p;
        int advance, lsb;
        stbtt_GetCodepointHMetrics(&g_font, codepoint, &advance, &lsb);

        int gw, gh, gxoff, gyoff;
        unsigned char *bitmap = stbtt_GetCodepointBitmap(
            &g_font, scale, scale, codepoint, &gw, &gh, &gxoff, &gyoff);

        if (bitmap) {
            blend_glyph(dst, dst_w, dst_h, bitmap, gw, gh,
                        pen_x + gxoff, y + baseline + gyoff);
            stbtt_FreeBitmap(bitmap, NULL);
        }

        pen_x += (int)((float)advance * scale);
        if (p[1]) {
            pen_x += (int)(stbtt_GetCodepointKernAdvance(&g_font, codepoint, p[1]) * scale);
        }
        p++;
    }

    return pen_x - x;
}
