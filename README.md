# Cronless and Loving It

> Replace cron with launchd on macOS — because cron silently drops jobs when your Mac sleeps. 💚

## The Problem

macOS sleeps. When it does, `cron` silently skips scheduled jobs. No error, no retry, no catch-up. Your watchdogs, reports, and health checks just... don't run.

`launchd` is macOS's native service manager. It handles sleep/wake correctly:
- **`StartInterval`** — runs every N seconds, catches up on wake
- **`StartCalendarInterval`** — runs at specific times, catches up on wake
- **`RunAtLoad`** — runs on boot/login
- **`KeepAlive`** — auto-restarts on crash

## Quick Start

### Audit a Mac

```bash
bash scripts/cron2launchd.sh --audit
```

### Migrate all cron jobs to launchd

```bash
# Dry run first
bash scripts/cron2launchd.sh --migrate --dry-run

# Migrate for real
bash scripts/cron2launchd.sh --migrate
```

### Generate an individual plist

```python
# Every 5 minutes (watchdog)
python3 scripts/generate_plist.py \
  --label com.openclaw.watchdog \
  --interval 300 \
  --command "openclaw doctor" \
  --output watchdog.plist

# Daily at 5am (report)
python3 scripts/generate_plist.py \
  --label com.openclaw.morning-report \
  --hour 5 --minute 0 \
  --command "openclaw run --task morning-report" \
  --no-run-at-load \
  --output morning-report.plist
```

### Install on a remote Mac

```bash
scp watchdog.plist user@mac:~/Library/LaunchAgents/
ssh user@mac "launchctl load ~/Library/LaunchAgents/watchdog.plist"
```

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/cron2launchd.sh` | Audit and migrate cron → launchd |
| `scripts/generate_plist.py` | Generate individual launchd plists |

## References

| File | Description |
|------|-------------|
| `references/plist-templates.md` | Ready-to-copy plist templates |

## Fleet Notes

For OpenClaw Mac minis, always set PATH explicitly in plists:

```
/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
```

Node 25 has a broken `libsimdjson.29.dylib` on this fleet. Always pin to Node 22.

## License

MIT