#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#include "image.h"
#include <stdlib.h>

/* Refuse to decode/allocate for absurdly large source images. A
   megapixel ceiling protects the ~15-32MB total RAM budget on these
   devices far better than discovering the hard way that a stray
   20000x20000 scan in someone's library OOM-kills the whole app. 40MP
   is generous headroom above any real manga scan (a 4800dpi A4 page is
   still well under 10MP) while catching pathological inputs. */
#define IMAGE_MAX_MEGAPIXELS 40
#define IMAGE_MAX_PIXELS ((long long)IMAGE_MAX_MEGAPIXELS * 1000000LL)

unsigned char *image_decode(const unsigned char *buf, size_t size,
                             int *out_w, int *out_h, int *out_channels) {
    int w, h, ch;
    /* stb_image can report dimensions without a full decode via a
       lightweight header parse; use that to reject oversized images
       before committing to the actual (much more expensive) decode. */
    if (!stbi_info_from_memory(buf, (int)size, &w, &h, &ch)) return NULL;
    if ((long long)w * (long long)h > IMAGE_MAX_PIXELS) return NULL;

    unsigned char *pixels = stbi_load_from_memory(buf, (int)size, &w, &h, &ch, 0);
    if (!pixels) return NULL;
    *out_w = w;
    *out_h = h;
    *out_channels = ch;
    return pixels;
}

void image_fit_dimensions(int src_w, int src_h, int box_w, int box_h,
                           int *out_w, int *out_h) {
    /* Compare src_w/src_h against box_w/box_h without floating point:
       cross-multiply to see whether width or height is the binding
       constraint, then scale off that constraint. */
    long long src_w_ll = src_w, src_h_ll = src_h, box_w_ll = box_w, box_h_ll = box_h;

    if (src_w_ll * box_h_ll > box_w_ll * src_h_ll) {
        /* width-limited */
        *out_w = box_w;
        *out_h = (int)((src_h_ll * box_w_ll) / src_w_ll);
    } else {
        /* height-limited */
        *out_h = box_h;
        *out_w = (int)((src_w_ll * box_h_ll) / src_h_ll);
    }
}

void image_to_grayscale(const unsigned char *rgb, int w, int h, int channels,
                         unsigned char *out_gray) {
    int n = w * h;
    for (int i = 0; i < n; i++) {
        const unsigned char *px = rgb + (size_t)i * channels;
        if (channels == 1) {
            out_gray[i] = px[0];
            continue;
        }
        /* Rec.709 luma */
        int r = px[0], g = px[1], b = px[2];
        int y = (int)(0.2126 * r + 0.7152 * g + 0.0722 * b);
        if (y < 0) y = 0;
        if (y > 255) y = 255;
        out_gray[i] = (unsigned char)y;
    }
}

/* 4x4 Bayer threshold matrix, scaled to 0..255 */
static const int BAYER4[4][4] = {
    {  0, 128,  32, 160 },
    { 192,  64, 224,  96 },
    {  48, 176,  16, 144 },
    { 240, 112, 208,  80 },
};

void image_dither_ordered(const unsigned char *gray, int w, int h,
                           unsigned char *out) {
    const int levels = 16;
    const int step = 255 / (levels - 1); /* 17 */

    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            int idx = y * w + x;
            int v = gray[idx];

            /* Bias the value by the threshold map before quantizing,
               spreading rounding error across the 4x4 tile instead of
               truncating every pixel identically. */
            int threshold = BAYER4[y % 4][x % 4] - 128;
            int biased = v + threshold / (256 / step + 1);
            if (biased < 0) biased = 0;
            if (biased > 255) biased = 255;

            int level = (biased + step / 2) / step;
            if (level > levels - 1) level = levels - 1;
            out[idx] = (unsigned char)(level * step);
        }
    }
}
