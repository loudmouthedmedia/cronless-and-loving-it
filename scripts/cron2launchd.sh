#!/usr/bin/env bash
# ==============================================================================
# cron2launchd.sh — Audit macOS cron jobs and convert them to launchd plists
#
# Usage:
#   ./cron2launchd.sh --audit              # Show current cron + launchd status
#   ./cron2launchd.sh --migrate             # Convert all cron jobs to launchd, remove crontab
#   ./cron2launchd.sh --migrate --dry-run   # Preview what would be created, don't install
#   ./cron2launchd.sh --migrate --label-filter "self_heal"  # Only migrate matching jobs
#
# Designed for OpenClaw fleet Mac minis. Sets correct PATH with Node 22.
# ==============================================================================

set -euo pipefail

# --- Config ---
LAUNCHD_DIR="$HOME/Library/LaunchAgents"
CRON_LABEL_PREFIX="com.openclaw.cron-migrated"
PATH_OPENCLAW="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
DRY_RUN=false
LABEL_FILTER=""
ACTION=""

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --audit) ACTION="audit"; shift ;;
    --migrate) ACTION="migrate"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --label-filter) LABEL_FILTER="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 --audit | --migrate [--dry-run] [--label-filter pattern]"
      echo ""
      echo "  --audit           Show current cron + launchd status"
      echo "  --migrate         Convert cron jobs to launchd plists"
      echo "  --dry-run         Preview without making changes"
      echo "  --label-filter    Only migrate cron entries matching pattern"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  echo "Error: specify --audit or --migrate"
  exit 1
fi

# --- Helpers ---

get_home_dir() {
  echo "$HOME"
}

# Parse cron interval (e.g., */5, */10, */15, */30) to seconds
parse_interval_minutes() {
  local expr="$1"
  # Handle */N format
  if [[ "$expr" == */* ]]; then
    local mins="${expr#\*/}"
    echo "$((mins * 60))"
  # Handle plain number
  elif [[ "$expr" =~ ^[0-9]+$ ]]; then
    echo "$((expr * 60))"
  else
    echo "0"
  fi
}

# Generate a plist from a cron job
generate_plist() {
  local label="$1"
  local interval_sec="$2"
  local command="$3"
  local home="$4"
  local stdout_log="$5"
  local stderr_log="$6"

  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>${command}</string>
    </array>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${PATH_OPENCLAW}</string>
        <key>HOME</key>
        <string>${home}</string>
    </dict>

    <key>StartInterval</key>
    <integer>${interval_sec}</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>${stdout_log}</string>
    <key>StandardErrorPath</key>
    <string>${stderr_log}</string>
</dict>
</plist>
PLIST
}

# --- Audit ---
if [[ "$ACTION" == "audit" ]]; then
  echo "=========================================="
  echo "  cron2launchd Audit"
  echo "=========================================="
  echo ""

  # Show crontab
  echo "── Cron Jobs ──"
  if crontab -l 2>/dev/null; then
    HAS_CRON=true
  else
    echo "(no crontab)"
    HAS_CRON=false
  fi
  echo ""

  # Show existing launchd plists
  echo "── Existing LaunchAgents ──"
  if ls "$LAUNCHD_DIR"/*openclaw* "$LAUNCHD_DIR"/*claw* 2>/dev/null; then
    echo ""
    for f in "$LAUNCHD_DIR"/*openclaw*.plist "$LAUNCHD_DIR"/*claw*.plist; do
      [[ -f "$f" ]] || continue
      label=$(plutil -extract Label raw "$f" 2>/dev/null || echo "unknown")
      loaded=$(launchctl list 2>/dev/null | grep "$label" && echo "✅ loaded" || echo "❌ not loaded")
      echo "  $label: $loaded"
    done
  else
    echo "(no openclaw/claw plists found)"
  fi
  echo ""

  # Show all plists
  echo "── All LaunchAgents ──"
  ls -1 "$LAUNCHD_DIR/" 2>/dev/null || echo "(empty)"
  echo ""

  # Summary
  echo "── Summary ──"
  if [[ "$HAS_CRON" == true ]]; then
    echo "⚠️  Cron jobs found — run --migrate to convert to launchd"
  else
    echo "✅ No cron jobs — all scheduling is launchd or OpenClaw-internal"
  fi
  exit 0
fi

# --- Migrate ---
if [[ "$ACTION" == "migrate" ]]; then
  echo "=========================================="
  echo "  cron2launchd Migration"
  echo "=========================================="
  echo ""

  # Read crontab
  CRON_CONTENT=""
  if ! CRON_CONTENT=$(crontab -l 2>/dev/null); then
    echo "No crontab found — nothing to migrate."
    exit 0
  fi

  # Filter lines (skip comments and empty lines)
  MIGRATABLE=false
  JOBS=()
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ -z "$line" || "$line" == \#* ]] && continue
    # Apply label filter if specified
    if [[ -n "$LABEL_FILTER" ]] && [[ "$line" != *"$LABEL_FILTER"* ]]; then
      continue
    fi
    JOBS+=("$line")
  done <<< "$CRON_CONTENT"

  if [[ ${#JOBS[@]} -eq 0 ]]; then
    echo "No cron jobs to migrate (filtered or empty)."
    exit 0
  fi

  echo "Found ${#JOBS[@]} cron job(s) to migrate:"
  for job in "${JOBS[@]}"; do
    echo "  $job"
  done
  echo ""

  MIGRATED=0
  FAILED=0

  for job in "${JOBS[@]}"; do
    # Parse cron line: MIN HOUR DAY MONTH DOW COMMAND
    # Handle */N minute intervals
    read -r min hour day month dow cmd <<< "$job"

    # Generate a label from the command
    # Extract script name or first meaningful word
    cmd_base=$(basename "$cmd" 2>/dev/null | sed 's/\..*//' | sed 's/[^a-zA-Z0-9]/-/g' | head -c 40)
    if [[ -z "$cmd_base" || "$cmd_base" == "-" ]]; then
      cmd_base="job"
    fi
    label="${CRON_LABEL_PREFIX}.${cmd_base}"

    # Check if label already exists
    if [[ -f "$LAUNCHD_DIR/${label}.plist" ]]; then
      echo "⚠️  $label already exists — skipping"
      continue
    fi

    # Determine interval in seconds
    # For */N minute patterns, use N*60 seconds
    # For specific times, use StartCalendarInterval instead
    if [[ "$min" == */* ]]; then
      interval_mins="${min#\*/}"
      interval_sec=$((interval_mins * 60))
      schedule_type="interval"
    elif [[ "$min" == "*" && "$hour" == */* ]]; then
      interval_mins="${hour#\*/}"
      interval_sec=$((interval_mins * 60 * 60))
      schedule_type="interval"
    else
      # Specific time — would need StartCalendarInterval
      # For simplicity, approximate with a daily interval
      interval_sec=86400
      schedule_type="calendar-approximated"
    fi

    home=$(get_home_dir)
    stdout_log="$HOME/.openclaw/logs/${cmd_base}.out.log"
    stderr_log="$HOME/.openclaw/logs/${cmd_base}.err.log"

    # Ensure log dir exists
    mkdir -p "$HOME/.openclaw/logs"

    echo "── Migrating: $cmd_base ──"
    echo "   Cron: $job"
    echo "   Label: $label"
    echo "   Interval: ${interval_sec}s ($((interval_sec / 60))min)"
    echo "   Command: $cmd"

    if [[ "$schedule_type" == "calendar-approximated" ]]; then
      echo "   ⚠️  Specific cron time approximated as daily interval (86400s)"
      echo "   ⚠️  Consider manual StartCalendarInterval plist for exact times"
    fi

    # Generate plist
    plist_content=$(generate_plist "$label" "$interval_sec" "$cmd" "$home" "$stdout_log" "$stderr_log")

    if [[ "$DRY_RUN" == true ]]; then
      echo "   [DRY RUN] Would create: $LAUNCHD_DIR/${label}.plist"
      echo "$plist_content"
      echo ""
      continue
    fi

    # Write plist
    echo "$plist_content" > "$LAUNCHD_DIR/${label}.plist"

    # Validate
    if plutil -lint "$LAUNCHD_DIR/${label}.plist" > /dev/null 2>&1; then
      echo "   ✅ Plist valid"
    else
      echo "   ❌ Plist invalid!"
      rm "$LAUNCHD_DIR/${label}.plist"
      FAILED=$((FAILED + 1))
      continue
    fi

    # Load
    if launchctl load "$LAUNCHD_DIR/${label}.plist" 2>/dev/null; then
      echo "   ✅ Loaded"
    else
      echo "   ⚠️  Load failed (may already be loaded or need manual load)"
    fi

    # Verify
    sleep 1
    if launchctl list | grep -q "$label"; then
      echo "   ✅ Running"
    else
      echo "   ⚠️  Not found in launchctl list"
    fi

    MIGRATED=$((MIGRATED + 1))
    echo ""
  done

  # Remove crontab if all migrated
  if [[ "$DRY_RUN" == false && $MIGRATED -gt 0 && $FAILED -eq 0 ]]; then
    echo "── Removing crontab ──"
    crontab -r 2>/dev/null || true
    echo "✅ Crontab removed"
  elif [[ "$DRY_RUN" == false && $MIGRATED -gt 0 ]]; then
    echo "⚠️  Some jobs failed — crontab left in place. Fix failures then re-run."
  fi

  echo ""
  echo "=========================================="
  echo "  Migration complete: $MIGRATED migrated, $FAILED failed"
  echo "=========================================="

  # Verify no more cron
  echo ""
  echo "── Remaining crontab ──"
  crontab -l 2>/dev/null || echo "(empty — all clear)"
fi