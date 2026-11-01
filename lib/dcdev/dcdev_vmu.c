/* VMU data files <-> PC folder vmu/<port letter><unit>/ (e.g. vmu/a1/). */
#include <kos.h>
#include <dc/vmufs.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include "dcdev.h"

static maple_device_t *vmu_dev(int port, int unit, char *tag) {
    maple_device_t *dev;
    tag[0] = 'a' + port;
    tag[1] = '0' + unit;
    tag[2] = 0;
    dev = maple_enum_dev(port, unit);
    if (!dev || !(dev->info.functions & MAPLE_FUNC_MEMCARD)) {
        printf("[dcdev] vmu: no memory card in %c%d\n", 'A' + port, unit);
        return NULL;
    }
    return dev;
}

int dcdev_vmu_backup(int port, int unit) {
    char tag[3], rel[64], path[384], fname[13];
    maple_device_t *dev;
    vmu_dir_t *dir = NULL;
    int cnt = 0, i, copied = 0;

    if (!dcdev_available() || !(dev = vmu_dev(port, unit, tag)))
        return -1;
    if (vmufs_readdir(dev, &dir, &cnt) < 0) {
        printf("[dcdev] vmu: cannot read the directory of %s\n", tag);
        return -1;
    }
    for (i = 0; i < cnt; i++) {
        void *buf = NULL;
        int size = 0;
        FILE *f;

        if (dir[i].filetype != 0x33)          /* data files only (0xcc = VMU game) */
            continue;
        memcpy(fname, dir[i].filename, 12);
        fname[12] = 0;
        for (int k = 11; k >= 0 && (fname[k] == ' ' || fname[k] == 0); k--)
            fname[k] = 0;
        if (vmufs_read_dirent(dev, &dir[i], &buf, &size) < 0 || !buf)
            continue;
        snprintf(rel, sizeof(rel), "vmu/%s/%s", tag, fname);
        f = fopen(dcdev_path(rel, path, sizeof(path)), "wb");
        if (f) {
            fwrite(buf, 1, size, f);
            fclose(f);
            copied++;
            printf("[dcdev] vmu backup %s (%d bytes)\n", path, size);
        } else {
            printf("[dcdev] vmu: cannot create %s (does vmu/%s exist?)\n", path, tag);
        }
        free(buf);
    }
    free(dir);
    printf("[dcdev] vmu backup %s: %d file(s)\n", tag, copied);
    return copied;
}

int dcdev_vmu_restore(int port, int unit) {
    char tag[3], rel[64], dirpath[384], path[640];
    maple_device_t *dev;
    DIR *d;
    struct dirent *de;
    int copied = 0;

    if (!dcdev_available() || !(dev = vmu_dev(port, unit, tag)))
        return -1;
    snprintf(rel, sizeof(rel), "vmu/%s", tag);
    d = opendir(dcdev_path(rel, dirpath, sizeof(dirpath)));
    if (!d) {
        printf("[dcdev] vmu: cannot open %s\n", dirpath);
        return -1;
    }
    while ((de = readdir(d)) != NULL) {
        FILE *f;
        long size;
        void *buf;
        size_t len = strlen(de->d_name);

        if (de->d_name[0] == '.' || len == 0 || len > 12)
            continue;
        snprintf(path, sizeof(path), "%s/%s", dirpath, de->d_name);
        f = fopen(path, "rb");
        if (!f)
            continue;
        fseek(f, 0, SEEK_END);
        size = ftell(f);
        fseek(f, 0, SEEK_SET);
        if (size <= 0 || size % 512 != 0) {      /* VMU files are whole 512-byte blocks */
            fclose(f);
            continue;
        }
        buf = malloc(size);
        if (buf && fread(buf, 1, size, f) == (size_t)size) {
            if (vmufs_write(dev, de->d_name, buf, (int)size, VMUFS_OVERWRITE) == 0) {
                copied++;
                printf("[dcdev] vmu restore %s -> %s\n", path, tag);
            } else {
                printf("[dcdev] vmu: writing %s failed (full card?)\n", de->d_name);
            }
        }
        free(buf);
        fclose(f);
    }
    closedir(d);
    printf("[dcdev] vmu restore %s: %d file(s)\n", tag, copied);
    return copied;
}
