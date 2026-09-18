#ifndef CI_IMAGE_H
#define CI_IMAGE_H
#include <stddef.h>

/* Decodes an in-memory image file (JPEG/PNG/etc, whatever stb_image
   supports). Returns a malloc'd RGB(A) buffer the caller frees, or NULL
   on failure. out_channels is whatever the source image actually has
   (stb_image is asked for its native channel count). */
unsigned char *image_decode(const unsigned char *buf, size_t size,
                             int *out_w, int *out_h, int *out_channels);

/* Computes the largest w x h that fits inside box_w x box_h while
   preserving the source aspect ratio. */
void image_fit_dimensions(int src_w, int src_h, int box_w, int box_h,
                           int *out_w, int *out_h);

/* Rec.709 luma. `channels` is the source channel count (3=RGB, 4=RGBA;
   alpha is ignored). Writes w*h bytes into `out_gray`. */
void image_to_grayscale(const unsigned char *rgb, int w, int h, int channels,
                         unsigned char *out_gray);

/* Ordered (Bayer 4x4) dither down to 16 gray levels (steps of 17,
   i.e. 0,17,34,...,255). Writes w*h bytes into `out`. */
void image_dither_ordered(const unsigned char *gray, int w, int h,
                           unsigned char *out);

#endif
