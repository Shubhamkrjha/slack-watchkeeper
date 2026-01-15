# Slack Watch Keeper

**A robust Slack notification monitor for macOS** 

Never miss an slack alert again. Slack Watch Keeper monitors your Slack dock badge during configured hours and plays a loud alarm — even if your system volume is low or muted.

![macOS](https://img.shields.io/badge/macOS-10.14+-blue?logo=apple)
![License](https://img.shields.io/badge/license-Unlicense-blue)
![AppleScript](https://img.shields.io/badge/AppleScript-native-orange)

---
 
## Features

| Feature | Description |
|---------|-------------|
| Dock Badge Detection | Reads Slack's unread count directly from macOS Dock |
| Configurable Schedule | Set custom start/end times and active days |
| Volume Override | Forces system volume to your configured level during alerts |
| Battery Safety | Warns on low battery, auto-exits before critical to prevent drain |
| Sleep Prevention | Keeps Mac awake using `caffeinate` |
| Network Monitoring | Detects network outages, alerts once, auto-resumes when restored |
| Slack Auto-Start | Automatically starts Slack if not running, restarts if crashed |
| Clean Shutdown | Proper cleanup on exit |
| Debug Mode | Verbose logging for troubleshooting |
| Alert Modes | Regular (bounded retries) or Deadman (loops until acknowledged) |
| Pre Alarm | A 10 sec pre alarm window where alert can acknowledged. |

---

## Requirements

- **macOS** 10.14 Mojave or later
- **Slack** desktop app 
- **Accessibility permission** for Terminal or Script Editor
- **alarm.mp3** — your alarm sound file

---

## Quick Start

### 1. Clone and Setup

```bash
git clone https://github.com/Shubhamkrjha/slack-watch.git
cd slack-watch
chmod +x slack-watch.sh
```

### 2. Add Alarm Sound

Place an `alarm.mp3` file in the project folder.

### 3. Grant Accessibility Permission

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click **+** and add **Terminal** (or the app you'll run from)
3. Toggle **ON**

### 4. Run

```bash
./slack-watch.sh
```

Press `Ctrl+C` to stop — cleanup happens automatically.

---

## Sample Output

```
╔═══════════════════════════════════════════════════════════╗
║                    SLACK WATCH KEEPER                     ║
║                    Notification Monitor                   ║
╚═══════════════════════════════════════════════════════════╝

[04:20:00] [1/6] Checking alarm sound file...
  Found: alarm.mp3

[04:20:00] [2/6] Checking volume control...
  Volume control working

[04:20:00] [3/6] Checking network connectivity...
  Network OK (slack.com reachable)

[04:20:00] [4/6] Checking Slack...
  Slack is running
  Dock badge accessible (badge: "2")
  Unread notifications detected!

[04:20:00] [5/6] Checking battery...
  Battery: 85%

[04:20:00] [6/6] Starting caffeinate...
  Caffeinate running (PID: 12345)

[04:20:00] Slack Watch Keeper started (deadman mode)

[04:20:30] ALERT! 2 unread notification(s)
[04:20:30] Showing alert ...
[04:20:40] Playing alarm ...
[04:20:50] Acknowledged. Alarm stopped.
```

---

## Configuration

Edit the `CONFIG` section at the top of `slack-watch.scpt`:

```applescript
-- ===== CONFIG =====
property intervalSeconds : 300            -- Check interval in seconds
property soundFileName : "alarm.mp3"     -- Alarm sound file
property alertVolume : 90                -- Alarm volume level (0-100)
property debugMode : false               -- Verbose logging

-- Battery thresholds
property batteryWarningThreshold : 15    -- Show warning below this %
property batteryCriticalThreshold : 5    -- Block/exit below this % (if unplugged)

-- Alert modes
-- "regular": up to maxAlertAttempts, then exit as user is deemed away
-- "deadman": repeats alarm until acknowledged, with battery/time/badge safety checks
property alertMode : "deadman"
property maxAlertAttempts : 5

-- Alert window timing (24h format)
property alertStartHour : 19             -- Start hour
property alertStartMin : 30              -- Start minute
property alertEndHour : 12               -- End hour
property alertEndMin : 30                -- End minute

-- Active days (evening = from start time, morning = until end time)
property alertDaysEvening : {Monday, Tuesday, Wednesday, Thursday, Friday}
property alertDaysMorning : {Tuesday, Wednesday, Thursday, Friday, Saturday}

-- Network monitoring
property networkFailThreshold : 3        -- Consecutive failures before alerting
property networkRealertMinutes : 30      -- Re-alert interval while network is down
-- ==================
```

### Schedule Examples

**Weeknight On-Call (default)**
```
Mon 19:30 → Tue 12:30
Tue 19:30 → Wed 12:30
Wed 19:30 → Thu 12:30
Thu 19:30 → Fri 12:30
Fri 19:30 → Sat 12:30
```

**24/7 Coverage**
```applescript
property alertStartHour : 0
property alertStartMin : 0
property alertEndHour : 23
property alertEndMin : 59
property alertDaysEvening : {Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday}
property alertDaysMorning : {Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday}
```

**Business Hours Only**
```applescript
property alertStartHour : 9
property alertStartMin : 0
property alertEndHour : 18
property alertEndMin : 0
property alertDaysEvening : {Monday, Tuesday, Wednesday, Thursday, Friday}
property alertDaysMorning : {}
```

---

## Network Monitoring

Slack Watch Keeper monitors network connectivity to ensure reliable operation:

| Scenario | Behavior |
|----------|----------|
| Startup: no network | Blocks startup with error message |
| Loop: 1-2 failed checks | Logged (debug mode), continues monitoring |
| Loop: 3+ consecutive failures | Alert once, enter waiting mode |
| Waiting mode | Skip badge checks, monitor network silently |
| Waiting 30+ minutes | Re-alert (network still down) |
| Network restored | Log success, resume normal monitoring |

Example output when network fails:
```
[04:20:30] Network check failed (1/3)
[04:21:00] Network check failed (2/3)
[04:21:30] Network check failed (3/3)

[04:21:30] Network unreachable (slack.com)
[04:21:30] Slack Watch Keeper paused. Waiting for network...
[04:21:30] Playing alarm ...

[04:51:30] Network still down (30 min). Re-alerting...

[05:10:00] Network restored. Resuming monitoring.
```

---

## Slack Auto-Management

Slack Watch Keeper automatically manages the Slack application:

| Scenario | Behavior |
|----------|----------|
| Startup: Slack not running | Auto-start Slack, wait 15 seconds |
| Startup: Slack not installed | Error message, exit |
| Loop: Slack crashed | Auto-restart, wait 15 seconds |
| Loop: Dock badge unreadable | Retry next loop |

---

## Battery Safety

Slack Watch Keeper includes battery protection since `caffeinate` prevents auto-sleep:

| Battery Level | Plugged In | Behavior |
|---------------|------------|----------|
| >= 15% | Any | Normal operation |
| 5%-14% | Yes | Warning shown, continues |
| 5%-14% | No | Warning shown, continues |
| < 5% | Yes | Warning shown, continues |
| < 5% | No | Blocks startup or auto-exits |

Example output when battery is low:
```
[04:20:00] [5/6] Checking battery...
  Battery: 12%
    Please plug in. Notifier will auto-stop below 5%
```

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                      STARTUP CHECKS                         │
├─────────────────────────────────────────────────────────────┤
│  1. Verify alarm.mp3 exists                                 │
│  2. Test volume control                   │
│  3. Check network connectivity (slack.com)                  │
│  4. Check Slack (auto-start if needed) + Dock accessibility │
│  5. Verify battery levels                                   │
│  6. Start caffeinate (prevent sleep)                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    MAIN LOOP                                │
├─────────────────────────────────────────────────────────────┤
│  Every [intervalSeconds]:                                   │
│                                                             │
│  • Exit if outside alert window                             │
│  • Exit if battery critical and unplugged                   │
│  • Check network:                                           │
│      - 3+ failures → alert once, wait mode                  │
│      - 30+ min in wait → re-alert                           │
│      - Network restored → resume                            │
│  • Check if Slack crashed → auto-restart                    │
│  • Read Slack dock badge:                                   │
│      "" (empty)     → no action                             │
│      "•" (presence) → no action                             │
│      "3" (numeric)  → trigger alert flow                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      ON ALERT                               │
├─────────────────────────────────────────────────────────────┤
│  1. Set volume to alertVolume                               │
│  2. Prealarm dialog (10s)                                   │
│     • If acknowledged: stop                                 │
│     • Else: play alarm                                      │
│  3. Alarm dialog:                                           │
│     • Regular mode: plays once per attempt (bounded retries)│
│     • Deadman mode: loops alarm until acknowledged          │
│       with safety checks (battery/time/badge) each cycle    │
└─────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
slack-watch/
├── slack-watch.scpt    # Main AppleScript 
├── slack-watch.sh      # Shell wrapper 
├── alarm.mp3           # Your alarm sound 
├── README.md           # This file

```

---

## Troubleshooting

### "osascript is not allowed assistive access"

```
System Settings → Privacy & Security → Accessibility → Add Terminal → Toggle ON
```

### No alarm plays

1. Verify Slack shows a **numeric** badge (like `3`), not just the presence dot
2. Confirm current time is within your alert window
3. Run with `debugMode : true` to see loop details

### Network alert keeps firing

Check your internet connection. The script pings `slack.com` directly — ensure:
- You're connected to WiFi/Ethernet
- No firewall blocking outbound HTTPS
- VPN is working if required

### Slack won't auto-start

Ensure Slack is installed in `/Applications/Slack.app`. The script uses `tell application "Slack" to activate`.

### Alarm doesn't stop

The alarm plays for the full duration of `alarm.mp3`. Click "Acknowledge" to stop it.

### Orphaned caffeinate process

If you killed the script unexpectedly without a cleanup:
```bash
pkill caffeinate
```

---

## Why Not Just Use Slack's Built-in Notifications?

| Feature | Slack Notifications | Slack Watch Keeper |
|---------|---------------------|-------------|
| Works when Mac is asleep | No | Yes (caffeinate) |
| Overrides Do Not Disturb | No | Yes |
| Forces volume up | No | Yes |
| Custom alarm sound | No | Yes |
| Scheduled active hours | No | Yes |
| Battery protection | N/A | Yes |
| Network monitoring | N/A | Yes |
| Auto-restart on crash | N/A | Yes |

---

## License

The Unlicense

---

## Contributing

Contributions welcome! Feel free to open issues or submit PRs.

---

<p align="center">
  <strong>Built for engineers who can't afford missed Slack alerts.</strong><br>
</p>
