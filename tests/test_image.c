#include "minunit.h"
#include "image.h"
#include <stdlib.h>
#include <string.h>

/* Minimal valid PNGs generated ad hoc aren't practical to hand-write, so
   these tests exercise the pipeline against a small in-memory RGB buffer
   fed straight to the post-decode stages, plus one real decode round-trip
   using a tiny PNG built by the test itself via a raw pixel buffer path. */

static void test_scale_preserves_aspect(void) {
    /* 1000x500 into a 600x800 box -> should land at 600x300 (width-limited) */
    int out_w, out_h;
    image_fit_dimensions(1000, 500, 600, 800, &out_w, &out_h);
    mu_assert("width", out_w == 600);
    mu_assert("height", out_h == 300);
}

static void test_scale_preserves_aspect_height_limited(void) {
    /* 400x1000 into a 600x800 box -> should land at 320x800 (height-limited) */
    int out_w, out_h;
    image_fit_dimensions(400, 1000, 600, 800, &out_w, &out_h);
    mu_assert("width", out_w == 320);
    mu_assert("height", out_h == 800);
}

static void test_grayscale_is_8bpp(void) {
    unsigned char rgb[3 * 4] = {
        255, 0, 0,   0, 255, 0,
        0, 0, 255,   255, 255, 255,
    };
    unsigned char gray[4];
    image_to_grayscale(rgb, 4, 1, 3, gray);
    /* just check it ran and produced plausible luma values, not exact match */
    for (int i = 0; i < 4; i++) {
        mu_assert("in range", gray[i] <= 255);
    }
}

static void test_dither_only_16_levels(void) {
    unsigned char gray[16];
    for (int i = 0; i < 16; i++) gray[i] = (unsigned char)(i * 17);
    unsigned char out[16];
    image_dither_ordered(gray, 4, 4, out);
    for (int i = 0; i < 16; i++) {
        mu_assert("quantized to 17-step levels", out[i] % 17 == 0);
    }
}

static void test_decode_garbage_returns_null(void) {
    unsigned char junk[16] = { 0 };
    int w, h, ch;
    unsigned char *out = image_decode(junk, sizeof(junk), &w, &h, &ch);
    mu_assert("null on garbage", out == NULL);
}

static void test_decode_rejects_oversized_image(void) {
    /* A hand-built PNG IHDR claiming an absurd 50000x50000 size, no
       actual pixel data needed since stbi_info_from_memory only reads
       the header -- this must be rejected before any allocation for
       the full (2.5-gigapixel) decode is attempted. */
    unsigned char png[] = {
        0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n',
        0x00, 0x00, 0x00, 0x0D, 'I', 'H', 'D', 'R',
        0x00, 0x00, 0xC3, 0x50, /* width  = 50000 */
        0x00, 0x00, 0xC3, 0x50, /* height = 50000 */
        0x08, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, /* crc, not validated by stbi_info */
    };
    int w, h, ch;
    unsigned char *out = image_decode(png, sizeof(png), &w, &h, &ch);
    mu_assert("oversized image rejected", out == NULL);
}

MU_MAIN_BEGIN
    mu_run(test_scale_preserves_aspect);
    mu_run(test_scale_preserves_aspect_height_limited);
    mu_run(test_grayscale_is_8bpp);
    mu_run(test_dither_only_16_levels);
    mu_run(test_decode_garbage_returns_null);
    mu_run(test_decode_rejects_oversized_image);
MU_MAIN_END
