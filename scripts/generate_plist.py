#!/usr/bin/env python3
"""Generate a macOS launchd plist for OpenClaw fleet Mac minis.

Usage:
  python3 generate_plist.py --label com.openclaw.watchdog --interval 300 --command "openclaw doctor"
  python3 generate_plist.py --label com.openclaw.morning-report --hour 5 --minute 0 --command "openclaw run --task morning-report"
  python3 generate_plist.py --label com.openclaw.watchdog --interval 300 --script /Users/test/.openclaw/workspace/scripts/watchdog.sh
"""

import argparse
import xml.etree.ElementTree as ET
from xml.dom import minidom
import sys

# Fleet home directories
HOME_DIRS = {
    "cosmos": "/Users/joshuawoods",
    "jj": "/Users/test",
    "j&j": "/Users/test",
    "zaphod": "/Users/joshwoods",
}

PATH = "/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"


def detect_home(machine):
    """Detect HOME directory from machine alias."""
    machine_lower = machine.lower() if machine else ""
    return HOME_DIRS.get(machine_lower, f"/Users/{machine}")


def build_plist(label, command=None, script=None, interval=None, hour=None, minute=None,
                machine=None, run_at_load=True, stdout_log=None, stderr_log=None):
    """Build a launchd plist as a string."""
    if not command and not script:
        print("Error: --command or --script required", file=sys.stderr)
        sys.exit(1)
    if interval and (hour is not None or minute is not None):
        print("Error: --interval and --hour/--minute are mutually exclusive", file=sys.stderr)
        sys.exit(1)
    if not interval and hour is None and minute is None:
        # Default to interval if nothing specified
        interval = 300

    home = detect_home(machine)
    if not stdout_log:
        stdout_log = f"/tmp/{label}.stdout.log"
    if not stderr_log:
        stderr_log = f"/tmp/{label}.stderr.log"

    # Build ProgramArguments
    if script:
        program_args = ["/bin/bash", script]
    else:
        # Use absolute paths for node and openclaw
        # Split command into args, replacing 'openclaw' with absolute path
        parts = command.split()
        new_parts = []
        skip_openclaw_bin = False
        for i, part in enumerate(parts):
            if part == "openclaw" and i == 0:
                new_parts.append("/opt/homebrew/opt/node@22/bin/node")
                new_parts.append("/opt/homebrew/bin/openclaw")
                skip_openclaw_bin = True
            elif skip_openclaw_bin and part.startswith("-"):
                # It's a flag after openclaw
                new_parts.append(part)
                skip_openclaw_bin = False
            else:
                skip_openclaw_bin = False
                new_parts.append(part)
        if not new_parts:
            new_parts = ["/opt/homebrew/opt/node@22/bin/node", "/opt/homebrew/bin/openclaw"]
        program_args = new_parts

    # Build XML manually for clean output
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
        '<plist version="1.0">',
        '<dict>',
        f'    <key>Label</key>',
        f'    <string>{label}</string>',
        '',
        f'    <key>ProgramArguments</key>',
        f'    <array>',
    ]
    for arg in program_args:
        lines.append(f'        <string>{arg}</string>')
    lines.append(f'    </array>')
    lines.append('')
    lines.append(f'    <key>EnvironmentVariables</key>')
    lines.append(f'    <dict>')
    lines.append(f'        <key>PATH</key>')
    lines.append(f'        <string>{PATH}</string>')
    lines.append(f'        <key>HOME</key>')
    lines.append(f'        <string>{home}</string>')
    lines.append(f'    </dict>')
    lines.append('')

    # Schedule
    if interval:
        lines.append(f'    <key>StartInterval</key>')
        lines.append(f'    <integer>{interval}</integer>')
    else:
        lines.append(f'    <key>StartCalendarInterval</key>')
        lines.append(f'    <dict>')
        if hour is not None:
            lines.append(f'        <key>Hour</key><integer>{hour}</integer>')
        if minute is not None:
            lines.append(f'        <key>Minute</key><integer>{minute}</integer>')
        lines.append(f'    </dict>')

    lines.append('')
    lines.append(f'    <key>RunAtLoad</key>')
    lines.append(f'    <{"true" if run_at_load else "false"}/>')
    lines.append('')
    lines.append(f'    <key>StandardOutPath</key>')
    lines.append(f'    <string>{stdout_log}</string>')
    lines.append(f'    <key>StandardErrorPath</key>')
    lines.append(f'    <string>{stderr_log}</string>')
    lines.append('</dict>')
    lines.append('</plist>')

    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description="Generate launchd plist for Mac OpenClaw fleet")
    parser.add_argument("--label", required=True, help="launchd label (e.g. com.openclaw.watchdog)")
    parser.add_argument("--interval", type=int, help="Run every N seconds")
    parser.add_argument("--hour", type=int, default=None, help="Run at this hour (0-23)")
    parser.add_argument("--minute", type=int, default=None, help="Run at this minute (0-59)")
    cmd = parser.add_mutually_exclusive_group()
    cmd.add_argument("--command", help="Command to run (e.g. 'openclaw doctor')")
    cmd.add_argument("--script", help="Path to shell script on the Mac")
    parser.add_argument("--machine", help="Machine alias (cosmos, jj, zaphod) for HOME dir")
    parser.add_argument("--no-run-at-load", action="store_true", help="Don't run at load (default: runs)")
    parser.add_argument("--output", "-o", help="Output file path (default: stdout)")

    args = parser.parse_args()

    plist = build_plist(
        label=args.label,
        command=args.command,
        script=args.script,
        interval=args.interval,
        hour=args.hour,
        minute=args.minute,
        machine=args.machine,
        run_at_load=not args.no_run_at_load,
    )

    if args.output:
        with open(args.output, 'w') as f:
            f.write(plist + '\n')
        print(f"Written to {args.output}")
    else:
        print(plist)


if __name__ == "__main__":
    main()