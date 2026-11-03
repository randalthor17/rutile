// What Night light runs (D91), as plain data so it tests offscreen. wlsunset moves between a day and a night
// temperature by the sun; it has no "always on". `o`: {temperature (K), schedule (bool), latitude, longitude (numbers
// or null: the weather place), sunset, sunrise ("HH:MM")}.
.pragma library

var DAYLIGHT = 6500;            // wlsunset's own day temperature: the screen untouched

function command(o) {
    var t = Math.round(o.temperature);
    // all day: the night temperature, and one kelvin more for the day
    if (!o.schedule) return ["wlsunset", "-t", String(t), "-T", String(t + 1)];
    var day = ["wlsunset", "-t", String(t), "-T", String(Math.max(DAYLIGHT, t + 1))];
    // sunset to sunrise: the sun's times at the weather place, or the times set by hand without one
    if (typeof o.latitude === "number" && typeof o.longitude === "number")
        return day.concat(["-l", String(o.latitude), "-L", String(o.longitude)]);
    return day.concat(["-S", o.sunrise, "-s", o.sunset]);
}
