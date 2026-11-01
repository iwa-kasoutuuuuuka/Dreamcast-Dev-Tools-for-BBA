/*
 * Minimal stand-in for KallistiOS, so lib/dcdev can be compiled and tested on the PC.
 * File access to "/pc/..." is redirected to a temp folder (mock_pc_root).
 */
#ifndef MOCK_KOS_H
#define MOCK_KOS_H

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <dirent.h>
#include <sys/stat.h>

/* ---- /pc/ redirection ---- */
extern char mock_pc_root[512];
extern int  mock_fs_calls;          /* fopen/opendir/stat calls that reached /pc/ */
FILE *mock_fopen(const char *path, const char *mode);
DIR  *mock_opendir(const char *path);
int   mock_stat(const char *path, struct stat *st);
#define fopen(p, m)   mock_fopen(p, m)
#define opendir(p)    mock_opendir(p)
#define stat(p, s)    mock_stat(p, s)

/* ---- timer ---- */
extern uint64_t mock_us;
static inline uint64_t timer_us_gettime64(void) { return mock_us; }
static inline uint64_t timer_ms_gettime64(void) { return mock_us / 1000; }

/* ---- video ---- */
typedef struct { int width, height, pm; } vid_mode_t;
extern vid_mode_t *vid_mode;
extern uint16_t *vram_s;
size_t vid_screen_shot_data(uint8_t **buffer);
#define DM_640x480 0
#define PM_RGB565  1
static inline void vid_set_mode(int dm, int pm) { (void)dm; (void)pm; }
static inline void vid_clear(int r, int g, int b) { (void)r; (void)g; (void)b; }
static inline void vid_waitvbl(void) {}
static inline void bfont_draw_str(void *b, int w, int o, const char *s) { (void)b; (void)w; (void)o; (void)s; }

/* ---- maple ---- */
#define MAPLE_FUNC_CONTROLLER 0x01000000
#define MAPLE_FUNC_MEMCARD    0x02000000
#define CONT_B     (1 << 1)
#define CONT_A     (1 << 2)
#define CONT_START (1 << 3)
#define CONT_Y     (1 << 9)
#define CONT_X     (1 << 10)
typedef struct { uint32_t functions; } maple_devinfo_t;
typedef struct { maple_devinfo_t info; int port, unit; } maple_device_t;
typedef struct { uint32_t buttons; int ltrig, rtrig; } cont_state_t;
extern cont_state_t mock_cont;
extern int mock_vmu_present;
maple_device_t *maple_enum_type(int n, uint32_t func);
maple_device_t *maple_enum_dev(int port, int unit);
void *maple_dev_status(maple_device_t *dev);

static inline const char *kos_get_banner(void) { return "mock KOS"; }

#endif
