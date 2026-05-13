---
name: cronless-and-loving-it
description: >
  Replace cron with launchd on macOS and add dead man's switch monitoring.
  Layer 1: launchd replaces cron so jobs survive sleep. Layer 2: Healthchecks.io dead man's
  switch detects silent failures. Audit, migrate, and manage launchd LaunchAgents + ping-based
  monitoring for scheduled jobs across the fleet. Triggers on "launchd", "mac scheduler",
  "mac cron replacement", "plist", "LaunchAgent", "mac sleep cron", "schedule mac",
  "mac watchdog", "migrate cron", "cron to launchd", "replace cron", "cronless",
  "dead man's switch", "healthcheck", "job monitoring", "cron monitoring".
---

# Cronless and Loving It 💚

Two layers of bulletproof scheduling:

**Layer 1 — launchd replaces cron** so jobs survive sleep.
**Layer 2 — Dead man's switch** detects silent failures.

## Layer 1: launchd (Sleep-Safe Scheduling)

macOS sleeps. Cron silently drops jobs. launchd catches up on wake.

| Problem | cron | launchd |
|---------|------|---------|
| Machine asleep | Silently drops | Runs on wake |
| No crash recovery | No | `KeepAlive` |
| No boot-time execution | No | `RunAtLoad` |
| PATH issues | Common | Set explicitly |

## Layer 2: Dead Man's Switch (Healthchecks.io)

Every job pings Healthchecks on completion. If no ping arrives within the expected window, you get a Telegram alert. Detects silent failures and offline machines.

For the full five-layer architecture, see `references/five-layers.md`.

---

## Quick Start

### Audit a Mac

```bash
bash scripts/cron2launchd.sh --audit
```

### Migrate Cron → launchd

```bash
# Dry run first
bash scripts/cron2launchd.sh --migrate --dry-run

# Migrate all cron jobs
bash scripts/cron2launchd.sh --migrate

# With dead man's switch (Layer 2)
bash scripts/cron2launchd.sh --migrate --ping-url http://localhost:8000/ping/<uuid>
```

### Generate Individual Plists

```bash
# Interval-based (watchdogs)
python3 scripts/generate_plist.py \
  --label com.openclaw.watchdog \
  --interval 300 \
  --command "openclaw doctor" \
  --machine jj

# With dead man's switch
python3 scripts/generate_plist.py \
  --label com.openclaw.watchdog \
  --interval 300 \
  --command "openclaw doctor" \
  --machine jj \
  --ping-url http://localhost:8000/ping/<uuid>

# Calendar-based (reports)
python3 scripts/generate_plist.py \
  --label com.openclaw.morning-report \
  --hour 5 --minute 0 \
  --command "openclaw run --task morning-report" \
  --machine cosmos \
  --no-run-at-load
```

### Install / Remove

```bash
scp com.openclaw.watchdog.plist jj:~/Library/LaunchAgents/
ssh jj "launchctl load ~/Library/LaunchAgents/com.openclaw.watchdog.plist"
# Remove: ssh jj "launchctl unload ... && rm ..."
```

## Healthchecks.io Reference

### Create a Check

```bash
curl -X POST http://localhost:8000/api/v3/checks/ \
  -H "X-Api-Key: <API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"name": "Job Name", "tags": "mcp watchdog", "timeout": 3600, "grace": 1800}'
```

### Ping on Completion

```bash
# Success
curl -fsS --retry 3 http://localhost:8000/ping/<uuid>

# Failure (job ran but failed)
curl -fsS --retry 3 http://localhost:8000/ping/<uuid>/fail
```

### List All Checks

```bash
curl -s http://localhost:8000/api/v3/checks/ \
  -H "X-Api-Key: <RO_API_KEY>" | python3 -m json.tool
```

---

## Schedule Type Selection

- **Watchdogs, health checks** (every N minutes) → `StartInterval`
- **Reports, backups** (specific times) → `StartCalendarInterval`
- **Services** (always running) → `KeepAlive: true`

## PATH Requirement (Critical)

All Mac minis use **Node 22** pinned via Homebrew. Always set PATH explicitly in plists:

```
/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
```

## Fleet SSH Aliases

| Machine | Alias | User | Home | SSH |
|---------|-------|------|------|-----|
| Cosmos | `cosmos` | joshuawoods | /Users/joshuawoods | `ssh joshuawoods@100.75.189.20` |
| J&J | `jj` | test | /Users/test | `ssh test@100.118.161.126` |
| Zaphod | `zaphod` | joshwoods | /Users/joshwoods | `ssh joshwoods@100.103.14.107` |

## Troubleshooting

- **Job not running?** `launchctl list | grep <label>` — exit code 0 = last run succeeded
- **Job running but failing?** Check logs: `log show --predicate 'process == "openclaw"' --last 1h`
- **plist not loading?** Validate: `plutil -lint ~/Library/LaunchAgents/com.openclaw.*.plist`
- **Need to reload?** `launchctl unload ... && launchctl load ...` (must unload first)
- **Cron jobs still present?** `crontab -l` to verify, `crontab -r` to clear
- **Healthchecks down?** `cd ~/healthchecks && docker compose up -d`

## Scripts

- **`scripts/cron2launchd.sh`** — Audit and migrate cron → launchd (`--ping-url` for Layer 2)
- **`scripts/generate_plist.py`** — Generate individual plists (`--ping-url` for Layer 2)

## References

- **`references/plist-templates.md`** — Ready-to-copy plist templates
- **`references/five-layers.md`** — The five-layer architecture outline