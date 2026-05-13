# Cronless and Loving It

> Replace cron with launchd on macOS — because cron silently drops jobs when your Mac sleeps. 💚

## The Problem

macOS sleeps. When it does, `cron` silently skips scheduled jobs. No error, no retry, no catch-up.

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

### Migrate cron to launchd

```bash
# Dry run first
bash scripts/cron2launchd.sh --migrate --dry-run

# Migrate for real
bash scripts/cron2launchd.sh --migrate

# With dead man's switch (Layer 2)
bash scripts/cron2launchd.sh --migrate --ping-url http://localhost:8000/ping/<uuid>
```

### Generate an individual plist

```python
# Every 5 minutes (watchdog)
python3 scripts/generate_plist.py \
  --label com.openclaw.watchdog \
  --interval 300 \
  --command "openclaw doctor" \
  --output watchdog.plist

# With dead man's switch
python3 scripts/generate_plist.py \
  --label com.openclaw.watchdog \
  --interval 300 \
  --command "openclaw doctor" \
  --ping-url http://localhost:8000/ping/<uuid> \
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

## The Five Layers

For the full architecture, see [`references/five-layers.md`](references/five-layers.md).

1. **Replace Cron with launchd** — sleep-safe scheduling
2. **Dead Man's Switch** — Healthchecks.io detects silent failures
3. **Job Idempotency** — file-based dedup to prevent double-triggers
4. **Job Queue with Retry** — exponential backoff for failed jobs
5. **Orchestration Brain** — central monitoring, log aggregation, AI analysis, alert routing

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/cron2launchd.sh` | Audit and migrate cron → launchd. Supports `--ping-url` |
| `scripts/generate_plist.py` | Generate individual launchd plists. Supports `--ping-url` |

## References

| File | Description |
|------|-------------|
| `references/plist-templates.md` | Ready-to-copy plist templates |
| `references/five-layers.md` | The five-layer architecture outline |

## Fleet Notes

For OpenClaw Mac minis, always set PATH explicitly in plists:

```
/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
```

Node 25 has a broken `libsimdjson.29.dylib` on this fleet. Always pin to Node 22.

## License

MIT