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
**Layer 2 — Dead man's switch** detects when they don't run.

## Layer 1: launchd (Mac Scheduling)

macOS sleeps. Cron doesn't wake up. launchd does.

| Problem | cron | launchd |
|---------|------|---------|
| Machine asleep at scheduled time | Silently drops the job | Runs on wake (catch-up) |
| PATH not set correctly | Common issue | Set explicitly in plist |
| No crash recovery | No | `KeepAlive` auto-restarts |
| No boot-time execution | No | `RunAtLoad` |

### Audit First

```bash
# Run on the Mac mini
bash scripts/cron2launchd.sh --audit
```

### Migrate Cron → launchd

```bash
# Dry run first — see what would be created
bash scripts/cron2launchd.sh --migrate --dry-run

# Migrate all cron jobs
bash scripts/cron2launchd.sh --migrate

# Migrate only matching jobs
bash scripts/cron2launchd.sh --migrate --label-filter "self_heal"
```

### Generate Individual Plists

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
  --no-run-at-load
```

### Install / Remove

```bash
scp com.openclaw.watchdog.plist jj:~/Library/LaunchAgents/
ssh jj "launchctl load ~/Library/LaunchAgents/com.openclaw.watchdog.plist"
# Remove: ssh jj "launchctl unload ... && rm ..."
```

## Layer 2: Dead Man's Switch (Healthchecks.io)

**Problem:** Even with launchd, jobs can silently fail. The machine could be down entirely. You need to know *before* the client does.

**Solution:** Every job pings Healthchecks on completion. If no ping arrives within the expected window, Healthchecks alerts you via Telegram.

### Setup (Already Deployed on MCP)

Healthchecks.io is self-hosted on MCP at `http://localhost:8000/`

| Credential | Value |
|-----------|-------|
| URL | http://localhost:8000/ |
| Admin | admin@cosmosthebot.com / mcp-fleet-2026 |
| API Key (R/W) | `llit57t0vOXF78g3OgpNysNFX1kAOYAL` |
| API Key (RO) | `Cdu2rBT8QfvUKJRj0r7q1X6ctPMaeDtS` |
| Ping Key | `hQ4K0qJyjGpO5rWyLoIxgg` |

### Create a Check

```bash
# Create a new check for a scheduled job
curl -X POST http://localhost:8000/api/v3/checks/ \
  -H "X-Api-Key: llit57t0vOXF78g3OgpNysNFX1kAOYAL" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Job Name",
    "tags": "mcp watchdog",
    "timeout": 3600,
    "grace": 1800
  }'
```

Response includes the `ping_url` — use the UUID from it.

### Ping on Completion

Add this to the END of every scheduled job (launchd plist or OpenClaw cron):

```bash
# Using UUID (from create response)
curl -fsS --retry 3 http://localhost:8000/ping/<uuid>

# Using ping key + slug (easier to read)
curl -fsS --retry 3 http://localhost:8000/ping/hQ4K0qJyjGpO5rWyLoIxgg/<slug>
```

### Report Failure

```bash
# Signal failure (job ran but failed)
curl -fsS --retry 3 http://localhost:8000/ping/<uuid>/fail
```

### Integrate with OpenClaw Cron Jobs

Add a ping to the end of any cron job payload message:

```
... After completing your task, run: curl -fsS --retry 3 http://localhost:8000/ping/<uuid>
```

Or add to launchd plist scripts:

```bash
#!/bin/bash
# ... do the actual work ...
RESULT=$?
if [ $RESULT -eq 0 ]; then
  curl -fsS --retry 3 http://localhost:8000/ping/<uuid>
else
  curl -fsS --retry 3 http://localhost:8000/ping/<uuid>/fail
fi
```

### List All Checks

```bash
curl -s http://localhost:8000/api/v3/checks/ \
  -H "X-Api-Key: Cdu2rBT8QfvUKJRj0r7q1X6ctPMaeDtS" | python3 -m json.tool
```

### Docker Management

```bash
cd ~/healthchecks
docker compose up -d      # Start
docker compose down        # Stop
docker compose logs -f     # Logs
```

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

- **`scripts/cron2launchd.sh`** — Audit and migrate cron → launchd (see `--help`)
- **`scripts/generate_plist.py`** — Generate individual plists (see `--help`)

## References

- **`references/plist-templates.md`** — Ready-to-copy plist templates