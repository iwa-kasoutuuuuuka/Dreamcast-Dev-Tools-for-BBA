/* BMP encoder, kept free of KOS headers so it can be tested on the PC. */
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>
#include "dcdev_bmp.h"

static void put16(uint8_t *p, uint32_t v) { p[0] = v; p[1] = v >> 8; }
static void put32(uint8_t *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }

size_t dcdev_bmp_stride(int w) {
    return ((size_t)w * 3 + 3) & ~(size_t)3;
}

void dcdev_bmp_header(uint8_t hdr[DCDEV_BMP_HEADER], int w, int h) {
    size_t img = dcdev_bmp_stride(w) * h;
    memset(hdr, 0, DCDEV_BMP_HEADER);
    hdr[0] = 'B'; hdr[1] = 'M';
    put32(hdr + 2, (uint32_t)(DCDEV_BMP_HEADER + img));
    put32(hdr + 10, DCDEV_BMP_HEADER);  /* pixel data offset */
    put32(hdr + 14, 40);                /* BITMAPINFOHEADER */
    put32(hdr + 18, (uint32_t)w);
    put32(hdr + 22, (uint32_t)h);       /* positive = bottom-up rows */
    put16(hdr + 26, 1);
    put16(hdr + 28, 24);
    put32(hdr + 34, (uint32_t)img);
    put32(hdr + 38, 2835);              /* 72 dpi */
    put32(hdr + 42, 2835);
}

void dcdev_bmp_row(uint8_t *dst, const uint8_t *rgb_row, int w) {
    int x;
    for (x = 0; x < w; x++) {
        dst[x * 3 + 0] = rgb_row[x * 3 + 2];  /* B */
        dst[x * 3 + 1] = rgb_row[x * 3 + 1];  /* G */
        dst[x * 3 + 2] = rgb_row[x * 3 + 0];  /* R */
    }
    memset(dst + (size_t)w * 3, 0, dcdev_bmp_stride(w) - (size_t)w * 3);
}

size_t dcdev_bmp_encode(const uint8_t *rgb, int w, int h, uint8_t **out) {
    size_t stride, total;
    uint8_t *b;
    int y;

    *out = NULL;
    if (!rgb || w <= 0 || h <= 0)
        return 0;
    stride = dcdev_bmp_stride(w);
    total = DCDEV_BMP_HEADER + stride * h;
    b = (uint8_t *)malloc(total);
    if (!b)
        return 0;
    dcdev_bmp_header(b, w, h);
    for (y = 0; y < h; y++)   /* bottom-up: first stored row = last image row */
        dcdev_bmp_row(b + DCDEV_BMP_HEADER + (size_t)y * stride, rgb + (size_t)(h - 1 - y) * w * 3, w);
    *out = b;
    return total;
}
