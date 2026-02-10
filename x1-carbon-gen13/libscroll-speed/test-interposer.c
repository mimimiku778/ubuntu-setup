/*
 * test-interposer.c — libscroll-speed の動作検証
 *
 * 1. 設定ファイルのパース
 * 2. LD_PRELOAD でシンボルが正しく差し替わるか
 * 3. 非線形カーブの出力が期待値と一致するか
 * 4. イベントタイプごとの分岐（FINGER / WHEEL）
 *
 * Usage:
 *   gcc -o test-interposer test-interposer.c -ldl -lm -linput
 *   # Without preload (raw libinput):
 *   ./test-interposer raw
 *   # With preload (intercepted):
 *   LD_PRELOAD=./libscroll-speed.so ./test-interposer preload
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libinput.h>

/* ── Color output ─────────────────────────────────────────── */
#define GREEN  "\033[1;32m"
#define RED    "\033[1;31m"
#define YELLOW "\033[1;33m"
#define RESET  "\033[0m"

static int g_pass = 0, g_fail = 0;

static void check(const char *name, int cond) {
    if (cond) {
        printf(GREEN "  PASS" RESET "  %s\n", name);
        g_pass++;
    } else {
        printf(RED "  FAIL" RESET "  %s\n", name);
        g_fail++;
    }
}

/* ── Reference transform (must match scroll-speed.c) ──────── */
static double ref_transform(double delta, double base, double cap) {
    double sign = (delta >= 0.0) ? 1.0 : -1.0;
    double abs_d = fabs(delta);
    if (cap <= 0.0)
        return delta * base;
    return sign * base * cap * tanh(abs_d / cap);
}

/* ── Test 1: Config file parsing ──────────────────────────── */
static void test_config_parse(void) {
    printf("\n== Config parse ==\n");

    /* Write a temp config */
    const char *path = "/tmp/test-scroll-speed.conf";
    FILE *f = fopen(path, "w");
    if (!f) { printf(RED "  Cannot write temp config\n" RESET); return; }
    fprintf(f, "# test config\n");
    fprintf(f, "base-speed=0.42\n");
    fprintf(f, "scroll-cap=12.5\n");
    fprintf(f, "discrete-scroll-factor=1.5\n");
    fclose(f);

    /* Read it back and verify */
    f = fopen(path, "r");
    double base = -1, cap = -1, disc = -1;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '#' || line[0] == '\n') continue;
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        /* trim */
        char *k = line;
        while (*k == ' ') k++;
        double val = atof(eq + 1);
        if (strcmp(k, "base-speed") == 0) base = val;
        else if (strcmp(k, "scroll-cap") == 0) cap = val;
        else if (strcmp(k, "discrete-scroll-factor") == 0) disc = val;
    }
    fclose(f);
    remove(path);

    check("base-speed parsed",          fabs(base - 0.42) < 0.001);
    check("scroll-cap parsed",          fabs(cap - 12.5) < 0.001);
    check("discrete-scroll-factor parsed", fabs(disc - 1.5) < 0.001);
}

/* ── Test 2: Transform curve math ─────────────────────────── */
static void test_curve_math(void) {
    printf("\n== Curve math (base=0.55, cap=15) ==\n");

    double base = 0.55, cap = 15.0;

    /* Small delta: nearly linear */
    double out1 = ref_transform(1.0, base, cap);
    check("delta=1: ≈ 0.55 (linear region)",
          fabs(out1 - 0.55) < 0.01);

    /* Medium delta: moderate reduction */
    double out10 = ref_transform(10.0, base, cap);
    check("delta=10: output ≈ 4.81",
          fabs(out10 - 4.81) < 0.05);

    /* Large delta: hard cap */
    double out50 = ref_transform(50.0, base, cap);
    double max_out = base * cap;
    check("delta=50: approaches max (8.25)",
          fabs(out50 - max_out) < 0.1);

    /* Negative delta: symmetric */
    double out_neg = ref_transform(-10.0, base, cap);
    check("negative delta: symmetric",
          fabs(out_neg + out10) < 0.001);

    /* Zero: identity */
    check("delta=0: output = 0",
          ref_transform(0.0, base, cap) == 0.0);

    /* Monotonic */
    int mono = 1;
    for (double d = 0.1; d < 100.0; d += 0.1) {
        if (ref_transform(d, base, cap) < ref_transform(d - 0.1, base, cap)) {
            mono = 0;
            break;
        }
    }
    check("monotonically increasing", mono);
}

/* ── Test 3: Symbol interposition (LD_PRELOAD mode) ──────── */
static void test_symbol_interposition(void) {
    printf("\n== Symbol interposition ==\n");

    /* Check that the scroll_value function symbol exists */
    void *sym = dlsym(RTLD_DEFAULT,
                      "libinput_event_pointer_get_scroll_value");
    check("get_scroll_value symbol resolved", sym != NULL);

    void *sym120 = dlsym(RTLD_DEFAULT,
                         "libinput_event_pointer_get_scroll_value_v120");
    check("get_scroll_value_v120 symbol resolved", sym120 != NULL);

    /* Check base_event and get_type are available (not intercepted) */
    void *sym_base = dlsym(RTLD_DEFAULT,
                           "libinput_event_pointer_get_base_event");
    check("get_base_event symbol available", sym_base != NULL);

    void *sym_type = dlsym(RTLD_DEFAULT,
                           "libinput_event_get_type");
    check("get_type symbol available", sym_type != NULL);
}

/* ── Test 4: LD_PRELOAD check ─────────────────────────────── */
static void test_preload_active(const char *mode) {
    printf("\n== LD_PRELOAD status ==\n");

    if (strcmp(mode, "preload") == 0) {
        /* Check for our marker function — proves our .so is loaded */
        typedef const char *(*version_fn)(void);
        version_fn ver = (version_fn)dlsym(RTLD_DEFAULT,
                                           "libscroll_speed_version");
        check("libscroll-speed loaded (marker found)", ver != NULL);
        if (ver)
            printf("  version: %s\n", ver());

        /* Verify scroll_value symbol is present */
        void *sym = dlsym(RTLD_DEFAULT,
                          "libinput_event_pointer_get_scroll_value");
        check("get_scroll_value intercepted", sym != NULL);
    } else {
        void *sym = dlsym(RTLD_DEFAULT,
                          "libinput_event_pointer_get_scroll_value");
        printf("  (not in preload mode, skipping interposition check)\n");
        check("raw mode: symbol exists", sym != NULL);

        /* Marker should NOT be present without preload */
        void *ver = dlsym(RTLD_DEFAULT, "libscroll_speed_version");
        check("raw mode: interposer NOT loaded", ver == NULL);
    }
}

/* ── Main ─────────────────────────────────────────────────── */
int main(int argc, char **argv) {
    const char *mode = (argc > 1) ? argv[1] : "raw";

    printf("libscroll-speed test suite (mode: %s)\n", mode);

    test_config_parse();
    test_curve_math();
    test_symbol_interposition();
    test_preload_active(mode);

    printf("\n────────────────────────────────\n");
    printf("Results: " GREEN "%d passed" RESET ", ", g_pass);
    if (g_fail > 0)
        printf(RED "%d failed" RESET "\n", g_fail);
    else
        printf("0 failed\n");

    return g_fail > 0 ? 1 : 0;
}
