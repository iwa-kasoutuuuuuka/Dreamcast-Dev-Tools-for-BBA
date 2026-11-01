/* BMP encoder, kept free of KOS headers so it can be tested on the PC. */
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>

static void put16(uint8_t *p, uint32_t v) { p[0] = v; p[1] = v >> 8; }
static void put32(uint8_t *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }

size_t dcdev_bmp_encode(const uint8_t *rgb, int w, int h, uint8_t **out) {
    size_t stride, img, total;
    uint8_t *b;
    int x, y;

    *out = NULL;
    if (!rgb || w <= 0 || h <= 0)
        return 0;
    stride = ((size_t)w * 3 + 3) & ~(size_t)3;
    img = stride * h;
    total = 54 + img;
    b = (uint8_t *)malloc(total);
    if (!b)
        return 0;
    memset(b, 0, 54);
    b[0] = 'B'; b[1] = 'M';
    put32(b + 2, (uint32_t)total);
    put32(b + 10, 54);            /* pixel data offset */
    put32(b + 14, 40);            /* BITMAPINFOHEADER */
    put32(b + 18, (uint32_t)w);
    put32(b + 22, (uint32_t)h);   /* positive = bottom-up rows */
    put16(b + 26, 1);
    put16(b + 28, 24);
    put32(b + 34, (uint32_t)img);
    put32(b + 38, 2835);          /* 72 dpi */
    put32(b + 42, 2835);

    for (y = 0; y < h; y++) {
        const uint8_t *src = rgb + (size_t)(h - 1 - y) * w * 3;
        uint8_t *dst = b + 54 + (size_t)y * stride;
        for (x = 0; x < w; x++) {
            dst[x * 3 + 0] = src[x * 3 + 2];  /* B */
            dst[x * 3 + 1] = src[x * 3 + 1];  /* G */
            dst[x * 3 + 2] = src[x * 3 + 0];  /* R */
        }
        memset(dst + (size_t)w * 3, 0, stride - (size_t)w * 3);
    }
    *out = b;
    return total;
}
