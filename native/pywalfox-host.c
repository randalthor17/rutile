/*
 * rutile-pywalfox-host: Rutile Shell's native-messaging host for the Pywalfox Firefox extension (D52, D54).
 *
 * Firefox starts it (the manifest the shell installs while Firefox's colors are on) and talks to it over stdin
 * and stdout: each message is a 32-bit length in native byte order, then that many bytes of UTF-8 JSON. It
 * answers the extension's requests (debug:version, action:colors; the custom-CSS ones are refused, saying so)
 * with the 16 colors the shell renders into $XDG_CACHE_HOME/rutile/pywalfox.conf, and sends the colors again,
 * with the dark or light mode, whenever that file changes, so a new wallpaper reaches Firefox at once.
 * Written from Pywalfox's protocol (pywalfox-native 2.9, MPL-2.0); none of its code.
 *
 * Built to be hard to break: one thread (poll() on stdin, with a timeout to look at the file); every read and
 * write loops until done and retries on EINTR; a message longer than MAX_MESSAGE ends the host (the stream
 * cannot be trusted after it); the JSON reader is strict, bounded in depth, and only ever indexes inside the
 * message it was given; every string sent is escaped and made valid UTF-8; nothing is written with stdio, so
 * no buffer can hold half a message. The colors file is plain lines ("color3 #aabbcc"), not JSON.
 * Exit status: 0 when Firefox closes stdin, 1 on an I/O error or a message it cannot frame.
 */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define VERSION "2.9.0"              /* the protocol version the extension expects */
#define MAX_MESSAGE (1u << 20)       /* the extension's messages are a few dozen bytes */
#define MAX_DEPTH 64
#define MAX_FIELD 256                /* longest action or target kept; longer ones are not ours */
#define MAX_FILE ((size_t)64 * 1024)
#define NCOLORS 16

/* ---- a growing output buffer; a failed allocation marks it, and it is then never sent ---- */

typedef struct {
    char *p;
    size_t len, cap;
    int failed;
} buf;

static void put(buf *b, const char *s, size_t n) {
    if (b->failed) return;
    if (n > SIZE_MAX - b->len - 1) { b->failed = 1; return; }
    if (b->len + n + 1 > b->cap) {
        size_t cap = b->cap ? b->cap : 256;
        while (cap < b->len + n + 1) {
            if (cap > SIZE_MAX / 2) { b->failed = 1; return; }
            cap *= 2;
        }
        char *p = realloc(b->p, cap);
        if (!p) { b->failed = 1; return; }
        b->p = p;
        b->cap = cap;
    }
    memcpy(b->p + b->len, s, n);
    b->len += n;
    b->p[b->len] = '\0';
}

static void puts_(buf *b, const char *s) { put(b, s, strlen(s)); }

/* Length of the valid UTF-8 sequence at s (n bytes left), or 0 if it is not one. */
static size_t utf8_len(const unsigned char *s, size_t n) {
    unsigned char c = s[0];
    size_t len;
    uint32_t cp;
    if (c < 0x80) return 1;
    if (c >= 0xc2 && c <= 0xdf) { len = 2; cp = c & 0x1f; }
    else if (c >= 0xe0 && c <= 0xef) { len = 3; cp = c & 0x0f; }
    else if (c >= 0xf0 && c <= 0xf4) { len = 4; cp = c & 0x07; }
    else return 0;
    if (n < len) return 0;
    for (size_t i = 1; i < len; i++) {
        if ((s[i] & 0xc0) != 0x80) return 0;
        cp = (cp << 6) | (s[i] & 0x3f);
    }
    if ((len == 3 && (cp < 0x800 || (cp >= 0xd800 && cp <= 0xdfff))) || (len == 4 && (cp < 0x10000 || cp > 0x10ffff)))
        return 0;
    return len;
}

/* A JSON string: quoted, escaped, and valid UTF-8 (a byte that is not becomes U+FFFD). */
static void put_json_string(buf *b, const char *s) {
    const unsigned char *u = (const unsigned char *)s;
    size_t n = strlen(s);
    put(b, "\"", 1);
    for (size_t i = 0; i < n;) {
        unsigned char c = u[i];
        if (c == '"' || c == '\\') {
            char esc[2] = {'\\', (char)c};
            put(b, esc, 2);
            i++;
        } else if (c < 0x20 || c == 0x7f) {
            char esc[8];
            snprintf(esc, sizeof esc, "\\u%04x", c);
            puts_(b, esc);
            i++;
        } else {
            size_t len = utf8_len(u + i, n - i);
            if (len == 0) { puts_(b, "\\ufffd"); i++; }
            else { put(b, s + i, len); i += len; }
        }
    }
    put(b, "\"", 1);
}

/* ---- I/O that finishes what it starts ---- */

/* 1: all n bytes read; 0: end of input before the first byte; -1: an error, or the input ended part-way. */
static int read_full(int fd, void *p, size_t n) {
    size_t got = 0;
    while (got < n) {
        ssize_t r = read(fd, (char *)p + got, n - got);
        if (r < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (r == 0) return got == 0 ? 0 : -1;
        got += (size_t)r;
    }
    return 1;
}

static int write_full(int fd, const void *p, size_t n) {
    size_t done = 0;
    while (done < n) {
        ssize_t w = write(fd, (const char *)p + done, n - done);
        if (w < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        done += (size_t)w;
    }
    return 0;
}

/* One message to Firefox; -1 if it could not be written (the host then stops: Firefox has gone). */
static int send_message(const buf *b) {
    if (b->failed || b->len > UINT32_MAX) return -1;
    uint32_t len = (uint32_t)b->len;
    unsigned char head[4];
    memcpy(head, &len, 4);               /* native byte order, as the protocol says */
    if (write_full(STDOUT_FILENO, head, 4) < 0) return -1;
    return write_full(STDOUT_FILENO, b->p, b->len);
}

/* ---- a strict, bounded JSON reader: checks the whole message, keeps two top-level string members ---- */

typedef struct {
    const unsigned char *s;
    size_t n, i;
    int depth;
} reader;

static void skip_ws(reader *r) {
    while (r->i < r->n && (r->s[r->i] == ' ' || r->s[r->i] == '\t' || r->s[r->i] == '\n' || r->s[r->i] == '\r')) r->i++;
}

static int hex4(reader *r, uint32_t *out) {
    if (r->n - r->i < 4) return -1;
    uint32_t v = 0;
    for (int k = 0; k < 4; k++) {
        unsigned char c = r->s[r->i++];
        v <<= 4;
        if (c >= '0' && c <= '9') v |= (uint32_t)(c - '0');
        else if (c >= 'a' && c <= 'f') v |= (uint32_t)(c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') v |= (uint32_t)(c - 'A' + 10);
        else return -1;
    }
    *out = v;
    return 0;
}

/* Appends cp as UTF-8 to out (cap bytes, always NUL-terminated); sets *too_long when it does not fit. */
static void emit(char *out, size_t cap, size_t *len, int *too_long, uint32_t cp) {
    char tmp[4];
    size_t k;
    if (cp < 0x80) { tmp[0] = (char)cp; k = 1; }
    else if (cp < 0x800) { tmp[0] = (char)(0xc0 | (cp >> 6)); tmp[1] = (char)(0x80 | (cp & 0x3f)); k = 2; }
    else if (cp < 0x10000) {
        tmp[0] = (char)(0xe0 | (cp >> 12)); tmp[1] = (char)(0x80 | ((cp >> 6) & 0x3f));
        tmp[2] = (char)(0x80 | (cp & 0x3f)); k = 3;
    } else {
        tmp[0] = (char)(0xf0 | (cp >> 18)); tmp[1] = (char)(0x80 | ((cp >> 12) & 0x3f));
        tmp[2] = (char)(0x80 | ((cp >> 6) & 0x3f)); tmp[3] = (char)(0x80 | (cp & 0x3f)); k = 4;
    }
    if (!out) return;
    if (*len + k + 1 > cap) { *too_long = 1; return; }
    memcpy(out + *len, tmp, k);
    *len += k;
    out[*len] = '\0';
}

/* A string at r->i (the opening quote). Decoded into out when out is not NULL; *too_long if it did not fit. */
static int parse_string(reader *r, char *out, size_t cap, int *too_long) {
    size_t len = 0;
    int dummy = 0;
    if (!too_long) too_long = &dummy;
    *too_long = 0;
    if (out && cap) out[0] = '\0';
    if (r->i >= r->n || r->s[r->i] != '"') return -1;
    r->i++;
    while (r->i < r->n) {
        unsigned char c = r->s[r->i];
        if (c == '"') { r->i++; return 0; }
        if (c < 0x20) return -1;
        if (c == '\\') {
            r->i++;
            if (r->i >= r->n) return -1;
            unsigned char e = r->s[r->i++];
            uint32_t cp;
            switch (e) {
            case '"': cp = '"'; break;
            case '\\': cp = '\\'; break;
            case '/': cp = '/'; break;
            case 'b': cp = '\b'; break;
            case 'f': cp = '\f'; break;
            case 'n': cp = '\n'; break;
            case 'r': cp = '\r'; break;
            case 't': cp = '\t'; break;
            case 'u':
                if (hex4(r, &cp) < 0) return -1;
                if (cp >= 0xd800 && cp <= 0xdbff) {           /* a surrogate pair */
                    uint32_t lo;
                    if (r->n - r->i < 6 || r->s[r->i] != '\\' || r->s[r->i + 1] != 'u') return -1;
                    r->i += 2;
                    if (hex4(r, &lo) < 0 || lo < 0xdc00 || lo > 0xdfff) return -1;
                    cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00);
                } else if (cp >= 0xdc00 && cp <= 0xdfff) {
                    return -1;                                  /* a lone low surrogate */
                }
                break;
            default:
                return -1;
            }
            emit(out, cap, &len, too_long, cp);
        } else {
            size_t k = utf8_len(r->s + r->i, r->n - r->i);
            if (k == 0) return -1;
            if (out) {
                if (len + k + 1 > cap) *too_long = 1;
                else { memcpy(out + len, r->s + r->i, k); len += k; out[len] = '\0'; }
            }
            r->i += k;
        }
    }
    return -1;
}

static int parse_value(reader *r);

static int parse_number(reader *r) {
    size_t start = r->i;
    if (r->i < r->n && r->s[r->i] == '-') r->i++;
    if (r->i >= r->n) return -1;
    if (r->s[r->i] == '0') r->i++;
    else if (r->s[r->i] >= '1' && r->s[r->i] <= '9') while (r->i < r->n && r->s[r->i] >= '0' && r->s[r->i] <= '9') r->i++;
    else return -1;
    if (r->i < r->n && r->s[r->i] == '.') {
        r->i++;
        size_t d = r->i;
        while (r->i < r->n && r->s[r->i] >= '0' && r->s[r->i] <= '9') r->i++;
        if (r->i == d) return -1;
    }
    if (r->i < r->n && (r->s[r->i] == 'e' || r->s[r->i] == 'E')) {
        r->i++;
        if (r->i < r->n && (r->s[r->i] == '+' || r->s[r->i] == '-')) r->i++;
        size_t d = r->i;
        while (r->i < r->n && r->s[r->i] >= '0' && r->s[r->i] <= '9') r->i++;
        if (r->i == d) return -1;
    }
    return r->i > start ? 0 : -1;
}

static int parse_literal(reader *r, const char *word) {
    size_t k = strlen(word);
    if (r->n - r->i < k || memcmp(r->s + r->i, word, k) != 0) return -1;
    r->i += k;
    return 0;
}

/* An object or array, at r->i. For the top-level object (want != NULL), the string members named "action" and
   "target" are kept in want[0] and want[1] (MAX_FIELD bytes each). */
static int parse_container(reader *r, char want[2][MAX_FIELD], int *have) {
    unsigned char open = r->s[r->i];
    unsigned char close = open == '{' ? '}' : ']';
    if (++r->depth > MAX_DEPTH) return -1;
    r->i++;
    skip_ws(r);
    if (r->i < r->n && r->s[r->i] == close) { r->i++; r->depth--; return 0; }
    for (;;) {
        int slot = -1;
        if (open == '{') {
            char key[16];
            int too_long;
            skip_ws(r);
            if (parse_string(r, key, sizeof key, &too_long) < 0) return -1;
            if (want && !too_long) {
                if (strcmp(key, "action") == 0) slot = 0;
                else if (strcmp(key, "target") == 0) slot = 1;
            }
            skip_ws(r);
            if (r->i >= r->n || r->s[r->i] != ':') return -1;
            r->i++;
        }
        skip_ws(r);
        if (slot >= 0 && r->i < r->n && r->s[r->i] == '"') {
            int too_long;
            if (parse_string(r, want[slot], MAX_FIELD, &too_long) < 0) return -1;
            if (too_long) {
                want[slot][0] = '\0';
                *have &= ~(1 << slot);
            } else {
                *have |= 1 << slot;
            }
        } else {
            if (slot >= 0) *have &= ~(1 << slot);      /* not a string: not one we can use */
            if (parse_value(r) < 0) return -1;
        }
        skip_ws(r);
        if (r->i >= r->n) return -1;
        if (r->s[r->i] == ',') { r->i++; continue; }
        if (r->s[r->i] == close) { r->i++; r->depth--; return 0; }
        return -1;
    }
}

static int parse_value(reader *r) {
    skip_ws(r);
    if (r->i >= r->n) return -1;
    switch (r->s[r->i]) {
    case '{':
    case '[': return parse_container(r, NULL, NULL);
    case '"': return parse_string(r, NULL, 0, NULL);
    case 't': return parse_literal(r, "true");
    case 'f': return parse_literal(r, "false");
    case 'n': return parse_literal(r, "null");
    default: return parse_number(r);
    }
}

/* The message's "action" (and "target"), or -1 if it is not a JSON object with a string action. */
static int read_request(const unsigned char *msg, size_t n, char action[MAX_FIELD], char target[MAX_FIELD]) {
    reader r = {msg, n, 0, 0};
    char want[2][MAX_FIELD] = {{0}, {0}};
    int have = 0;
    skip_ws(&r);
    if (r.i >= r.n || r.s[r.i] != '{') return -1;
    if (parse_container(&r, want, &have) < 0) return -1;
    skip_ws(&r);
    if (r.i != r.n || !(have & 1)) return -1;
    memcpy(action, want[0], MAX_FIELD);
    memcpy(target, (have & 2) ? want[1] : "", (have & 2) ? MAX_FIELD : 1);
    return 0;
}

/* ---- the colors file: "mode dark", "wallpaper /path", "color0 #rrggbb" ... "color15 #rrggbb" ---- */

typedef struct {
    char colors[NCOLORS][8];
    char mode[8];
    char wallpaper[PATH_MAX];
} palette;

static int is_hex_color(const char *s, size_t n) {
    if (n != 7 || s[0] != '#') return 0;
    for (size_t i = 1; i < 7; i++) {
        char c = s[i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return 0;
    }
    return 1;
}

/* 0 and *p filled, or -1 with a reason in err. */
static int load_palette(const char *path, palette *p, char *err, size_t errcap) {
    memset(p, 0, sizeof *p);
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) { snprintf(err, errcap, "No colors from Rutile Shell yet (%s: %s)", path, strerror(errno)); return -1; }
    char *text = malloc(MAX_FILE + 1);
    if (!text) { close(fd); snprintf(err, errcap, "out of memory"); return -1; }
    size_t len = 0;
    for (;;) {
        ssize_t r = read(fd, text + len, MAX_FILE + 1 - len);
        if (r < 0) {
            if (errno == EINTR) continue;
            snprintf(err, errcap, "could not read %s: %s", path, strerror(errno));
            close(fd); free(text); return -1;
        }
        if (r == 0) break;
        len += (size_t)r;
        if (len > MAX_FILE) { snprintf(err, errcap, "%s is too large", path); close(fd); free(text); return -1; }
    }
    close(fd);
    text[len] = '\0';
    if (memchr(text, '\0', len)) { snprintf(err, errcap, "%s is not text", path); free(text); return -1; }

    unsigned have = 0;
    char *line = text;
    while (line && *line) {
        char *next = strchr(line, '\n');
        if (next) *next++ = '\0';
        size_t n = strlen(line);
        if (n && line[n - 1] == '\r') line[--n] = '\0';
        char *sp = strchr(line, ' ');
        if (line[0] != '#' && sp) {
            *sp = '\0';
            const char *key = line, *val = sp + 1;
            size_t vn = strlen(val);
            if (strncmp(key, "color", 5) == 0 && key[5] >= '0' && key[5] <= '9') {
                char *end;
                long i = strtol(key + 5, &end, 10);
                if (*end == '\0' && i >= 0 && i < NCOLORS && is_hex_color(val, vn)) {
                    memcpy(p->colors[i], val, 8);
                    have |= 1u << i;
                }
            } else if (strcmp(key, "mode") == 0 && (strcmp(val, "dark") == 0 || strcmp(val, "light") == 0)) {
                memcpy(p->mode, val, vn + 1);
            } else if (strcmp(key, "wallpaper") == 0 && vn < sizeof p->wallpaper) {
                memcpy(p->wallpaper, val, vn + 1);
            }
        }
        line = next;
    }
    free(text);
    if (have != (1u << NCOLORS) - 1) {
        snprintf(err, errcap, "%s does not have all 16 colors", path);
        return -1;
    }
    return 0;
}

/* ---- the replies ---- */

static int reply_simple(const char *action, int success, const char *data, const char *error) {
    buf b = {0};
    puts_(&b, "{\"action\":");
    put_json_string(&b, action);
    puts_(&b, success ? ",\"success\":true" : ",\"success\":false");
    if (data) { puts_(&b, ",\"data\":"); put_json_string(&b, data); }
    if (error) { puts_(&b, ",\"error\":"); put_json_string(&b, error); }
    puts_(&b, "}");
    int rc = send_message(&b);
    free(b.p);
    return rc;
}

/* The colors (and the mode, when the file says one). */
static int send_colors(const char *path) {
    palette p;
    char err[PATH_MAX + 128];
    if (load_palette(path, &p, err, sizeof err) < 0) return reply_simple("action:colors", 0, NULL, err);
    buf b = {0};
    puts_(&b, "{\"action\":\"action:colors\",\"success\":true,\"data\":{\"colors\":[");
    for (int i = 0; i < NCOLORS; i++) {
        if (i) puts_(&b, ",");
        put_json_string(&b, p.colors[i]);
    }
    puts_(&b, "],\"wallpaper\":");
    put_json_string(&b, p.wallpaper);
    puts_(&b, "}}");
    int rc = send_message(&b);
    free(b.p);
    if (rc == 0 && p.mode[0]) rc = reply_simple("theme:mode", 1, p.mode, NULL);
    return rc;
}

static int handle(const unsigned char *msg, size_t n, const char *path) {
    char action[MAX_FIELD], target[MAX_FIELD];
    if (read_request(msg, n, action, target) < 0) return reply_simple("action:invalid", 0, NULL, NULL);
    if (strcmp(action, "debug:version") == 0) return reply_simple("debug:version", 1, VERSION, NULL);
    if (strcmp(action, "action:colors") == 0) return send_colors(path);
    if (strcmp(action, "css:enable") == 0 || strcmp(action, "css:disable") == 0 || strcmp(action, "css:font:size") == 0)
        return reply_simple(action, 0, target[0] ? target : NULL, "Rutile Shell's host does not change Firefox's CSS");
    return reply_simple("action:invalid", 0, NULL, NULL);
}

/* ---- watching the file ---- */

typedef struct {
    int exists;
    struct timespec mtime;
    off_t size;
    ino_t ino;
} stamp;

static stamp file_stamp(const char *path) {
    stamp s = {0};
    struct stat st;
    if (stat(path, &st) == 0) {
        s.exists = 1;
        s.mtime = st.st_mtim;
        s.size = st.st_size;
        s.ino = st.st_ino;
    }
    return s;
}

static int same_stamp(stamp a, stamp b) {
    return a.exists == b.exists && a.mtime.tv_sec == b.mtime.tv_sec && a.mtime.tv_nsec == b.mtime.tv_nsec &&
           a.size == b.size && a.ino == b.ino;
}

static long long now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static int colors_path(char *out, size_t cap) {
    const char *cache = getenv("XDG_CACHE_HOME");
    const char *home = getenv("HOME");
    int n;
    if (cache && cache[0] == '/') n = snprintf(out, cap, "%s/rutile/pywalfox.conf", cache);
    else if (home && home[0] == '/') n = snprintf(out, cap, "%s/.cache/rutile/pywalfox.conf", home);
    else return -1;
    return n > 0 && (size_t)n < cap ? 0 : -1;
}

static int poll_interval_ms(void) {
    const char *s = getenv("RUTILE_PYWALFOX_POLL");
    if (!s || !*s) return 1000;
    char *end;
    double v = strtod(s, &end);
    if (*end != '\0' || !(v >= 0.01 && v <= 60)) return 1000;
    return (int)(v * 1000);
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);            /* Firefox gone: write fails with EPIPE, and the host stops */
    char path[PATH_MAX];
    if (colors_path(path, sizeof path) < 0) snprintf(path, sizeof path, "/nonexistent/rutile/pywalfox.conf");
    const int interval = poll_interval_ms();
    stamp seen = file_stamp(path);
    long long next = now_ms() + interval;

    for (;;) {
        long long wait = next - now_ms();
        struct pollfd in = {STDIN_FILENO, POLLIN, 0};
        int r = poll(&in, 1, wait > 0 ? (int)wait : 0);
        if (r < 0) {
            if (errno == EINTR) continue;
            return 1;
        }
        if (now_ms() >= next) {
            stamp now = file_stamp(path);
            if (!same_stamp(now, seen) && now.exists && send_colors(path) < 0) return 1;
            seen = now;
            next = now_ms() + interval;
        }
        if (r == 0) continue;
        if (in.revents & POLLNVAL) return 1;
        if (!(in.revents & (POLLIN | POLLHUP | POLLERR))) continue;

        unsigned char head[4];
        int got = read_full(STDIN_FILENO, head, 4);
        if (got == 0) return 0;          /* Firefox closed the pipe: done */
        if (got < 0) return 1;
        uint32_t len;
        memcpy(&len, head, 4);
        if (len > MAX_MESSAGE) return 1; /* not ours to read: the stream cannot be framed after it */
        unsigned char *msg = malloc(len ? len : 1);
        if (!msg) return 1;
        if (len && read_full(STDIN_FILENO, msg, len) != 1) { free(msg); return 1; }
        int rc = handle(msg, len, path);
        free(msg);
        if (rc < 0) return 1;
    }
}
