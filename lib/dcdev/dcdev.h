/*
 * dcdev - small developer helpers for KallistiOS programs run over the BBA
 * (dcload-ip / dc-tool-ip). Everything goes through /pc/, so it only works
 * while the program was started by dc-tool-ip; on a burned disc every call
 * is a cheap no-op that returns an error.
 *
 *   dcdev_init("/pc/work/mygame");   folder on the PC that holds these subfolders:
 *       screenshots/  logs/  vmu/  assets/  prof/
 *   (dcload cannot create folders, so create them on the PC first;
 *    scripts/dc_prepare_host.ps1 does it.)
 *
 * Features
 *   dcdev_screenshot()        current framebuffer -> screenshots/shot_0001.bmp
 *   dcdev_log()               printf to the console + append to logs/dc_log.txt
 *   dcdev_vmu_backup/restore  VMU data files <-> vmu/<port><unit>/ (e.g. vmu/a1/)
 *   dcdev_asset_load()        load assets/<name> from the PC (falls back to /cd/, /rd/)
 *   dcdev_asset_changed()     has assets/<name> changed on the PC? (hot reload)
 *   dcdev_prof_*()            per-section timings -> prof/prof.csv
 *   dcdev_poll()              button combos: hold L+R triggers, then
 *                               A = screenshot, X = VMU backup, Y = VMU restore,
 *                               B = print the profile now
 */
#ifndef DCDEV_H
#define DCDEV_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- core ---- */
/* host_dir: a /pc/ path, e.g. "/pc/work/mygame". Returns 1 if /pc/ is usable. */
int  dcdev_init(const char *host_dir);
int  dcdev_available(void);
/* Builds "<host_dir>/<sub>" into out. Returns out. */
const char *dcdev_path(const char *sub, char *out, size_t outlen);

/* ---- screenshot ---- */
/* name == NULL: auto-numbered screenshots/shot_NNNN.bmp. Returns 0 on success. */
int  dcdev_screenshot(const char *name);
/* Encodes a 24-bit RGB buffer (top row first) as a BMP in memory (malloc'd).
   Exposed for tests; returns the size or 0. */
size_t dcdev_bmp_encode(const uint8_t *rgb, int w, int h, uint8_t **out);

/* ---- log ---- */
/* printf to the dc-tool console and append the same line to logs/dc_log.txt
   (with a timestamp in ms since boot). */
void dcdev_log(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
void dcdev_log_close(void);

/* ---- VMU ---- */
/* port 0..3 (A..D), unit 1..2. Data files only (the VMU game slot is skipped).
   Return the number of files copied, or -1. */
int  dcdev_vmu_backup(int port, int unit);
int  dcdev_vmu_restore(int port, int unit);

/* ---- assets ---- */
/* Loads assets/<name> from the PC, else /cd/<name>, else /rd/<name>.
   Returns a malloc'd buffer (free() it) and sets *size; NULL if not found. */
void *dcdev_asset_load(const char *name, size_t *size);
/* 1 if assets/<name> on the PC changed since the last call for that name.
   Checks at most every 500 ms per name, so it is fine to call every frame.
   Tracks up to 32 names. */
int  dcdev_asset_changed(const char *name);

/* ---- profiler ---- */
/* Wrap code sections; name must be a string literal (compared by pointer). */
void dcdev_prof_begin(const char *name);
void dcdev_prof_end(const char *name);
/* Call once per frame. Every `interval` frames (default 60) appends
   avg/max per section to prof/prof.csv. */
void dcdev_prof_frame(void);
void dcdev_prof_set_interval(int frames);
void dcdev_prof_print(void);

/* ---- button combos ---- */
/* Call once per frame. Handles the L+R combos above on the first controller found
   (normally port A). A combo fires once when the button is pressed while both
   triggers are held. Returns the button that fired (CONT_A etc.) or 0. */
uint32_t dcdev_poll(void);

#ifdef __cplusplus
}
#endif
#endif
