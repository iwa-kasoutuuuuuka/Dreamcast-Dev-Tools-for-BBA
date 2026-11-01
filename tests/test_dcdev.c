/*
 * PC-side tests for lib/dcdev, using the mock KallistiOS in tests/mock.
 * Build and run with tests/run_tests.ps1.
 */
#include "mock/kos.h"
#include "mock/dc/fs_dcload.h"
#include "mock/dc/vmufs.h"
#include "../lib/dcdev/dcdev.h"
#undef fopen
#undef opendir
#undef stat
#include <stdlib.h>
#include <string.h>
#include <direct.h>

/* ================= mock state ================= */
char mock_pc_root[512];
int  mock_fs_calls;
uint64_t mock_us = 1000000;
int dcload_type = DCLOAD_TYPE_IP;
static vid_mode_t mode = { 4, 2, PM_RGB565 };
vid_mode_t *vid_mode = &mode;
uint16_t *vram_s;
cont_state_t mock_cont;
int mock_vmu_present = 1;
mock_vmu_file_t mock_vmu[MOCK_VMU_MAX];
int mock_vmu_count;
int mock_vmu_free_blocks = 200;
static char written_names[8][16];
static int  written_sizes[8];
static int  written_count;

static const char *map(const char *path, char *buf, size_t n) {
    if (strncmp(path, "/pc/", 4) != 0)
        return NULL;
    mock_fs_calls++;
    snprintf(buf, n, "%s%s", mock_pc_root, path + 3);
    return buf;
}
FILE *mock_fopen(const char *path, const char *mode) {
    char b[1024];
    const char *p = map(path, b, sizeof(b));
    return p ? fopen(p, mode) : NULL;           /* /cd/ and /rd/: no disc in the mock */
}
DIR *mock_opendir(const char *path) {
    char b[1024];
    const char *p = map(path, b, sizeof(b));
    return p ? opendir(p) : NULL;
}
int mock_stat(const char *path, struct stat *st) {
    char b[1024];
    const char *p = map(path, b, sizeof(b));
    return p ? stat(p, st) : -1;
}

size_t vid_screen_shot_data(uint8_t **buffer) {
    size_t n = (size_t)mode.width * mode.height * 3;
    *buffer = malloc(n);
    for (size_t i = 0; i < n; i++) (*buffer)[i] = (uint8_t)(i * 7);
    return n;
}
static maple_device_t ctrl = { { MAPLE_FUNC_CONTROLLER }, 0, 0 };
static maple_device_t vmu  = { { MAPLE_FUNC_MEMCARD }, 0, 1 };
maple_device_t *maple_enum_type(int n, uint32_t func) {
    (void)n;
    return func == MAPLE_FUNC_CONTROLLER ? &ctrl : NULL;
}
maple_device_t *maple_enum_dev(int port, int unit) {
    return (port == 0 && unit == 1 && mock_vmu_present) ? &vmu : NULL;
}
void *maple_dev_status(maple_device_t *dev) { (void)dev; return &mock_cont; }

int vmufs_readdir(maple_device_t *dev, vmu_dir_t **outbuf, int *outcnt) {
    (void)dev;
    *outbuf = malloc(sizeof(vmu_dir_t) * (mock_vmu_count ? mock_vmu_count : 1));
    for (int i = 0; i < mock_vmu_count; i++) (*outbuf)[i] = mock_vmu[i].dir;
    *outcnt = mock_vmu_count;
    return 0;
}
int vmufs_read_dirent(maple_device_t *dev, vmu_dir_t *d, void **outbuf, int *outsize) {
    (void)dev;
    for (int i = 0; i < mock_vmu_count; i++)
        if (memcmp(mock_vmu[i].dir.filename, d->filename, 12) == 0) {
            *outbuf = malloc(mock_vmu[i].size);
            memcpy(*outbuf, mock_vmu[i].data, mock_vmu[i].size);
            *outsize = mock_vmu[i].size;
            return 0;
        }
    return -1;
}
int vmufs_write(maple_device_t *dev, const char *fn, void *inbuf, int insize, int flags) {
    (void)dev; (void)inbuf; (void)flags;
    if (insize / 512 > mock_vmu_free_blocks || written_count == 8) return -1;
    snprintf(written_names[written_count], 16, "%s", fn);
    written_sizes[written_count++] = insize;
    return 0;
}

/* ================= helpers ================= */
static int failures, checks;
#define CHECK(cond, ...) do { checks++; if (!(cond)) { failures++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void host_path(const char *rel, char *out, size_t n) { snprintf(out, n, "%s/host/%s", mock_pc_root, rel); }
static long file_size(const char *rel) {
    char p[1024]; FILE *f; long n;
    host_path(rel, p, sizeof(p));
    if (!(f = fopen(p, "rb"))) return -1;
    fseek(f, 0, SEEK_END); n = ftell(f); fclose(f);
    return n;
}
static void write_file(const char *rel, const void *data, size_t n) {
    char p[1024]; FILE *f;
    host_path(rel, p, sizeof(p));
    f = fopen(p, "wb"); fwrite(data, 1, n, f); fclose(f);
}
static char *read_text(const char *rel) {
    static char buf[8192]; char p[1024]; FILE *f; size_t n;
    host_path(rel, p, sizeof(p));
    if (!(f = fopen(p, "rb"))) return NULL;
    n = fread(buf, 1, sizeof(buf) - 1, f); buf[n] = 0; fclose(f);
    return buf;
}
static void add_vmu(const char *name12, uint8_t type, int blocks, uint8_t fill) {
    mock_vmu_file_t *v = &mock_vmu[mock_vmu_count++];
    memset(&v->dir, 0, sizeof(v->dir));
    memset(v->dir.filename, ' ', 12);
    memcpy(v->dir.filename, name12, strlen(name12) > 12 ? 12 : strlen(name12));
    v->dir.filetype = type;
    v->dir.filesize = blocks;
    v->size = blocks * 512;
    v->data = malloc(v->size);
    memset(v->data, fill, v->size);
}

/* ================= tests ================= */
static void test_disabled(void) {
    dcload_type = DCLOAD_TYPE_NONE;
    CHECK(dcdev_init("/pc/host") == 0, "init must fail without dcload");
    CHECK(dcdev_screenshot(NULL) == -1, "screenshot must fail without dcload");
    CHECK(dcdev_vmu_backup(0, 1) == -1, "vmu backup must fail without dcload");
    CHECK(dcdev_asset_changed("x") == 0, "asset_changed must be 0 without dcload");
    dcdev_log("not written\n");
    CHECK(file_size("logs/dc_log.txt") == -1, "log file must not be created without dcload");
    dcload_type = DCLOAD_TYPE_IP;
}

static void test_init_path(void) {
    char p[128];
    CHECK(dcdev_init("/pc/host//") == 1, "init");
    CHECK(strcmp(dcdev_path("a/b", p, sizeof(p)), "/pc/host/a/b") == 0, "trailing slashes: got %s", p);
}

static void test_screenshot(void) {
    write_file("screenshots/shot_0001.bmp", "x", 1);        /* existing file is skipped */
    CHECK(dcdev_screenshot(NULL) == 0, "auto screenshot 1");
    CHECK(dcdev_screenshot(NULL) == 0, "auto screenshot 2");
    CHECK(file_size("screenshots/shot_0001.bmp") == 1, "existing shot overwritten");
    CHECK(file_size("screenshots/shot_0002.bmp") == 54 + 2 * 12, "shot_0002 size %ld", file_size("screenshots/shot_0002.bmp"));
    CHECK(file_size("screenshots/shot_0003.bmp") == 54 + 2 * 12, "shot_0003 missing");
    CHECK(dcdev_screenshot("named.bmp") == 0 && file_size("screenshots/named.bmp") > 0, "named screenshot");

    /* the streamed file must equal the in-memory encoder output (odd width = row padding) */
    {
        uint8_t *rgb, *bmp;
        size_t n;
        char p[1024];
        FILE *f;
        mode.width = 5; mode.height = 3;
        CHECK(dcdev_screenshot("stream.bmp") == 0, "stream screenshot");
        vid_screen_shot_data(&rgb);
        n = dcdev_bmp_encode(rgb, 5, 3, &bmp);
        host_path("screenshots/stream.bmp", p, sizeof(p));
        f = fopen(p, "rb");
        uint8_t *got = malloc(n + 16);
        size_t gn = f ? fread(got, 1, n + 16, f) : 0;
        if (f) fclose(f);
        CHECK(gn == n && memcmp(got, bmp, n) == 0, "streamed BMP differs from encoder (%zu vs %zu bytes)", gn, n);
        /* first stored row is the bottom image row, as BGR */
        CHECK(bmp[54] == rgb[(2 * 5) * 3 + 2] && bmp[56] == rgb[(2 * 5) * 3 + 0], "bottom-up BGR order");
        free(got); free(bmp); free(rgb);
        mode.width = 4; mode.height = 2;
    }
    CHECK(dcdev_screenshot("../nofolder/x.bmp") == -1, "missing folder must fail");
}

static void test_log(void) {
    char *t;
    mock_us = 12345678;
    dcdev_log("hello %d\n", 42);
    dcdev_log("second\n");
    dcdev_log_close();
    t = read_text("logs/dc_log.txt");
    CHECK(t && strstr(t, "---- new run ----"), "run marker");
    CHECK(t && strstr(t, "[     12.345] hello 42\n"), "timestamped line, got: %s", t ? t : "(null)");
    CHECK(t && strstr(t, "second\n"), "second line");
}

static void test_vmu(void) {
    char *t;
    add_vmu("SAVE1", 0x33, 2, 0xAA);
    add_vmu("MINIGAME", 0xcc, 4, 0xBB);         /* VMU game: skipped */
    add_vmu("ABCDEFGHIJKL", 0x33, 1, 0xCC);     /* full 12-char name, no terminator */
    CHECK(dcdev_vmu_backup(0, 1) == 2, "backup should copy 2 data files");
    CHECK(file_size("vmu/a1/SAVE1") == 1024, "SAVE1 size %ld", file_size("vmu/a1/SAVE1"));
    CHECK(file_size("vmu/a1/ABCDEFGHIJKL") == 512, "12-char name");
    CHECK(file_size("vmu/a1/MINIGAME") == -1, "game file must be skipped");
    t = read_text("vmu/a1/SAVE1");
    CHECK(t && (uint8_t)t[0] == 0xAA, "content");

    write_file("vmu/a1/notes.txt", "abc", 3);   /* not a VMU file: skipped */
    written_count = 0;
    CHECK(dcdev_vmu_restore(0, 1) == 2, "restore should write 2 files (wrote %d)", written_count);
    for (int i = 0; i < written_count; i++)
        CHECK(written_sizes[i] % 512 == 0, "restored size %d", written_sizes[i]);

    mock_vmu_present = 0;
    CHECK(dcdev_vmu_backup(0, 1) == -1, "no VMU must fail");
    mock_vmu_present = 1;
}

static void test_asset(void) {
    size_t size = 0;
    char *a;
    write_file("assets/msg.txt", "hello", 5);
    a = dcdev_asset_load("msg.txt", &size);
    CHECK(a && size == 5 && memcmp(a, "hello", 5) == 0, "asset load");
    free(a);
    CHECK(dcdev_asset_load("missing.bin", &size) == NULL, "missing asset");

    CHECK(dcdev_asset_changed("msg.txt") == 0, "first call is not a change");
    write_file("assets/msg.txt", "hello world", 11);
    mock_us += 100000;
    CHECK(dcdev_asset_changed("msg.txt") == 0, "rate limited within 500 ms");
    mock_us += 500000;
    CHECK(dcdev_asset_changed("msg.txt") == 1, "change detected after 500 ms");
    mock_us += 600000;
    CHECK(dcdev_asset_changed("msg.txt") == 0, "no second report");

    /* a file that does not exist yet must also be rate limited (no network call every frame) */
    int before = mock_fs_calls;
    for (int i = 0; i < 60; i++) { mock_us += 16667; dcdev_asset_changed("later.txt"); }
    int calls = mock_fs_calls - before;
    CHECK(calls <= 3, "missing file polled %d times in 1 s (should be <= 3)", calls);

    /* ...and its creation counts as a change */
    write_file("assets/later.txt", "new", 3);
    mock_us += 600000;
    CHECK(dcdev_asset_changed("later.txt") == 1, "newly created file must be reported");
}

static void test_prof(void) {
    char *t;
    dcdev_prof_set_interval(10);
    dcdev_prof_frame();                         /* starts the first frame */
    for (int f = 0; f < 10; f++) {
        dcdev_prof_begin("logic"); mock_us += 1000 + f * 100; dcdev_prof_end("logic");
        dcdev_prof_begin("draw");  mock_us += 5000;           dcdev_prof_end("draw");
        mock_us += 10667;
        dcdev_prof_frame();
    }
    t = read_text("prof/prof.csv");
    CHECK(t && strstr(t, "frame,section,avg_us,max_us\n"), "csv header");
    /* logic: 1000..1900 -> avg 1450, max 1900 */
    CHECK(t && strstr(t, ",logic,1450,1900\n"), "logic avg/max, csv:\n%s", t ? t : "(null)");
    CHECK(t && strstr(t, ",draw,5000,5000\n"), "draw avg/max");
    CHECK(t && strstr(t, ",frame,17117,17567\n"), "frame avg/max");
}

static void test_poll(void) {
    int shots_before = (int)file_size("screenshots/shot_0004.bmp");
    memset(&mock_cont, 0, sizeof(mock_cont));
    mock_cont.buttons = CONT_A;
    CHECK(dcdev_poll() == 0, "A without triggers does nothing");
    mock_cont.buttons = 0;
    dcdev_poll();
    mock_cont.ltrig = mock_cont.rtrig = 255;
    dcdev_poll();
    mock_cont.buttons = CONT_A;
    CHECK(dcdev_poll() == CONT_A, "L+R+A fires");
    CHECK(dcdev_poll() == 0, "holding A must not fire again");
    CHECK(shots_before == -1 && file_size("screenshots/shot_0004.bmp") > 0, "combo took a screenshot");
    /* pressing the triggers while A is already held must not fire */
    mock_cont.ltrig = mock_cont.rtrig = 0;
    mock_cont.buttons = CONT_A;
    dcdev_poll();
    mock_cont.ltrig = mock_cont.rtrig = 255;
    CHECK(dcdev_poll() == 0, "A held before the triggers must not fire");
}

int main(int argc, char **argv) {
    const char *subs[] = { "", "/host", "/host/screenshots", "/host/logs", "/host/assets",
                           "/host/prof", "/host/vmu", "/host/vmu/a1" };
    if (argc < 2) { printf("usage: test_dcdev <empty temp folder>\n"); return 2; }
    snprintf(mock_pc_root, sizeof(mock_pc_root), "%s", argv[1]);
    for (size_t i = 0; i < sizeof(subs) / sizeof(subs[0]); i++) {
        char p[1024]; snprintf(p, sizeof(p), "%s%s", mock_pc_root, subs[i]); _mkdir(p);
    }
    test_disabled();
    test_init_path();
    test_screenshot();
    test_log();
    test_vmu();
    test_asset();
    test_prof();
    test_poll();
    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
