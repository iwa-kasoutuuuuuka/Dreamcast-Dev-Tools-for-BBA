/* Internal BMP helpers shared by dcdev_bmp.c and dcdev_screenshot.c. */
#ifndef DCDEV_BMP_H
#define DCDEV_BMP_H
#include <stdint.h>
#include <stddef.h>

#define DCDEV_BMP_HEADER 54

size_t dcdev_bmp_stride(int w);                                  /* bytes per stored row */
void   dcdev_bmp_header(uint8_t hdr[DCDEV_BMP_HEADER], int w, int h);
void   dcdev_bmp_row(uint8_t *dst, const uint8_t *rgb_row, int w);  /* RGB -> BGR + padding */

#endif
