# launchd Plist Templates

## Template 1: Interval-based Watchdog (every N seconds)

For health checks, watchdogs, and periodic tasks that should run regardless of wall-clock time.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.watchdog</string>

    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/opt/node@22/bin/node</string>
        <string>/opt/homebrew/bin/openclaw</string>
        <string>doctor</string>
    </array>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/test</string>
    </dict>

    <key>StartInterval</key>
    <integer>300</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/com.openclaw.watchdog.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/com.openclaw.watchdog.stderr.log</string>
</dict>
</plist>
```

### Customization
- Change `Label` to match the job
- Change `ProgramArguments` to the actual command
- Change `StartInterval` (seconds): 300 = 5min, 3600 = 1hr, 86400 = 24hr
- Set `HOME` to the correct user home directory
- Change log paths as needed

## Template 2: Calendar-based Report (specific time)

For morning reports, nightly analysis, or any task at a specific time.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.morning-report</string>

    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/opt/node@22/bin/node</string>
        <string>/opt/homebrew/bin/openclaw</string>
        <string>run</string>
        <string>--task</string>
        <string>morning-report</string>
    </array>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/test</string>
    </dict>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>5</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>RunAtLoad</key>
    <false/>

    <key>StandardOutPath</key>
    <string>/tmp/com.openclaw.morning-report.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/com.openclaw.morning-report.stderr.log</string>
</dict>
</plist>
```

### Customization
- `StartCalendarInterval` supports: `Hour`, `Minute`, `Weekday` (0=Sun, 1=Mon, etc.), `Day` (day of month)
- For weekday-only: add `<key>Weekday</key><integer>1</integer>` through `<integer>5</integer>`
- For daily: omit `Weekday` (runs every day)

## Template 3: Shell Script Wrapper

When the command is complex (multi-step, pipes, conditionals), wrap in a script and call the script.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.esm-patch-watchdog</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/test/.openclaw/workspace/scripts/watchdog.sh</string>
    </array>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/test</string>
    </dict>

    <key>StartInterval</key>
    <integer>1800</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/com.openclaw.esm-patch.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/com.openclaw.esm-patch.stderr.log</string>
</dict>
</plist>
```

## User HOME Directories

| Machine | User | HOME |
|---------|------|------|
| Cosmos | joshuawoods | /Users/joshuawoods |
| J&J | test | /Users/test |
| Zaphod | joshwoods | /Users/joshwoods |

## Common Commands

```bash
# Load a plist
launchctl load ~/Library/LaunchAgents/com.openclaw.<name>.plist

# Unload a plist
launchctl unload ~/Library/LaunchAgents/com.openclaw.<name>.plist

# Reload (must unload first!)
launchctl unload ~/Library/LaunchAgents/com.openclaw.<name>.plist
launchctl load ~/Library/LaunchAgents/com.openclaw.<name>.plist

# Check if loaded
launchctl list | grep openclaw

# View recent logs
log show --predicate 'process == "openclaw"' --last 1h

# Validate plist syntax
plutil -lint ~/Library/LaunchAgents/com.openclaw.*.plist
```