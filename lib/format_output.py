#!/usr/bin/env python3
"""Parse opencode's JSON-streaming output into readable terminal output.

Reads newline-delimited JSON events from stdin and formats them for
human consumption: text content streams through in real-time, tool
calls are displayed with their inputs and results, and errors or
denied permissions are surfaced prominently.

The session id seen in the first JSON event is written to the path given
in the PROMPTLESS_CAPTURE_FILE environment variable (if set) so the shell
wrapper can adopt a freshly created session as the current one.

Usage:
    PROMPTLESS_CAPTURE_FILE=/tmp/out opencode run --format json --auto "$PROMPT" 2>/dev/tty | format_output.py
"""

import json
import sys
import os


ANSI_RESET = "\033[0m"
ANSI_BOLD = "\033[1m"
ANSI_DIM = "\033[2m"
ANSI_GREEN = "\033[32m"
ANSI_YELLOW = "\033[33m"
ANSI_RED = "\033[31m"
ANSI_CYAN = "\033[36m"

_use_color = os.isatty(sys.stdout.fileno())


def _c(code, text):
    if not _use_color:
        return text
    return f"{code}{text}{ANSI_RESET}"


def _b(text):
    return _c(ANSI_BOLD, text)


def _dim(text):
    return _c(ANSI_DIM, text)


def _green(text):
    return _c(ANSI_GREEN, text)


def _yellow(text):
    return _c(ANSI_YELLOW, text)


def _red(text):
    return _c(ANSI_RED, text)


def _cyan(text):
    return _c(ANSI_CYAN, text)


def unescape_json(s):
    return s.replace("\\n", "\n").replace("\\t", "\t").replace('\\"', '"').replace("\\\\", "\\")


def main():
    session_captured = False
    line_count = 0

    capture_file = os.environ.get("PROMPTLESS_CAPTURE_FILE") or None

    for line_no, line in enumerate(sys.stdin, start=1):
        line = line.strip()
        if not line:
            continue

        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
            continue

        line_count += 1

        event_type = data.get("type", "")
        session_id = data.get("sessionID", "")
        part = data.get("part", {})

        # ---- session capture (first event) ----
        if not session_captured and session_id:
            session_captured = True
            if capture_file:
                try:
                    with open(capture_file, "w") as cf:
                        cf.write(session_id)
                except OSError:
                    pass

        # ---- step_start: opaque working indicator ----
        if event_type == "step_start":
            continue

        # ---- text: stream content to terminal ----
        elif event_type == "text":
            text = part.get("text", "")
            text = unescape_json(text)
            sys.stdout.write(text)
            sys.stdout.flush()

        # ---- tool_use: display tool call and result ----
        elif event_type == "tool_use":
            tool = part.get("tool", "unknown")
            state = part.get("state", {})
            status = state.get("status", "unknown")
            tool_input = state.get("input", {})
            tool_output = state.get("output", "")
            tool_error = state.get("error", "")
            title = state.get("title", "")
            call_id = part.get("callID", "")

            if not title:
                title = tool

            indent = "  "

            if status == "completed":
                print()
                print(_dim(f"── {title} ") + _green("✓"))
                if tool == "bash" and "command" in tool_input:
                    print(_dim(f"{indent}$ {tool_input['command']}"))
                if tool_output:
                    for output_line in tool_output.rstrip("\n").split("\n"):
                        print(f"{indent}{output_line}")
            elif status == "error":
                print()
                print(_dim(f"── {title} ") + _red("✗"))
                if tool_error:
                    print(_red(f"{indent}{tool_error}"))
                if tool == "bash" and tool_input.get("command"):
                    print(_dim(f"{indent}attempted: $ {tool_input['command']}"))
            elif status == "running":
                print()
                print(_yellow(f"⟳ {title}..."))
                if tool == "bash" and tool_input.get("command"):
                    print(_dim(f"{indent}$ {tool_input['command']}"))
            else:
                print()
                print(_dim(f"── {title} [{status}]"))

        # ---- step_finish: capture tokens for visibility ----
        elif event_type == "step_finish":
            tokens = part.get("tokens", {})
            tokens_in = tokens.get("input", 0)
            tokens_out = tokens.get("output", 0)
            if tokens_in > 0 or tokens_out > 0:
                sys.stderr.write(
                    _dim(f"  (↑{tokens_in} ↓{tokens_out})\n")
                )
                sys.stderr.flush()

        # ---- unknown event types ----
        # else:
        #     sys.stderr.write(_dim(f"[unhandled event: {event_type}]\n"))

    # Final newline if we produced any output.
    if line_count > 0:
        print()


if __name__ == "__main__":
    main()
