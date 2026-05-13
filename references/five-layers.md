# Cronless and Loving It — The Five Layers

## Layer 1: Replace Cron With launchd

Don't use cron on macOS. Use launchd with `StartInterval` or `StartCalendarInterval`:

```xml
<key>StartCalendarInterval</key>
<dict>
 <key>Hour</key><integer>9</integer>
 <key>Minute</key><integer>0</integer>
</dict>
<key>RunAtLoad</key><true/>
```

`launchd` has catch-up — if the machine was asleep, it runs the job as soon as it wakes. Cron just silently drops it.

## Layer 2: Dead Man's Switch

Job runs → immediately pings a watchdog URL. Watchdog waits → if no ping within expected window → fires alert.

```bash
# At the END of every job
curl -fsS --retry 3 http://localhost:8000/ping/<uuid>
```

If that ping doesn't arrive, you know before the client does. Self-hosted Healthchecks.io on your infrastructure — free, private, real-time dashboard of every job's status.

## Layer 3: Job Idempotency

Even if a job runs twice (double-trigger on resume from sleep), it shouldn't cause damage:

```bash
IDEM_FILE="$HOME/.openclaw/state/daily-$(date +%Y-%m-%d)-${JOB_NAME}.lock"
if [ -f "$IDEM_FILE" ]; then
    echo "Job $JOB_NAME already ran today, skipping"
    exit 0
fi
touch "$IDEM_FILE"
# ... do the work ...
```

File-based idempotency key — the job checks if it already ran before doing anything. Running it twice is harmless.

## Layer 4: Job Queue With Retry

Cron/launchd fires → pushes job to queue (Redis/SQLite) → worker picks up → fails? Retries with exponential backoff (30s, 2min, 10min, 1hr) → still failing after 4 retries? Marks as failed, alerts.

For OpenClaw deployments, this is already built in — OpenClaw's internal queue handles retries, timeouts, and `failureAlert` configs. Adding Huey/Redis underneath would be two job queues in parallel.

## Layer 5: Orchestration Brain

Client Mac Mini:
- launchd triggers jobs (not cron)
- jobs push to local queue
- worker executes with retry
- success/failure → pings your monitoring server
- structured logs → shipped to your central server

Your central server:
- Healthchecks dashboard (all clients, all jobs)
- Log aggregator (collected nightly)
- AI analyzes log anomalies
- Alert rules → your phone if something's red
- SSH jump host → you log in and fix