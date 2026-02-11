/*
 * scroll-speed.c — Non-linear touchpad scroll speed interposer
 *
 * LD_PRELOAD library that intercepts libinput scroll value getters
 * and applies a macOS-like non-linear curve:
 *   - Slow finger movement: nearly 1:1 (precise control)
 *   - Fast finger movement: soft speed cap (tames kinetic scrolling)
 *
 * Build:
 *   gcc -shared -fPIC -O2 -o libscroll-speed.so scroll-speed.c -ldl -lm
 *
 * Install:
 *   sudo cp libscroll-speed.so /usr/local/lib/x86_64-linux-gnu/
 *   echo '/usr/local/lib/x86_64-linux-gnu/libscroll-speed.so' | sudo tee /etc/ld.so.preload
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
#include <libinput.h>

/* ── Version / presence marker (for testing) ──────────────── */
const char *libscroll_speed_version(void) { return "1.0.0"; }

/* ── Configuration defaults ───────────────────────────────── */

/* Base sensitivity for slow/precise scrolling (0.0–1.0+).
 * macOS feels like ~0.5–0.6 for trackpad finger scrolling. */
static double cfg_base_speed = 0.55;

/* Soft speed cap (in scroll-value units).
 * Deltas above this are progressively squashed via tanh.
 * Effective max output ≈ base_speed × scroll_cap.         */
static double cfg_scroll_cap = 12.0;

/* Linear factor for discrete mouse wheel (1.0 = unchanged). */
static double cfg_discrete_factor = 1.0;

/* Ramp softness exponent (1.0 = linear start, >1 = gentler initial ramp).
 * Higher values suppress small-delta output while preserving max speed.
 * Useful for taming kinetic/inertial scrolling in browsers.           */
static double cfg_ramp_softness = 2.2;

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

/* ── Config file parser ───────────────────────────────────── */

static void trim(char *s)
{
    /* trim trailing whitespace / newline */
    char *end = s + strlen(s) - 1;
    while (end >= s && (*end == ' ' || *end == '\t' || *end == '\n' || *end == '\r'))
        *end-- = '\0';
    /* trim leading whitespace (shift in-place) */
    char *start = s;
    while (*start == ' ' || *start == '\t')
        start++;
    if (start != s)
        memmove(s, start, strlen(start) + 1);
}

static void load_config(void)
{
    FILE *f = fopen("/etc/scroll-speed.conf", "r");
    if (!f)
        return;

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
    }
    fclose(f);
}

/* ── Initialization ───────────────────────────────────────── */

static void do_init(void)
{
    real_get_scroll_value =
        dlsym(RTLD_NEXT, "libinput_event_pointer_get_scroll_value");
    real_get_scroll_value_v120 =
        dlsym(RTLD_NEXT, "libinput_event_pointer_get_scroll_value_v120");
    real_get_base_event =
        dlsym(RTLD_NEXT, "libinput_event_pointer_get_base_event");
    real_get_type =
        dlsym(RTLD_NEXT, "libinput_event_get_type");

    load_config();
}

static void init(void)
{
    pthread_once(&g_init_once, do_init);
}

/* ── Non-linear transform (Hill function) ─────────────────── *
 *
 * f(delta) = sign(d) × base_speed × cap × x / (1 + x)
 *   where x = (|d| / cap) ^ softness
 *
 * Properties:
 *   - At d = cap: output = 50% of max (= base_speed × cap / 2)
 *   - softness=1 → linear start
 *   - softness>1 → suppresses small deltas (inertial tail)
 *   - Approaches max gradually (unlike tanh which saturates abruptly)
 *
 * Example with base_speed=0.80, cap=10, softness=3.0:
 *   delta= 1 → 0.008 (0.8%)  — inertial tail, nearly silent
 *   delta= 2 → 0.063 (3%)    — inertial, strongly suppressed
 *   delta= 5 → 0.89  (18%)   — slow scroll, preserved
 *   delta=10 → 4.00  (40%)   — medium: gradual mid-range
 *   delta=15 → 6.17  (41%)   — medium-fast, still climbing
 *   delta=20 → 7.11  (36%)   — fast, approaching cap
 *   delta=30 → 7.71  (26%)   — very fast
 *   maximum  → 8.00          — absolute ceiling (= base_speed × cap)
 */
static double transform_finger(double delta)
{
    if (cfg_scroll_cap <= 0.0)
        return delta * cfg_base_speed;

    double sign = (delta >= 0.0) ? 1.0 : -1.0;
    double abs_d = fabs(delta);
    double normalized = abs_d / cfg_scroll_cap;

    /* Apply softness: pow(x, s) with s>1 flattens near zero */
    if (cfg_ramp_softness != 1.0 && normalized > 0.0)
        normalized = pow(normalized, cfg_ramp_softness);

    /* Hill function: x/(1+x) — gradual saturation unlike tanh */
    return sign * cfg_base_speed * cfg_scroll_cap * (normalized / (1.0 + normalized));
}

/* ── Intercepted API ──────────────────────────────────────── */

double libinput_event_pointer_get_scroll_value(
    struct libinput_event_pointer *event,
    enum libinput_pointer_axis axis)
{
    init();
    if (!real_get_scroll_value || !real_get_base_event || !real_get_type)
        return 0.0;

    double raw = real_get_scroll_value(event, axis);

    /* Determine event type to choose transform */
    struct libinput_event *base = real_get_base_event(event);
    enum libinput_event_type type = real_get_type(base);

    switch (type) {
    case LIBINPUT_EVENT_POINTER_SCROLL_FINGER:
        return transform_finger(raw);

    case LIBINPUT_EVENT_POINTER_SCROLL_WHEEL:
        return raw * cfg_discrete_factor;

    case LIBINPUT_EVENT_POINTER_SCROLL_CONTINUOUS:
        /* TrackPoint middle-button scroll — apply same finger curve */
        return transform_finger(raw);

    default:
        return raw;
    }
}

double libinput_event_pointer_get_scroll_value_v120(
    struct libinput_event_pointer *event,
    enum libinput_pointer_axis axis)
{
    init();
    if (!real_get_scroll_value_v120 || !real_get_base_event || !real_get_type)
        return 0.0;

    double raw = real_get_scroll_value_v120(event, axis);

    /* v120 is primarily used for high-res mouse wheels.
     * Touchpad SCROLL_FINGER events return 0 here. */
    struct libinput_event *base = real_get_base_event(event);
    enum libinput_event_type type = real_get_type(base);

    if (type == LIBINPUT_EVENT_POINTER_SCROLL_WHEEL)
        return raw * cfg_discrete_factor;

    /* For non-wheel events that somehow have v120, apply finger curve */
    if (raw != 0.0)
        return transform_finger(raw);

    return raw;
}
