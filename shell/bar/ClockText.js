// The clock pill's text. Kept apart so it is tested offscreen with fixed dates.
.pragma library

// "8:55" on a 12-hour clock (no AM/PM, as Googlebook shows it), "20:55" on a 24-hour one.
function time(d, use24h) {
    var h = d.getHours(), m = d.getMinutes();
    if (!use24h) h = h % 12 === 0 ? 12 : h % 12;
    return (use24h && h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
}

// "Fri, Oct 9" in English; the locale's day and month names otherwise.
function date(d, locale) {
    return locale.toString(d, "ddd, MMM d");
}

// Whether a locale's short time format (e.g. "h:mm AP" or "HH:mm") is a 24-hour clock.
function uses24h(format) {
    return !/a/i.test(format);
}
