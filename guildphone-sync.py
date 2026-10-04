#!/usr/bin/env python3
"""GuildPhone companion - keeps a guild roster in sync automatically.

WoW addons have NO network access: no HTTP, no sockets, not even to localhost.
The only way roster data leaves the game is a file the client writes. So the
addon serialises the roster into SavedVariables at logout, and this watches that
file and uploads it. The officer does nothing.

Consequence worth knowing: the client only flushes SavedVariables on /reload,
logout or exit. So a sync happens at session boundaries, not live. That is
plenty for roster membership, which is what this is for.

stdlib only - no pip install, runs anywhere Python does.

Windows: install Python from the Microsoft Store (search "Python 3", or just
type `python` in Terminal and Windows offers it), then run this script the
same way macOS and Linux do. There is no .exe and there is not going to be
one: an unsigned download is a "Windows protected your PC" box between a
stranger and a product they already suspect, and a readable script you can
open in Notepad is the whole point of this being public.
"""
import argparse, json, os, re, sys, time, urllib.error, urllib.request
from pathlib import Path

DEFAULT_URL = "https://guildphone.com"

WOW_HINTS = [
    r"C:\Program Files (x86)\World of Warcraft",
    r"C:\Program Files\World of Warcraft",
    "/Applications/World of Warcraft",
    str(Path.home() / "Applications/World of Warcraft"),
]

def find_saved_variables(root=None):
    """Locate every GuildPhone.lua under WTF/Account/*/SavedVariables/."""
    roots = [Path(root)] if root else [Path(p) for p in WOW_HINTS if Path(p).exists()]
    found = []
    for r in roots:
        if not r.exists():
            continue
        # the flavour directory varies (_classic_era_, _retail_, Forever...)
        found += list(r.glob("*/WTF/Account/*/SavedVariables/GuildPhone.lua"))
        found += list(r.glob("WTF/Account/*/SavedVariables/GuildPhone.lua"))
    return sorted(set(found))

_LUA_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}

def _unescape(s):
    out, i = [], 0
    while i < len(s):
        ch = s[i]
        if ch == "\\" and i + 1 < len(s):
            nxt = s[i+1]
            if nxt in _LUA_ESCAPES:
                out.append(_LUA_ESCAPES[nxt]); i += 2; continue
            if nxt.isdigit():                      # \ddd decimal escape
                j = i + 1
                while j < len(s) and j < i + 4 and s[j].isdigit():
                    j += 1
                out.append(chr(int(s[i+1:j]))); i = j; continue
        out.append(ch); i += 1
    return "".join(out)

def extract_export(text):
    """Pull the NEWEST GP1 export out of the SavedVariables Lua.

    A file holds more than one: /gp claim and /gp enroll write
    GuildPhoneDB.export, the automatic exporter writes
    GuildPhoneDB.auto.export. Lua tables have no order and WoW serialises
    keys in hash order, so taking the first match uploaded whichever one
    the hash happened to put first - which for a given file does not
    change, so the same stale export went up every time.

    Field five of the GP1 header is when the addon built it. Mirrors
    export_from_savedvariables in the portal: the automated route and the
    manual one must not disagree about which export a file contains.
    """
    best, best_at, best_claims = None, None, False
    seen = set()
    for pat in (r'\["export"\]\s*=\s*"((?:[^"\\]|\\.)*)"',
                r'\bexport\s*=\s*"((?:[^"\\]|\\.)*)"'):
        for m in re.finditer(pat, text, re.S):
            body = _unescape(m.group(1))
            if not body.startswith("GP1|") or body in seen:
                continue
            seen.add(body)
            head = body.split("\n", 1)[0].split("|")
            try:
                at = int(head[4])
            except (IndexError, ValueError):
                at = -1
            claims = len(head) >= 7 and head[6] != ""
            if best is None or (at, claims) > (best_at, best_claims):
                best, best_at, best_claims = body, at, claims
    return best

def upload(url, token, roster):
    req = urllib.request.Request(url.rstrip("/") + "/api/roster",
                                 data=roster.encode("utf-8"), method="POST")
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Content-Type", "text/plain; charset=utf-8")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read().decode())
        except Exception:
            return {"ok": False, "error": f"HTTP {e.code}"}
    except Exception as e:
        return {"ok": False, "error": str(e)}

STATE_FILE = Path.home() / ".guildphone-sync.json"
TOKEN_FILE = Path.home() / ".guildphone-token"

# The loop is a service now, so every failure mode has to be survivable:
# the server can be down, the game can be uninstalled, a second WoW install
# can appear tomorrow. None of those may stop it watching.
RESCAN_SECONDS = 300          # look for new SavedVariables paths this often
BACKOFF_MAX_SECONDS = 900     # a dead server is retried at most every 15 min


def log(msg):
    """Line-buffered output with a clock, because this ends up in a log file.

    Service managers capture stdout and a block-buffered pipe means the log
    stays empty for hours - which looks exactly like a process doing nothing.
    """
    print(f"[gp {time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)


def load_state():
    """Persisted so a re-run does not re-upload an unchanged roster. Imports are
    idempotent, so a redundant upload is harmless - just wasteful and noisy."""
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {}

def save_state(state):
    try:
        STATE_FILE.write_text(json.dumps(state))
    except Exception as e:
        log(f"could not save state: {e}")


def backoff_seconds(base, failures):
    """How long to wait before the next pass, given consecutive failed passes.

    The loop used to sleep a flat interval whatever happened. With nobody
    watching it that is a log line every 30 seconds for as long as the server
    is down. Doubling, capped, keeps a real outage to four lines an hour and
    still retries a blip almost immediately.
    """
    if failures <= 0:
        return base
    return min(base * (2 ** min(failures, 20)), BACKOFF_MAX_SECONDS)


def sync_once(path, url, token, state, quiet=False):
    """Upload this file's newest export if it has changed. Returns a status.

    "unchanged" nothing to do | "empty" no export in the file yet
    "ok" uploaded | "failed" the upload did not land

    The mtime is only recorded once the upload has actually landed. It used
    to be recorded before the request, so a failed upload marked the file as
    done: a five-second server blip lost that roster until the player next
    logged out, and nothing retried it.
    """
    try:
        mtime = path.stat().st_mtime
    except OSError:
        return "unchanged"
    if state.get(str(path)) == mtime:
        return "unchanged"
    text = path.read_text(encoding="utf-8", errors="replace")
    roster = extract_export(text)
    if not roster:
        # Nothing to retry: the file is real and holds no export.
        state[str(path)] = mtime
        if not quiet:
            log(f"{path.name}: no roster yet (log out once so the game writes it)")
        return "empty"
    res = upload(url, token, roster)
    if not res.get("ok"):
        if not quiet:
            log(f"upload failed: {res.get('error')}")
        return "failed"
    state[str(path)] = mtime
    save_state(state)
    log(f"synced {res.get('guild')} - {res.get('members')} members"
        + (f", {res['departed']} departed" if res.get("departed") else "")
        + f" (guild {res.get('tenant')}, {res.get('state')})")
    return "ok"


def announce(paths, url):
    if paths:
        log(f"watching {len(paths)} file(s), uploading to {url}")
        for p in paths:
            log(f"  {p}")
    else:
        log("no GuildPhone.lua anywhere yet - install the addon and log out "
            "once. Still watching; nothing to do until then.")


def run_loop(url, token, wow, interval, state, passes=None):
    """Watch for ever. `passes` bounds the loop for the test suite only."""
    paths = find_saved_variables(wow)
    announce(paths, url)
    last_scan = time.monotonic()
    failures, last_error, n = 0, None, 0
    while passes is None or n < passes:
        n += 1
        if time.monotonic() - last_scan >= RESCAN_SECONDS:
            last_scan = time.monotonic()
            try:
                fresh = find_saved_variables(wow)
            except Exception as e:
                log(f"rescan failed: {e}")
                fresh = paths
            if fresh != paths:
                paths = fresh
                announce(paths, url)
        failed = None
        for p in paths:
            # One unreadable file must not stop the others syncing: a second
            # WoW install with a permissions problem used to take the whole
            # loop down with it, including the install that was working.
            try:
                if sync_once(p, url, token, state, quiet=True) == "failed":
                    failed = "upload failed"
            except Exception as e:
                failed = f"{p.name}: {e}"
        if failed:
            failures += 1
            if failed != last_error:          # do not repeat an unchanged fault
                log(f"{failed} - retrying in {backoff_seconds(interval, failures)}s")
            last_error = failed
        else:
            if last_error:
                log("recovered")
            failures, last_error = 0, None
        time.sleep(backoff_seconds(interval, failures))


# ------------------------------------------------------------------ install
#
# This writes an autostart entry, which is the single most suspicious thing a
# downloaded script can do. So it is per-user (never system-wide, never asks
# for administrator or sudo), it prints the exact file and the exact command
# before it runs either, and --uninstall removes those two things and nothing
# else. Anybody can read the file afterwards and see it is twenty lines.

SERVICE_NAME = "guildphone-sync"


def platform_key():
    if sys.platform.startswith("win"):
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    return "linux"


def _runner(exe=None, plat=None):
    """The absolute interpreter path to start the service with.

    sys.executable is authoritative and is used on every platform. The
    installer is running under the very interpreter that will run the
    service, so there is nothing to guess and nothing to look up on PATH -
    which matters, because the PATH a launch agent or a scheduled task gets
    is not the PATH the player had in their terminal.

    On Windows the recommended Python is the Microsoft Store one, which runs
    behind an execution alias in WindowsApps. Whether Task Scheduler resolves
    that alias is not something this project has confirmed either way, and
    writing the resolved path means it never has to.

    pythonw.exe is the same interpreter with no console window. It is a
    DIFFERENT FILE, not a flag, and a Store Python does not lay its files out
    the way a python.org one does - so each candidate is checked on disk and
    sys.executable is used unchanged when none is there. A console window is
    ugly; a task pointing at a filename that was only ever guessed does not
    run at all.
    """
    exe = Path(exe or sys.executable)
    plat = plat or platform_key()
    if plat != "windows":
        return str(exe)
    for cand in (exe.with_name(exe.name.replace("python", "pythonw", 1)),
                 exe.with_name("pythonw.exe")):
        if cand.name != exe.name and cand.exists():
            return str(cand)
    return str(exe)


def _q(a):
    """Quote one argument for cmd.exe.

    Every argument, unconditionally. A WoW folder with a space in it is the
    normal case and not the exotic one - the default install is
    C:\\Program Files (x86)\\World of Warcraft, which also carries the
    parentheses cmd.exe treats specially - and the home directory under which
    the .cmd itself is written is "C:\\Users\\John Smith" for a great many
    people. Quoting only the arguments that look dangerous is a rule with
    exceptions; quoting all of them has none.
    """
    return '"%s"' % a


def service_plan(url, wow, home=None, plat=None, script=None, runner=None):
    """What --install would write and run. Pure, so it can be shown and tested.

    Returns {path, body, register, unregister, note}. `path` is the file the
    user can go and read; `register` / `unregister` are argv lists.
    """
    home = Path(home) if home else Path.home()
    plat = plat or platform_key()
    script = script or str(Path(__file__).resolve())
    runner = runner or _runner(plat=plat)
    args = [runner, script, "--url", url]
    if wow:
        args += ["--wow", str(wow)]

    if plat == "linux":
        path = home / ".config/systemd/user/" / (SERVICE_NAME + ".service")
        body = (
            "[Unit]\n"
            "Description=GuildPhone roster sync\n"
            "After=network-online.target\n"
            "\n"
            "[Service]\n"
            "Type=simple\n"
            "ExecStart=" + " ".join(args) + "\n"
            "Restart=always\n"
            "RestartSec=60\n"
            "\n"
            "[Install]\n"
            "WantedBy=default.target\n")
        return {
            "path": path, "body": body,
            "register": [["systemctl", "--user", "daemon-reload"],
                         ["systemctl", "--user", "enable", "--now",
                          SERVICE_NAME + ".service"]],
            "unregister": [["systemctl", "--user", "disable", "--now",
                            SERVICE_NAME + ".service"],
                           ["systemctl", "--user", "daemon-reload"]],
            "note": "a systemd USER unit - no root, no sudo. "
                    "Read it: journalctl --user -u " + SERVICE_NAME,
        }

    if plat == "macos":
        path = home / "Library/LaunchAgents" / ("com.guildphone.sync.plist")
        logpath = home / "Library/Logs/guildphone-sync.log"
        prog = "".join("    <string>%s</string>\n" % _xml(a) for a in args)
        body = (
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0">\n'
            '<dict>\n'
            '  <key>Label</key><string>com.guildphone.sync</string>\n'
            '  <key>ProgramArguments</key>\n'
            '  <array>\n' + prog + '  </array>\n'
            '  <key>RunAtLoad</key><true/>\n'
            '  <key>KeepAlive</key><true/>\n'
            '  <key>StandardOutPath</key><string>%s</string>\n'
            '  <key>StandardErrorPath</key><string>%s</string>\n'
            '</dict>\n'
            '</plist>\n' % (_xml(str(logpath)), _xml(str(logpath))))
        return {
            "path": path, "body": body,
            "register": [["launchctl", "unload", str(path)],
                         ["launchctl", "load", "-w", str(path)]],
            "unregister": [["launchctl", "unload", "-w", str(path)]],
            "note": "a LaunchAgent in your own home directory - not "
                    "/Library, so it needs no administrator password. "
                    "Output goes to " + str(logpath),
        }

    # Windows. Task Scheduler cannot be handed a quoted command line without
    # a fight, so the command lives in a .cmd the task points at - which also
    # means there is a plain text file to read, same as the other two.
    base = home / "AppData/Local/GuildPhone"
    path = base / "guildphone-sync.cmd"
    # `start "" /b` so the .cmd hands off and exits instead of sitting there
    # for the whole session: a scheduled task runs its command through
    # cmd.exe in the player's own session, and a cmd.exe that is still
    # waiting on Python is a black window on the desktop until they log out.
    # The empty "" is start's title argument, which it needs before a quoted
    # program name.
    body = ("@echo off\r\n"
            "rem GuildPhone roster sync - written by guildphone-sync.py --install\r\n"
            'start "" /b ' + " ".join(_q(a) for a in args) + "\r\n")
    return {
        "path": path, "body": body,
        # The quotes inside the /TR value are deliberate and are not Python's.
        # Task Scheduler stores that value as a string and splits it on spaces
        # itself when the task fires, so an unquoted C:\Users\John Smith\...
        # becomes the command C:\Users\John with an argument, and the task
        # fails at logon with nothing on screen to say why.
        "register": [["schtasks", "/Create", "/TN", "GuildPhoneSync",
                      "/TR", '"%s"' % path, "/SC", "ONLOGON", "/F"]],
        "unregister": [["schtasks", "/Delete", "/TN", "GuildPhoneSync", "/F"]],
        "note": "a Task Scheduler entry for your user only, triggered at "
                "logon. No administrator rights. Inspect it with: "
                "schtasks /Query /TN GuildPhoneSync /V /FO LIST",
    }


def _xml(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def save_token(token):
    """Kept out of the service file on purpose: a token in a unit file is a
    token in `ps`, in `systemctl cat` and in anything that reads the task."""
    TOKEN_FILE.write_text(token)
    try:
        os.chmod(TOKEN_FILE, 0o600)
    except OSError:
        pass                      # Windows has no mode bits worth setting


def resolve_token(arg):
    if arg:
        return arg
    try:
        tok = TOKEN_FILE.read_text().strip()
    except OSError:
        return None
    return tok or None


def _show(plan):
    print("This will write:\n")
    print("  " + str(plan["path"]) + "\n")
    for line in plan["body"].replace("\r\n", "\n").rstrip("\n").split("\n"):
        print("    | " + line)
    print("\nand then run:\n")
    for cmd in plan["register"]:
        print("  " + " ".join(cmd))
    print("\n" + plan["note"] + "\n")


def _run(cmds, ignore_failure=()):
    import subprocess
    for cmd in cmds:
        try:
            r = subprocess.run(cmd, capture_output=True, text=True)
        except FileNotFoundError:
            print(f"  ! {cmd[0]} not found - run this yourself: {' '.join(cmd)}")
            continue
        out = (r.stdout + r.stderr).strip()
        tag = "ok" if r.returncode == 0 else f"exit {r.returncode}"
        if r.returncode != 0 and cmd in ignore_failure:
            tag = "not loaded (fine)"
        print(f"  $ {' '.join(cmd)}  [{tag}]")
        if out and r.returncode != 0:
            print("    " + out.replace("\n", "\n    "))


def do_install(url, wow, token):
    plan = service_plan(url, wow)
    _show(plan)
    if token:
        save_token(token)
        print(f"Token saved to {TOKEN_FILE} (readable only by you).\n")
    elif not resolve_token(None) and not os.environ.get("GUILDPHONE_TOKEN"):
        sys.exit("no token: re-run with --install --token YOUR_TOKEN. "
                 "Generate one in the portal, companion tab.")
    plan["path"].parent.mkdir(parents=True, exist_ok=True)
    plan["path"].write_text(plan["body"])
    # On macOS the first `launchctl unload` of a never-loaded agent fails,
    # which is not an error - it is the idempotent reinstall path.
    _run(plan["register"], ignore_failure=plan["register"][:1]
         if platform_key() == "macos" else ())
    print("\nInstalled. It starts with your session and syncs whenever you "
          "log out of WoW.\nRemove it completely with: "
          f"{Path(sys.executable).name} {Path(__file__).name} --uninstall")


def do_uninstall(url, wow):
    plan = service_plan(url, wow)
    print("Removing exactly what --install created:\n")
    _run(plan["unregister"], ignore_failure=plan["unregister"])
    if plan["path"].exists():
        plan["path"].unlink()
        print(f"  removed {plan['path']}")
    else:
        print(f"  {plan['path']} was not there")
    print(f"\nLeft alone: {TOKEN_FILE} and {STATE_FILE}. "
          "Delete those yourself if you want them gone.")


def main():
    ap = argparse.ArgumentParser(description="GuildPhone roster sync")
    ap.add_argument("--token", default=os.environ.get("GUILDPHONE_TOKEN"),
                    help="device token from the portal")
    ap.add_argument("--url", default=os.environ.get("GUILDPHONE_URL", DEFAULT_URL))
    ap.add_argument("--wow", help="World of Warcraft install directory")
    ap.add_argument("--once", action="store_true", help="sync and exit")
    ap.add_argument("--interval", type=int, default=30)
    ap.add_argument("--force", action="store_true",
                    help="ignore the saved state and upload regardless")
    ap.add_argument("--install", action="store_true",
                    help="start automatically when you log in (this user only)")
    ap.add_argument("--uninstall", action="store_true",
                    help="undo --install")
    a = ap.parse_args()

    if a.install and a.uninstall:
        sys.exit("--install and --uninstall are opposites; pick one")
    if a.install:
        return do_install(a.url, a.wow, a.token)
    if a.uninstall:
        return do_uninstall(a.url, a.wow)

    token = resolve_token(a.token)
    if not token:
        sys.exit("no token: pass --token or set GUILDPHONE_TOKEN "
                 "(generate one in the portal)")

    state = {} if a.force else load_state()
    if a.once:
        paths = find_saved_variables(a.wow)
        # Exiting is right here and wrong in the loop: --once is somebody at a
        # prompt who wants an answer, the loop is a service that has to still
        # be there when the addon finally writes the file.
        if not paths:
            sys.exit("no GuildPhone.lua found. Install the addon, log out "
                     "once, then pass --wow <your WoW folder>.")
        announce(paths, a.url)
        results = [sync_once(p, a.url, token, state) for p in paths]
        if "failed" in results:
            sys.exit(1)
        if "ok" not in results:
            log("nothing new since the last sync")
        return
    run_loop(a.url, token, a.wow, a.interval, state)


if __name__ == "__main__":
    main()
