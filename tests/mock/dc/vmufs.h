#ifndef MOCK_VMUFS_H
#define MOCK_VMUFS_H
#include <stdint.h>
#include "../kos.h"

typedef struct {
    uint8_t  filetype;      /* 0x33 data, 0xcc game */
    uint8_t  copyprotect;
    uint16_t firstblk;
    char     filename[12];  /* no terminator, padded */
    uint8_t  time[8];
    uint16_t filesize;      /* blocks */
    uint16_t hdroff;
    uint8_t  pad[12];
} vmu_dir_t;

#define VMUFS_OVERWRITE 1

/* mock VMU contents */
#define MOCK_VMU_MAX 8
typedef struct { vmu_dir_t dir; uint8_t *data; int size; } mock_vmu_file_t;
extern mock_vmu_file_t mock_vmu[MOCK_VMU_MAX];
extern int mock_vmu_count;
extern int mock_vmu_free_blocks;

int vmufs_readdir(maple_device_t *dev, vmu_dir_t **outbuf, int *outcnt);
int vmufs_read_dirent(maple_device_t *dev, vmu_dir_t *dirent, void **outbuf, int *outsize);
int vmufs_write(maple_device_t *dev, const char *fn, void *inbuf, int insize, int flags);
#endif
