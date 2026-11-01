/* Screenshot of the framebuffer -> BMP on the PC. */
#include <kos.h>
#include <stdio.h>
#include <stdlib.h>
#include "dcdev.h"
#include "dcdev_bmp.h"

static int g_shot_no;   /* next number to try; 0 = not scanned yet */

static int file_exists(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f)
        return 0;
    fclose(f);
    return 1;
}

int dcdev_screenshot(const char *name) {
    char rel[96], path[384];
    uint8_t hdr[DCDEV_BMP_HEADER];
    uint8_t *rgb = NULL, *row = NULL;
    int w, h, y, ok = 1;
    FILE *f;
    uint64_t t0 = timer_ms_gettime64();

    if (!dcdev_available())
        return -1;

    if (name) {
        snprintf(rel, sizeof(rel), "screenshots/%s", name);
    } else {
        /* continue after the highest existing number (one scan per run) */
        if (g_shot_no == 0) {
            g_shot_no = 1;
            for (;;) {
                snprintf(rel, sizeof(rel), "screenshots/shot_%04d.bmp", g_shot_no);
                if (!file_exists(dcdev_path(rel, path, sizeof(path))))
                    break;
                g_shot_no++;
            }
        }
        snprintf(rel, sizeof(rel), "screenshots/shot_%04d.bmp", g_shot_no);
    }
    dcdev_path(rel, path, sizeof(path));

    /* Grab the frame first, so the picture is taken when asked, not after the file opens. */
    if (!vid_screen_shot_data(&rgb) || !rgb) {
        printf("[dcdev] screenshot: could not read the framebuffer\n");
        return -1;
    }
    w = vid_mode->width;
    h = vid_mode->height;

    f = fopen(path, "wb");
    if (!f) {
        printf("[dcdev] screenshot: cannot create %s (does the screenshots folder exist?)\n", path);
        free(rgb);
        return -1;
    }
    if (!name)
        g_shot_no++;

    /* Write row by row: only one extra row in memory instead of a second full image. */
    row = (uint8_t *)malloc(dcdev_bmp_stride(w));
    dcdev_bmp_header(hdr, w, h);
    if (!row || fwrite(hdr, 1, sizeof(hdr), f) != sizeof(hdr))
        ok = 0;
    for (y = h - 1; ok && y >= 0; y--) {
        dcdev_bmp_row(row, rgb + (size_t)y * w * 3, w);
        if (fwrite(row, 1, dcdev_bmp_stride(w), f) != dcdev_bmp_stride(w))
            ok = 0;
    }
    fclose(f);
    free(row);
    free(rgb);
    if (!ok) {
        printf("[dcdev] screenshot: writing %s failed\n", path);
        return -1;
    }
    printf("[dcdev] screenshot %s (%dx%d, %u ms)\n", path, w, h,
           (unsigned)(timer_ms_gettime64() - t0));
    return 0;
}
