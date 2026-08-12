#!/usr/bin/env python3
"""Interactive session picker for promptless's /session command.

Lists opencode sessions (scoped to the current directory, matching the native
opencode TUI /sessions behavior) and lets the user choose one to continue,
start a fresh one, or cancel.

The outcome is printed on stdout as a single token the shell acts on:

    <session-id>          continue this session
    __PROMPTLESS_NEW__    start a new session
    __PROMPTLESS_CANCEL__ cancel / keep the current session

Commands:
    list [--dir DIR] [--json JSON]   print sessions as TSV: id<TAB>title<TAB>time
    pick [--dir DIR] [--json JSON]   interactive numbered picker

Without --json, session data is loaded from `opencode session list --format
json` (override the binary with the OPENCODE_BIN env var, useful for tests).
"""

import argparse
import datetime
import json
import os
import subprocess
import sys

PROMPTLESS_NEW = "__PROMPTLESS_NEW__"
PROMPTLESS_CANCEL = "__PROMPTLESS_CANCEL__"

MAX_TITLE_WIDTH = 55


def load_sessions(args):
    """Return sessions as a list of dicts, newest first, filtered by --dir."""
    if args.json:
        data = json.loads(args.json)
    else:
        binary = os.environ.get("OPENCODE_BIN", "opencode")
        proc = subprocess.run(
            [binary, "session", "list", "--format", "json"],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            sys.stderr.write(
                f"promptless: {binary} session list failed: {proc.stderr.strip()}\n"
            )
            sys.exit(1)
        data = json.loads(proc.stdout)

    if args.dir:
        target = os.path.realpath(args.dir)
        data = [
            s for s in data
            if os.path.realpath(s.get("directory", "")) == target
        ]

    data.sort(key=lambda s: s.get("updated", 0), reverse=True)
    return data


def _fmt_ampm(dt):
    hour = dt.hour
    ampm = "AM" if hour < 12 else "PM"
    hour12 = hour % 12 or 12
    return f"{hour12}:{dt.minute:02d} {ampm}"


def fmt_time(ts_ms):
    """Human-friendly timestamp: today -> '9:30 PM', older -> '9:30 PM · 8/2/2026'."""
    if not ts_ms:
        return ""
    now = datetime.datetime.now().astimezone()
    ts = datetime.datetime.fromtimestamp(ts_ms / 1000.0).astimezone()
    if ts.date() == now.date():
        return _fmt_ampm(ts)
    return f"{_fmt_ampm(ts)} · {ts.month}/{ts.day}/{ts.year}"


def _truncate(text, width):
    if len(text) <= width:
        return text
    return text[: width - 1] + "…"


def _read_line():
    """Read one line of user input.

    Normally stdin is the terminal, but when promptless runs under a zsh zle
    widget stdin is /dev/null, so fall back to /dev/tty.  When stdin is a pipe
    (tests), /dev/tty usually does not exist and we read the pipe instead.
    """
    if sys.stdin.isatty():
        return sys.stdin.readline()
    try:
        with open("/dev/tty", "r", encoding="utf-8") as tty:
            return tty.readline()
    except OSError:
        return sys.stdin.readline()


def tsv_rows(sessions):
    rows = []
    for s in sessions:
        title = _truncate(s.get("title") or "(untitled)", MAX_TITLE_WIDTH)
        rows.append("\t".join([s.get("id", ""), title, fmt_time(s.get("updated"))]))
    return rows


def cmd_list(args):
    sessions = load_sessions(args)
    for row in tsv_rows(sessions):
        print(row)


def cmd_pick(args):
    sessions = load_sessions(args)
    active = args.active or ""
    here = os.path.realpath(args.dir) if args.dir else os.getcwd()

    # All UI output goes to stderr so the shell can capture the result token
    # cleanly on stdout (stderr passes through to the terminal).
    err = sys.stderr
    err.write("promptless sessions · " + here + "\n")
    err.write("-" * 60 + "\n")

    if not sessions:
        err.write("  (no sessions for this directory)\n")
    else:
        for idx, s in enumerate(sessions, start=1):
            title = _truncate(s.get("title") or "(untitled)", MAX_TITLE_WIDTH)
            marker = "*" if s.get("id") == active else " "
            err.write(f"  {marker}{idx:>2}) {title:<{MAX_TITLE_WIDTH}}  {fmt_time(s.get('updated'))}\n")

    if active:
        err.write(f"  currently active: {active}\n")

    while True:
        err.write(f"Select a session (1-{len(sessions) or 0}, n=new, q=cancel): ")
        err.flush()
        line = _read_line()
        if line == "":
            err.write("\n")
            err.flush()
            print(PROMPTLESS_CANCEL)
            return
        choice = line.strip().lower()

        if choice in ("q", "quit", ""):
            print(PROMPTLESS_CANCEL)
            return
        if choice in ("n", "new"):
            print(PROMPTLESS_NEW)
            return
        if choice.isdigit():
            num = int(choice)
            if 1 <= num <= len(sessions):
                print(sessions[num - 1]["id"])
                return
        err.write(f"  invalid choice: {choice!r}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    for name in ("list", "pick"):
        p = sub.add_parser(name)
        p.add_argument("--dir", default=None, help="only sessions in this directory")
        p.add_argument("--json", default=None, help="inline JSON session list (tests)")
        if name == "pick":
            p.add_argument("--active", default=None, help="currently active session id")

    args = parser.parse_args()
    if args.command == "list":
        cmd_list(args)
    else:
        cmd_pick(args)


if __name__ == "__main__":
    main()
