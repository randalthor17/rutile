"""rutile-calendar (native/calendar.c, D95) against a real evolution-data-server on a private session bus, with
calendars of the test's own in a temporary home: repeats expanded, time zones and all-day events right, calendars
that are hidden or switched off left out, and the exit codes. Skipped without dbus-daemon or evolution-data-server
(pkg-config finds it in `nix develop`)."""
import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "build" / "rutile-calendar"


def eds_prefix():
    try:
        out = subprocess.run(["pkg-config", "--variable=prefix", "libedataserver-1.2"], capture_output=True,
                             text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    p = Path(out.stdout.strip())
    return p if out.returncode == 0 and (p / "share" / "dbus-1" / "services").is_dir() else None


SOURCE = """[Data Source]
DisplayName={name}
Enabled={enabled}
Parent=local-stub

[Calendar]
BackendName=local
Color=#3465a4
Selected={selected}
"""

ICS = """BEGIN:VCALENDAR
VERSION:2.0
PRODID:rutile-test
BEGIN:VEVENT
UID:weekly
SUMMARY:Weekly "quoted" \\, event
DTSTART:20261104T090000
DTEND:20261104T100000
RRULE:FREQ=WEEKLY;COUNT=3
END:VEVENT
BEGIN:VEVENT
UID:ny
SUMMARY:New York call
DTSTART;TZID=America/New_York:20261105T090000
DTEND;TZID=America/New_York:20261105T093000
END:VEVENT
BEGIN:VEVENT
UID:holiday
SUMMARY:Holiday
DTSTART;VALUE=DATE:20261106
DTEND;VALUE=DATE:20261107
END:VEVENT
END:VCALENDAR
"""


@unittest.skipUnless(shutil.which("dbus-daemon") and eds_prefix(), "needs dbus-daemon and evolution-data-server")
class CalendarHelper(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        prefix = eds_prefix()
        cls.tmp = Path(tempfile.mkdtemp(prefix="rcal"))
        services = cls.tmp / "services"
        services.mkdir()
        # D-Bus activation without systemd: the services' Exec lines
        for f in (prefix / "share" / "dbus-1" / "services").glob("*.service"):
            (services / f.name).write_text("".join(l for l in f.read_text().splitlines(True)
                                                   if not l.startswith("SystemdService")))
        conf = cls.tmp / "bus.conf"
        conf.write_text(f"""<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:path={cls.tmp}/bus</listen><servicedir>{services}</servicedir>
<policy context="default"><allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/></policy></busconfig>""")
        home = cls.tmp / "home"
        sources = home / "config" / "evolution" / "sources"
        sources.mkdir(parents=True)
        for uid, name, enabled, selected in [("shown", "Shown", "true", "true"), ("hidden", "Hidden", "true", "false"),
                                             ("off", "Off", "false", "true")]:
            (sources / f"{uid}.source").write_text(SOURCE.format(name=name, enabled=enabled, selected=selected))
            data = home / "data" / "evolution" / "calendar" / uid
            data.mkdir(parents=True)
            (data / "calendar.ics").write_text(ICS.replace("\n", "\r\n"))
        schemas = next((prefix / "share" / "gsettings-schemas").iterdir())
        cls.env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / "config"),
                       XDG_DATA_HOME=str(home / "data"), XDG_CACHE_HOME=str(home / "cache"),
                       XDG_RUNTIME_DIR=str(cls.tmp), DBUS_SESSION_BUS_ADDRESS=f"unix:path={cls.tmp}/bus",
                       GSETTINGS_BACKEND="memory", TZ="Asia/Dhaka",
                       XDG_DATA_DIRS=f"{schemas}:{os.environ.get('XDG_DATA_DIRS', '')}")
        # its own process group: the data server's processes it starts go with it
        cls.bus = subprocess.Popen(["dbus-daemon", "--nofork", f"--config-file={conf}"], env=cls.env,
                                   start_new_session=True)
        for _ in range(50):
            if (cls.tmp / "bus").exists():
                break
            time.sleep(0.1)

    @classmethod
    def tearDownClass(cls):
        os.killpg(cls.bus.pid, signal.SIGTERM)
        cls.bus.wait(10)
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def run_helper(self, *args, env=None):
        return subprocess.run([str(HELPER), *args], env=env or self.env, capture_output=True, text=True, timeout=60)

    @staticmethod
    def at(y, m, d, h=0, mi=0, tz=None):
        return int(datetime(y, m, d, h, mi, tzinfo=tz or timezone.utc).timestamp())

    def test_sources_lists_the_enabled_calendars(self):
        r = self.run_helper("sources")
        self.assertEqual(r.returncode, 0, r.stderr)
        rows = {s["source"]: s for s in map(json.loads, r.stdout.splitlines())}
        self.assertEqual(rows["shown"]["name"], "Shown")
        self.assertIs(rows["shown"]["selected"], True)
        self.assertIs(rows["hidden"]["selected"], False)
        self.assertNotIn("off", rows, "a calendar switched off is not listed")
        self.assertEqual(rows["shown"]["color"], "#3465a4")

    def test_events_expanded_in_their_zones(self):
        # Dhaka is UTC+6 all year: Nov 4 2026 local midnight is Nov 3 18:00 UTC
        r = self.run_helper("events", str(self.at(2026, 11, 3, 18)), str(self.at(2026, 12, 1)))
        self.assertEqual(r.returncode, 0, r.stderr)
        events = [json.loads(l) for l in r.stdout.splitlines()]
        self.assertEqual({e["source"] for e in events}, {"shown"}, "hidden and switched-off calendars left out")
        weekly = sorted(e["start"] for e in events if e["uid"] == "weekly")
        # a floating 09:00 is local (Dhaka) time: 03:00 UTC; COUNT=3
        self.assertEqual(weekly, [self.at(2026, 11, 4, 3), self.at(2026, 11, 11, 3), self.at(2026, 11, 18, 3)])
        w = next(e for e in events if e["uid"] == "weekly")
        self.assertEqual(w["title"], 'Weekly "quoted" , event', "escaped in JSON, iCalendar's escapes undone")
        self.assertEqual(w["end"] - w["start"], 3600)
        self.assertEqual(w["calendar"], "Shown")
        ny = next(e for e in events if e["uid"] == "ny")
        self.assertEqual(ny["start"], self.at(2026, 11, 5, 14), "09:00 in New York (EST, after Nov 1) is 14:00 UTC")
        self.assertIs(ny["allDay"], False)
        holiday = next(e for e in events if e["uid"] == "holiday")
        self.assertIs(holiday["allDay"], True)
        self.assertEqual(holiday["start"], self.at(2026, 11, 5, 18), "an all-day event from local midnight")
        self.assertEqual(holiday["end"] - holiday["start"], 86400)

    def test_range_leaves_out_other_times(self):
        r = self.run_helper("events", str(self.at(2026, 11, 10)), str(self.at(2026, 11, 12)))
        self.assertEqual([json.loads(l)["uid"] for l in r.stdout.splitlines()], ["weekly"])

    def test_refresh_and_bad_command_lines(self):
        self.assertEqual(self.run_helper("refresh").returncode, 0)
        for args in [(), ("events",), ("events", "10", "5"), ("events", "x", "20"), ("sources", "extra"), ("nope",)]:
            r = self.run_helper(*args)
            self.assertEqual(r.returncode, 1, args)
            self.assertIn("usage", r.stderr)

    def test_no_data_server(self):
        r = self.run_helper("sources", env=dict(self.env, DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent"))
        self.assertEqual(r.returncode, 2)
        self.assertEqual(r.stdout, "")


if __name__ == "__main__":
    unittest.main()
