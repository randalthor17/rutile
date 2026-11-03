/*
 * rutile-calendar: the calendar under the clock reads the user's calendars through evolution-data-server (D95).
 *
 * GNOME Online Accounts signs in to Google (or Microsoft, Nextcloud, CalDAV...) and evolution-data-server keeps
 * those calendars, and local ones, in sync; GNOME Calendar edits them. The shell cannot hold a D-Bus connection of
 * its own (EDS closes a calendar as soon as the client that opened it leaves), so this program opens them with
 * libecal, prints what the shell asks for and exits:
 *
 *   rutile-calendar events FROM TO   every event that is on between FROM and TO (Unix seconds), one JSON object a
 *                                    line: {"calendar", "color", "source", "uid", "rid", "title", "location",
 *                                    "start", "end" (Unix seconds), "allDay"}; repeats expanded by EDS, in the
 *                                    events' own time zones; all-day events from local midnight to local midnight
 *   rutile-calendar refresh          asks every calendar that can to sync with its server now
 *   rutile-calendar sources          the calendars, one JSON object a line: {"source", "name", "color", "backend",
 *                                    "selected"}
 *
 * Each calendar is read on a thread of its own, its lines printed together, in the data server's order.
 * Only enabled calendars that are selected (shown, in GNOME Calendar's terms) are read. A calendar that cannot be
 * opened (offline, a sign-in to renew) is skipped with a line on stderr; the others still print.
 * Exit status: 0; 1 for a wrong command line; 2 when evolution-data-server cannot be reached.
 */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <libecal/libecal.h>

/* How long to wait for a calendar to be online. Local ones never say so and take the whole wait (seen with
 * evolution-data-server 3.60), and one that is not online still answers from its copy, so the wait is short; the
 * calendars are opened side by side, so the whole read takes about this long. */
#define CONNECT_SECONDS 1u

/* ---- JSON strings: escaped, and only valid UTF-8 (anything else becomes U+FFFD) ---- */
static void put_string(GString *out, const char *s) {
    g_string_append_c(out, '"');
    if (s == NULL) s = "";
    gchar *valid = g_utf8_make_valid(s, -1);
    for (const unsigned char *p = (const unsigned char *)valid; *p; p++) {
        switch (*p) {
        case '"': g_string_append(out, "\\\""); break;
        case '\\': g_string_append(out, "\\\\"); break;
        case '\n': g_string_append(out, "\\n"); break;
        case '\r': g_string_append(out, "\\r"); break;
        case '\t': g_string_append(out, "\\t"); break;
        default:
            if (*p < 0x20) g_string_append_printf(out, "\\u%04x", *p);
            else g_string_append_c(out, (char)*p);
        }
    }
    g_free(valid);
    g_string_append_c(out, '"');
}

static void put_field(GString *out, const char *name, const char *value, gboolean first) {
    if (!first) g_string_append_c(out, ',');
    put_string(out, name);
    g_string_append_c(out, ':');
    put_string(out, value);
}

/* a finished line into a calendar's output */
static void emit(GString *out, GString *line) {
    g_string_append_len(out, line->str, (gssize)line->len);
    g_string_append_c(out, '\n');
}

/* ---- times ---- */
/* The local time zone, for floating times (no zone) and as the calendars' default; NULL when unknown. */
static ICalTimezone *local_zone(void) {
    const char *tz = getenv("TZ");
    char buf[PATH_MAX];
    if (tz == NULL || *tz == '\0') {
        ssize_t n = readlink("/etc/localtime", buf, sizeof buf - 1);
        if (n <= 0) return NULL;
        buf[n] = '\0';
        const char *at = strstr(buf, "zoneinfo/");
        if (at == NULL) return NULL;
        tz = at + strlen("zoneinfo/");
    } else if (*tz == ':') {
        tz++;
    }
    return i_cal_timezone_get_builtin_timezone(tz);
}

/* A time as Unix seconds: a date at local midnight, a time in its own zone (floating: local). */
static gint64 seconds(ICalTime *t) {
    if (i_cal_time_is_date(t)) {
        struct tm tm = { 0 };
        tm.tm_year = i_cal_time_get_year(t) - 1900;
        tm.tm_mon = i_cal_time_get_month(t) - 1;
        tm.tm_mday = i_cal_time_get_day(t);
        tm.tm_isdst = -1;
        return (gint64)mktime(&tm);
    }
    /* a floating time comes with the calendar's default zone, set to the local one (open_calendar) */
    return (gint64)i_cal_time_as_timet_with_zone(t, i_cal_time_get_timezone(t));
}

/* ---- the calendars ---- */
typedef struct {
    ESource *source;
    gboolean refresh;           /* refresh, or list the events between from and to */
    time_t from, to;
    ICalTimezone *local;
    gchar *color;
    GString *out;               /* its lines */
    GThread *thread;
} Calendar;

static gboolean instance(ICalComponent *comp, ICalTime *start, ICalTime *end, gpointer data, GCancellable *cancel,
                         GError **error) {
    (void)cancel;
    (void)error;
    const Calendar *cal = data;
    GString *line = g_string_new("{");
    put_field(line, "calendar", e_source_get_display_name(cal->source), TRUE);
    put_field(line, "color", cal->color, FALSE);
    put_field(line, "source", e_source_get_uid(cal->source), FALSE);
    put_field(line, "uid", i_cal_component_get_uid(comp), FALSE);
    gchar *rid = NULL;
    ICalTime *recur = i_cal_component_get_recurrenceid(comp);
    if (recur != NULL && !i_cal_time_is_null_time(recur)) rid = i_cal_time_as_ical_string(recur);
    if (recur != NULL) g_object_unref(recur);
    put_field(line, "rid", rid, FALSE);
    g_free(rid);
    put_field(line, "title", i_cal_component_get_summary(comp), FALSE);
    put_field(line, "location", i_cal_component_get_location(comp), FALSE);
    gint64 s = seconds(start), e = end != NULL ? seconds(end) : s;
    if (e < s) e = s;
    g_string_append_printf(line, ",\"start\":%" G_GINT64_FORMAT ",\"end\":%" G_GINT64_FORMAT ",\"allDay\":%s}", s, e,
                           i_cal_time_is_date(start) ? "true" : "false");
    emit(cal->out, line);
    g_string_free(line, TRUE);
    return TRUE;
}

static ECalClient *open_calendar(ESource *source, ICalTimezone *local) {
    GError *error = NULL;
    EClient *client = e_cal_client_connect_sync(source, E_CAL_CLIENT_SOURCE_TYPE_EVENTS, CONNECT_SECONDS, NULL, &error);
    if (client == NULL) {
        fprintf(stderr, "rutile-calendar: %s: %s\n", e_source_get_display_name(source),
                error != NULL ? error->message : "cannot open");
        g_clear_error(&error);
        return NULL;
    }
    if (local != NULL) e_cal_client_set_default_timezone(E_CAL_CLIENT(client), local);
    return E_CAL_CLIENT(client);
}

static gboolean selected(ESource *source) {
    ESourceSelectable *ext = e_source_get_extension(source, E_SOURCE_EXTENSION_CALENDAR);
    return e_source_selectable_get_selected(ext);
}

static gchar *color_of(ESource *source) {
    ESourceSelectable *ext = e_source_get_extension(source, E_SOURCE_EXTENSION_CALENDAR);
    gchar *c = e_source_selectable_dup_color(ext);
    return c != NULL ? c : g_strdup("");
}

/* One calendar, on its own thread: opened, then refreshed or read. */
static gpointer work(gpointer data) {
    Calendar *cal = data;
    ECalClient *client = open_calendar(cal->source, cal->local);
    if (client == NULL) return NULL;
    GError *error = NULL;
    if (cal->refresh) {
        if (e_client_check_refresh_supported(E_CLIENT(client)) && !e_client_refresh_sync(E_CLIENT(client), NULL, &error)) {
            fprintf(stderr, "rutile-calendar: %s: %s\n", e_source_get_display_name(cal->source), error->message);
            g_clear_error(&error);
        }
    } else {
        e_cal_client_generate_instances_sync(client, cal->from, cal->to, NULL, instance, cal);
    }
    g_object_unref(client);
    return NULL;
}

static gboolean parse_time(const char *s, time_t *out) {
    char *end = NULL;
    errno = 0;
    long long v = strtoll(s, &end, 10);
    if (errno != 0 || end == s || *end != '\0') return FALSE;
    *out = (time_t)v;
    return TRUE;
}

static int usage(void) {
    fputs("usage: rutile-calendar events FROM TO | refresh | sources\n", stderr);
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 2) return usage();
    const char *cmd = argv[1];
    time_t from = 0, to = 0;
    if (strcmp(cmd, "events") == 0) {
        if (argc != 4 || !parse_time(argv[2], &from) || !parse_time(argv[3], &to) || to <= from) return usage();
    } else if ((strcmp(cmd, "refresh") != 0 && strcmp(cmd, "sources") != 0) || argc != 2) {
        return usage();
    }

    GError *error = NULL;
    ESourceRegistry *registry = e_source_registry_new_sync(NULL, &error);
    if (registry == NULL) {
        fprintf(stderr, "rutile-calendar: no evolution-data-server: %s\n", error != NULL ? error->message : "");
        g_clear_error(&error);
        return 2;
    }
    ICalTimezone *local = local_zone();
    GList *sources = e_source_registry_list_enabled(registry, E_SOURCE_EXTENSION_CALENDAR);
    GPtrArray *calendars = g_ptr_array_new();
    GString *out = g_string_new("");
    for (GList *l = sources; l != NULL; l = l->next) {
        ESource *source = l->data;
        if (strcmp(cmd, "sources") == 0) {
            gchar *color = color_of(source);
            ESourceBackend *backend = e_source_get_extension(source, E_SOURCE_EXTENSION_CALENDAR);
            GString *line = g_string_new("{");
            put_field(line, "source", e_source_get_uid(source), TRUE);
            put_field(line, "name", e_source_get_display_name(source), FALSE);
            put_field(line, "color", color, FALSE);
            put_field(line, "backend", e_source_backend_get_backend_name(backend), FALSE);
            g_string_append_printf(line, ",\"selected\":%s}", selected(source) ? "true" : "false");
            emit(out, line);
            g_string_free(line, TRUE);
            g_free(color);
        } else if (selected(source)) {
            Calendar *cal = g_new0(Calendar, 1);
            cal->source = source;
            cal->refresh = strcmp(cmd, "refresh") == 0;
            cal->from = from;
            cal->to = to;
            cal->local = local;
            cal->color = color_of(source);
            cal->out = g_string_new("");
            cal->thread = g_thread_new("calendar", work, cal);
            g_ptr_array_add(calendars, cal);
        }
    }
    for (guint i = 0; i < calendars->len; i++) {
        Calendar *cal = g_ptr_array_index(calendars, i);
        g_thread_join(cal->thread);
        g_string_append_len(out, cal->out->str, (gssize)cal->out->len);
        g_string_free(cal->out, TRUE);
        g_free(cal->color);
        g_free(cal);
    }
    g_ptr_array_free(calendars, TRUE);
    fwrite(out->str, 1, out->len, stdout);
    g_string_free(out, TRUE);
    g_list_free_full(sources, g_object_unref);
    g_object_unref(registry);
    fflush(stdout);
    return 0;
}
