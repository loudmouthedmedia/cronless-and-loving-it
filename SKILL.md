---
name: mac-launchd
description: >
  Create, install, and manage macOS launchd plist LaunchAgents for OpenClaw fleet Mac minis.
  Use when scheduling recurring tasks (watchdogs, reports, health checks) on macOS machines
  where cron silently drops jobs during sleep. Replaces cron with launchd for Mac OpenClaw
  instances. Triggers on "launchd", "mac scheduler", "mac cron replacement", "plist",
  "LaunchAgent", "mac sleep cron", "schedule mac", "mac fleet schedule", "mac watchdog",
  "migrate cron", "cron to launchd", "replace cron".
---

# mac-launchd

macOS sleeps. Cron doesn't wake up. launchd does.

## When to Use This Skill

- Scheduling any recurring task on a Mac OpenClaw instance
- Replacing existing cron jobs on Mac minis with launchd equivalents
- Auditing a Mac's scheduling setup (cron vs launchd)
- Setting up watchdogs, health checks, or reports on Mac fleet machines

## Why launchd Instead of cron

| Problem | cron | launchd |
|---------|------|---------|
| Machine asleep at scheduled time | Silently drops the job | Runs on wake (catch-up) |
| PATH not set correctly | Common issue | Set explicitly in plist |
| No crash recovery | No | `KeepAlive` auto-restarts |
| No boot-time execution | No | `RunAtLoad` |

## Workflow: Audit First

Before migrating, always audit the target machine:

```bash
# Run on the Mac mini
bash scripts/cron2launchd.sh --audit
```

This shows all cron jobs, existing launchd plists, and whether they're loaded.

## Workflow: Migrate Cron → launchd

### Automatic Migration (Recommended)

```bash
# Dry run first — see what would be created
bash scripts/cron2launchd.sh --migrate --dry-run

# Migrate all cron jobs
bash scripts/cron2launchd.sh --migrate

# Migrate only matching jobs
bash scripts/cron2launchd.sh --migrate --label-filter "self_heal"
```

The script will:
1. Parse each cron job
2. Generate a launchd plist with correct PATH, HOME, and schedule
3. Validate the plist with `plutil -lint`
4. Load it with `launchctl load`
5. Verify it's running
6. Remove the crontab entry

### Manual plist Generation

For custom jobs or finer control:

```bash
# Interval-based (watchdogs, health checks)
python3 scripts/generate_plist.py \
  --label com.openclaw.watchdog \
  --interval 300 \
  --command "openclaw doctor" \
  --machine jj \
  --output com.openclaw.watchdog.plist

# Calendar-based (reports at specific times)
python3 scripts/generate_plist.py \
  --label com.openclaw.morning-report \
  --hour 5 --minute 0 \
  --command "openclaw run --task morning-report" \
  --machine cosmos \
  --no-run-at-load \
  --output com.openclaw.morning-report.plist
```

### Install on a Remote Mac

```bash
# Copy plist to Mac
scp com.openclaw.watchdog.plist jj:~/Library/LaunchAgents/

# SSH in and load it
ssh jj "launchctl load ~/Library/LaunchAgents/com.openclaw.watchdog.plist"

# Verify
ssh jj "launchctl list | grep openclaw"
```

### Unload / Remove

```bash
ssh jj "launchctl unload ~/Library/LaunchAgents/com.openclaw.watchdog.plist && rm ~/Library/LaunchAgents/com.openclaw.watchdog.plist"
```

## Schedule Type Selection

- **Watchdogs, health checks** (every N minutes) → `StartInterval`
- **Reports, backups** (specific times) → `StartCalendarInterval`
- **Services** (always running) → `KeepAlive: true`

## PATH Requirement (Critical)

All Mac minis in this fleet use **Node 22** pinned via Homebrew. The plist MUST set the PATH explicitly or use absolute paths:

- `openclaw` → `/opt/homebrew/opt/node@22/bin/node /opt/homebrew/bin/openclaw`
- Or set `EnvironmentVariables` → `PATH` in the plist

**Never** rely on the default `node` — Node 25 has a broken `libsimdjson.29.dylib` on this fleet.

## Fleet SSH Aliases

| Machine | Alias | User | Home | SSH |
|---------|-------|------|------|-----|
| Cosmos | `cosmos` | joshuawoods | /Users/joshuawoods | `ssh joshuawoods@100.75.189.20` |
| J&J | `jj` | test | /Users/test | `ssh test@100.118.161.126` |
| Zaphod | `zaphod` | joshwoods | /Users/joshwoods | `ssh joshwoods@100.103.14.107` |

Always prepend PATH in SSH commands:
```bash
ssh jj "export PATH=/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH && <command>"
```

## Troubleshooting

- **Job not running?** `launchctl list | grep <label>` — exit code 0 = last run succeeded
- **Job running but failing?** Check logs: `log show --predicate 'process == "openclaw"' --last 1h`
- **plist not loading?** Validate: `plutil -lint ~/Library/LaunchAgents/com.openclaw.*.plist`
- **Need to reload?** `launchctl unload ... && launchctl load ...` (must unload first)
- **Cron jobs still present?** Run `crontab -l` to verify, `crontab -r` to clear

## Scripts

- **`scripts/cron2launchd.sh`** — Audit and migrate cron → launchd (see `--help`)
- **`scripts/generate_plist.py`** — Generate individual plists (see `--help`)

## References

- **`references/plist-templates.md`** — Ready-to-copy plist templates