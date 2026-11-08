#!/usr/bin/env python3
"""
fprintd-led-watchdog.py
Listens for screen unlock, fingerprint verification match, and session startup.
Immediately stops fprintd so Goodix 27c6:6594 LED resets from green to white
without waiting for the 30-second idle timeout, enabling USB low-power suspend.
"""

import sys
import time
import threading
import subprocess
import gi
from gi.repository import Gio, GLib

def stop_fprintd_worker(delay):
    if delay > 0:
        time.sleep(delay)
    res = subprocess.run(
        ["systemctl", "is-active", "--quiet", "fprintd"],
        capture_output=True
    )
    if res.returncode == 0:
        subprocess.run(
            ["systemctl", "stop", "fprintd"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

def trigger_stop(delay=0.3):
    t = threading.Thread(target=stop_fprintd_worker, args=(delay,), daemon=True)
    t.start()

def on_screensaver_signal(conn, sender, path, iface, signal, params, user_data):
    try:
        is_active = params.get_child_value(0).get_boolean()
        if not is_active:
            trigger_stop(delay=0.3)
    except Exception:
        pass

def on_login1_unlock(conn, sender, path, iface, signal, params, user_data):
    trigger_stop(delay=0.3)

def on_fprint_verify_status(conn, sender, path, iface, signal, params, user_data):
    try:
        result = params.get_child_value(0).get_string()
        done = params.get_child_value(1).get_boolean()
        if done and result == "verify-match":
            trigger_stop(delay=0.8)
    except Exception:
        pass

def main():
    loop = GLib.MainLoop()

    # On session start (after SDDM login), allow 2.5s for SDDM PAM to cleanly finalize
    trigger_stop(delay=2.5)

    try:
        session_bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        session_bus.signal_subscribe(
            None,
            "org.freedesktop.ScreenSaver",
            "ActiveChanged",
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            on_screensaver_signal,
            None
        )
    except Exception as e:
        sys.stderr.write(f"Warning: Failed to connect to session bus: {e}\n")

    try:
        system_bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        system_bus.signal_subscribe(
            None,
            "org.freedesktop.login1.Session",
            "Unlock",
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            on_login1_unlock,
            None
        )
        system_bus.signal_subscribe(
            None,
            "net.reactivated.Fprint.Device",
            "VerifyStatus",
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            on_fprint_verify_status,
            None
        )
    except Exception as e:
        sys.stderr.write(f"Warning: Failed to connect to system bus: {e}\n")

    loop.run()

if __name__ == "__main__":
    main()
