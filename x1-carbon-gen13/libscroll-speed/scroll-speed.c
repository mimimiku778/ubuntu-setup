/*
 * scroll-speed.c — Non-linear touchpad scroll speed interposer
 *
 * LD_PRELOAD library that intercepts libinput scroll value getters
 * and applies a macOS-like non-linear curve:
 *   - Slow finger movement: nearly 1:1 (precise control)
 *   - Fast finger movement: soft speed cap (tames kinetic scrolling)
 *
 * Per-app scroll factor (e.g. for Chromium):
 *   When loaded into gnome-shell via /etc/ld.so.preload, the library
 *   uses Mutter/GNOME Shell API to detect the focused window's process.
 *   If the focused app matches a known browser (Chrome/Chromium/Electron),
 *   an additional chrome-scroll-factor is applied to compensate for
 *   Chrome's higher internal scroll multiplier.
 *
 * Build:
 *   gcc -shared -fPIC -O2 -o libscroll-speed.so scroll-speed.c -ldl -lm
 *
 * Install:
 *   sudo cp libscroll-speed.so /usr/local/lib/x86_64-linux-gnu/
 *   echo '/usr/local/lib/x86_64-linux-gnu/libscroll-speed.so' \
 *        | sudo tee /etc/ld.so.preload
 *
 * Config: /etc/scroll-speed.conf
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <libinput.h>

/* ── Version / presence marker (for testing) ──────────────── */
const char *libscroll_speed_version(void) { return "2.1.0"; }

/* ── Configuration defaults ───────────────────────────────── */

static double cfg_base_speed = 0.46;
static double cfg_scroll_cap = 20.0;
static double cfg_discrete_factor = 1.0;
static double cfg_ramp_softness = 1.0;
static double cfg_low_cut = 0.0;

/* Per-app scroll factor for Chromium-based browsers.
 * Applied compositor-side by detecting focused window PID.
 * Use < 1.0 to reduce Chrome's scroll speed.               */
static double cfg_chrome_scroll_factor = 1.0;

/* ── Internal state ───────────────────────────────────────── */

static pthread_once_t g_init_once = PTHREAD_ONCE_INIT;

/* Real libinput function pointers resolved via dlsym */
static double (*real_get_scroll_value)(
    struct libinput_event_pointer *, enum libinput_pointer_axis);
static double (*real_get_scroll_value_v120)(
    struct libinput_event_pointer *, enum libinput_pointer_axis);
static struct libinput_event *(*real_get_base_event)(
    struct libinput_event_pointer *);
static enum libinput_event_type (*real_get_type)(
    struct libinput_event *);

/* Mutter / GNOME Shell API function pointers.
 * Resolved via dlsym(RTLD_DEFAULT) — only available when
 * loaded into gnome-shell (the compositor process).          */
static void *(*fn_shell_global_get)(void);
static void *(*fn_shell_global_get_display)(void *);
static void *(*fn_meta_display_get_focus_window)(void *);
static int   (*fn_meta_window_get_pid)(void *);

/* Focused-window Chrome detection cache */
static pid_t g_cached_focus_pid = -1;
static int   g_cached_is_chrome = 0;

/* Hot-reload: re-read config when /etc/scroll-speed.conf changes */
#define CONF_PATH "/etc/scroll-speed.conf"
#define RELOAD_INTERVAL 3  /* seconds between stat() checks */
static time_t g_conf_mtime = 0;
static time_t g_last_check = 0;

/* ── Config file parser ───────────────────────────────────── */

static void trim(char *s)
{
    char *end = s + strlen(s) - 1;
    while (end >= s && (*end == ' ' || *end == '\t' || *end == '\n' || *end == '\r'))
        *end-- = '\0';
    char *start = s;
    while (*start == ' ' || *start == '\t')
        start++;
    if (start != s)
        memmove(s, start, strlen(start) + 1);
}

static void load_config(void)
{
    FILE *f = fopen(CONF_PATH, "r");
    if (!f)
        return;

    struct stat st;
    if (fstat(fileno(f), &st) == 0)
        g_conf_mtime = st.st_mtime;

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '#' || line[0] == '\n' || line[0] == '\r')
            continue;

        char *eq = strchr(line, '=');
        if (!eq)
            continue;

        *eq = '\0';
        char *key = line;
        char *val = eq + 1;
        trim(key);
        trim(val);

        double v = atof(val);
        if (strcmp(key, "base-speed") == 0)
            cfg_base_speed = v;
        else if (strcmp(key, "scroll-cap") == 0)
            cfg_scroll_cap = v;
        else if (strcmp(key, "discrete-scroll-factor") == 0)
            cfg_discrete_factor = v;
        else if (strcmp(key, "ramp-softness") == 0)
            cfg_ramp_softness = v;
        else if (strcmp(key, "low-cut") == 0)
            cfg_low_cut = v;
        else if (strcmp(key, "chrome-scroll-factor") == 0)
            cfg_chrome_scroll_factor = v;
    }
    fclose(f);
}

/* ── Hot-reload ───────────────────────────────────────────── */

static void maybe_reload_config(void)
{
    time_t now = time(NULL);
    if (now - g_last_check < RELOAD_INTERVAL)
        return;
    g_last_check = now;

    struct stat st;
    if (stat(CONF_PATH, &st) == 0 && st.st_mtime != g_conf_mtime) {
        g_conf_mtime = st.st_mtime;
        load_config();
    }
}

/* ── Initialization ───────────────────────────────────────── */

static void do_init(void)
{
    real_get_scroll_value = dlsym(RTLD_NEXT,
        "libinput_event_pointer_get_scroll_value");
    real_get_scroll_value_v120 = dlsym(RTLD_NEXT,
        "libinput_event_pointer_get_scroll_value_v120");
    real_get_base_event = dlsym(RTLD_NEXT,
        "libinput_event_pointer_get_base_event");
    real_get_type = dlsym(RTLD_NEXT,
        "libinput_event_get_type");

    load_config();

    /* Resolve Mutter/GNOME Shell API for per-app scroll factor.
     * Always resolve (not gated on config value) so that
     * hot-reload can enable chrome-scroll-factor later.
     * These are only available inside gnome-shell; in other
     * processes they resolve to NULL and the feature is skipped. */
    fn_shell_global_get =
        dlsym(RTLD_DEFAULT, "shell_global_get");
    fn_shell_global_get_display =
        dlsym(RTLD_DEFAULT, "shell_global_get_display");
    fn_meta_display_get_focus_window =
        dlsym(RTLD_DEFAULT, "meta_display_get_focus_window");
    fn_meta_window_get_pid =
        dlsym(RTLD_DEFAULT, "meta_window_get_pid");

    /* Log once at init to verify Mutter API resolution */
    FILE *dbg = fopen("/tmp/scroll-speed-init.log", "a");
    if (dbg) {
        char exe[256] = {0};
        ssize_t r = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
        if (r > 0) exe[r] = '\0';
        fprintf(dbg, "[%s] v2.1.0 chrome-factor=%.2f "
                "shell_global_get=%p display_get_focus=%p "
                "window_get_pid=%p\n",
                exe, cfg_chrome_scroll_factor,
                (void *)fn_shell_global_get,
                (void *)fn_meta_display_get_focus_window,
                (void *)fn_meta_window_get_pid);
        fclose(dbg);
    }
}

static void init(void)
{
    pthread_once(&g_init_once, do_init);
}

/* ── Focused-window Chrome detection ─────────────────────── */

static int is_focused_chrome(void)
{
    if (!fn_shell_global_get || !fn_shell_global_get_display ||
        !fn_meta_display_get_focus_window || !fn_meta_window_get_pid)
        return 0;

    void *global = fn_shell_global_get();
    if (!global) return 0;

    void *display = fn_shell_global_get_display(global);
    if (!display) return 0;

    void *window = fn_meta_display_get_focus_window(display);
    if (!window) return 0;

    pid_t pid = fn_meta_window_get_pid(window);
    if (pid <= 0) return 0;

    if (pid != g_cached_focus_pid) {
        g_cached_focus_pid = pid;
        g_cached_is_chrome = 0;

        char path[64];
        char exe[256];
        snprintf(path, sizeof(path), "/proc/%d/exe", pid);
        ssize_t n = readlink(path, exe, sizeof(exe) - 1);
        if (n > 0) {
            exe[n] = '\0';
            if (strstr(exe, "chrome") || strstr(exe, "chromium") ||
                strstr(exe, "electron"))
                g_cached_is_chrome = 1;
        }
    }

    return g_cached_is_chrome;
}

/* ── Non-linear transform (Hill function) ─────────────────── */

static double transform_finger(double delta)
{
    if (cfg_scroll_cap <= 0.0)
        return delta * cfg_base_speed;

    double sign = (delta >= 0.0) ? 1.0 : -1.0;
    double abs_d = fabs(delta);
    double normalized = abs_d / cfg_scroll_cap;

    if (cfg_ramp_softness != 1.0 && normalized > 0.0)
        normalized = pow(normalized, cfg_ramp_softness);

    double out = cfg_base_speed * cfg_scroll_cap * (normalized / (1.0 + normalized));

    if (cfg_low_cut > 0.0) {
        double d2 = abs_d * abs_d;
        double d4 = d2 * d2;
        double t2 = cfg_low_cut * cfg_low_cut;
        double t4 = t2 * t2;
        out *= d4 / (t4 + d4);
    }

    return sign * out;
}

/* ── Per-app scroll factor ────────────────────────────────── */

static double app_scroll_factor(void)
{
    if (cfg_chrome_scroll_factor != 1.0 && is_focused_chrome())
        return cfg_chrome_scroll_factor;
    return 1.0;
}

/* ── Intercepted libinput API (runs inside Mutter) ────────── */

double libinput_event_pointer_get_scroll_value(
    struct libinput_event_pointer *event,
    enum libinput_pointer_axis axis)
{
    init();
    maybe_reload_config();
    if (!real_get_scroll_value || !real_get_base_event || !real_get_type)
        return 0.0;

    double raw = real_get_scroll_value(event, axis);

    struct libinput_event *base = real_get_base_event(event);
    enum libinput_event_type type = real_get_type(base);

    double factor = app_scroll_factor();

    switch (type) {
    case LIBINPUT_EVENT_POINTER_SCROLL_FINGER:
        return transform_finger(raw) * factor;
    case LIBINPUT_EVENT_POINTER_SCROLL_WHEEL:
        return raw * cfg_discrete_factor;
    case LIBINPUT_EVENT_POINTER_SCROLL_CONTINUOUS:
        return transform_finger(raw) * factor;
    default:
        return raw;
    }
}

double libinput_event_pointer_get_scroll_value_v120(
    struct libinput_event_pointer *event,
    enum libinput_pointer_axis axis)
{
    init();
    maybe_reload_config();
    if (!real_get_scroll_value_v120 || !real_get_base_event || !real_get_type)
        return 0.0;

    double raw = real_get_scroll_value_v120(event, axis);

    struct libinput_event *base = real_get_base_event(event);
    enum libinput_event_type type = real_get_type(base);

    if (type == LIBINPUT_EVENT_POINTER_SCROLL_WHEEL)
        return raw * cfg_discrete_factor;

    if (raw != 0.0) {
        double factor = app_scroll_factor();
        return transform_finger(raw) * factor;
    }

    return raw;
}
