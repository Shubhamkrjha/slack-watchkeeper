-- ═══════════════════════════════════════════════════════════════════════════
--
--                         SLACK WATCH KEEPER
--                         Notification Monitor
--
--                    
--
-- ═══════════════════════════════════════════════════════════════════════════


-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │                              CONFIGURATION                                │
-- └───────────────────────────────────────────────────────────────────────────┘

property intervalSeconds : 30
property soundFileName : "alarm.mp3"
property alertVolume : 55
property debugMode : false
property pidFile : "/tmp/slack-watch-caffeinate.pid"

-- Battery thresholds
property batteryWarningThreshold : 15
property batteryCriticalThreshold : 5

-- Alert modes: "regular" (bounded retries) or "deadman" (loops until acknowledged)
property alertMode : "deadman"
property maxAlertAttempts : 5

-- Alert window (24h format)
property alertStartHour : 19
property alertStartMin : 30
property alertEndHour : 12
property alertEndMin : 30

-- Active days
property alertDaysEvening : {Monday, Tuesday, Wednesday, Thursday, Friday}
property alertDaysMorning : {Tuesday, Wednesday, Thursday, Friday, Saturday}

-- Network monitoring
property networkFailThreshold : 3
property networkRealertMinutes : 30


-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │                            GLOBAL VARIABLES                               │
-- └───────────────────────────────────────────────────────────────────────────┘

global caffeinatePID
global soundFile
global alertAttemptCount
global networkFailCount
global networkWaiting
global lastNetworkAlertTime

set caffeinatePID to ""
set alertAttemptCount to 0
set networkFailCount to 0
set networkWaiting to false
set lastNetworkAlertTime to 0

set scriptPath to POSIX path of (path to me)
set scriptDir to do shell script "dirname " & quoted form of scriptPath
set soundFile to scriptDir & "/" & soundFileName


-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │                           UTILITY FUNCTIONS                               │
-- └───────────────────────────────────────────────────────────────────────────┘

on nowStamp()
	set d to current date
	set h to text -2 thru -1 of ("0" & hours of d)
	set m to text -2 thru -1 of ("0" & minutes of d)
	set s to text -2 thru -1 of ("0" & seconds of d)
	return "[" & h & ":" & m & ":" & s & "]"
end nowStamp

on getUnixTime()
	return (do shell script "date +%s") as integer
end getUnixTime

on formatTime(h, m)
	return text -2 thru -1 of ("0" & h) & ":" & text -2 thru -1 of ("0" & m)
end formatTime

on toMinutes(h, m)
	return h * 60 + m
end toMinutes


-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │                           TERMINAL OUTPUT                                 │
-- └───────────────────────────────────────────────────────────────────────────┘

on printLog(msg)
	try
		do shell script "echo " & quoted form of msg & " > /dev/tty"
	end try
end printLog

on printSuccess(msg)
	try
		do shell script "/bin/bash -c 'echo -e \"\\033[0;32m" & msg & "\\033[0m\" > /dev/tty'"
	end try
end printSuccess

on printError(msg)
	try
		do shell script "/bin/bash -c 'echo -e \"\\033[0;31m" & msg & "\\033[0m\" > /dev/tty'"
	end try
end printError

on printWarning(msg)
	try
		do shell script "/bin/bash -c 'echo -e \"\\033[1;33m" & msg & "\\033[0m\" > /dev/tty'"
	end try
end printWarning

on printInfo(msg)
	try
		do shell script "/bin/bash -c 'echo -e \"\\033[0;36m" & msg & "\\033[0m\" > /dev/tty'"
	end try
end printInfo

on printDim(msg)
	try
		do shell script "echo " & quoted form of msg & " > /dev/tty"
	end try
end printDim

on printBold(msg)
	try
		do shell script "/bin/bash -c 'echo -e \"\\033[1m" & msg & "\\033[0m\" > /dev/tty'"
	end try
end printBold


-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │                            AUDIO CONTROL                                  │
-- └───────────────────────────────────────────────────────────────────────────┘

on setAlertVolume()
	set volume output volume alertVolume without output muted
end setAlertVolume

on getAlarmDuration()
	global soundFile
	try
		set durationStr to do shell script "afinfo " & quoted form of soundFile & " 2>/dev/null | grep duration | awk '{print int($3)}'"
		if durationStr is "" then return 30
		return durationStr as integer
	on error
		return 30
	end try
end getAlarmDuration


-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │                          NETWORK MONITORING                               │
-- └───────────────────────────────────────────────────────────────────────────┘

on checkNetwork()
	try
		set httpCode to do shell script "curl -s --max-time 5 -o /dev/null -w '%{http_code}' https://slack.com 2>/dev/null || echo '000'"
		return httpCode is in {"200", "301", "302", "303", "307", "308"}
	on error
		return false
	end try
end checkNetwork

on playNetworkAlert()
	global soundFile
	
	set alarmPID to do shell script "nohup afplay " & quoted form of soundFile & " </dev/null >/dev/null 2>&1 & echo $!"
	set dialogTimeout to getAlarmDuration()
	
	set alertMessage to "Network Unreachable" & return & return & ¬
		"Cannot reach slack.com" & return & ¬
		"Slack Watch Keeper is paused." & return & return & ¬
		"Will auto-resume when network returns." & return & ¬
		"(Re-alert in " & networkRealertMinutes & " minutes if still down)" & return & return & ¬
		"Click to acknowledge."
	
	try
		display dialog alertMessage buttons {"Acknowledge"} default button 1 giving up after dialogTimeout with title "Slack Watch Keeper"
		set dialogResult to result
		do shell script "(kill -9 " & alarmPID & " 2>/dev/null || true) &"
		if not (gave up of dialogResult) then
			printSuccess(nowStamp() & " ✓ Network alert acknowledged")
		end if
	on error
		do shell script "(kill -9 " & alarmPID & " 2>/dev/null || true) &"
	end try
end playNetworkAlert


-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │                          SLACK MANAGEMENT                                 │
-- └───────────────────────────────────────────────────────────────────────────┘

on isSlackRunning()
	try
		tell application "System Events"
			return (name of processes) contains "Slack"
		end tell
	on error
		return false
	end try
end isSlackRunning

on startSlack()
	try
		do shell script "open -g -a Slack"
		return true
	on error errMsg
		printError("  ✗ Failed to start Slack: " & errMsg)
		return false
	end try
end startSlack

on isNumericBadge(badgeText)
	if badgeText is "" then return false
	if badgeText is missing value then return false
	try
		set testNum to badgeText as integer
		return (testNum > 0)
	on error
		return false
	end try
end isNumericBadge


-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │                          BATTERY MONITORING                               │
-- └───────────────────────────────────────────────────────────────────────────┘

on getBatteryInfo()
	try
		set batteryOutput to do shell script "pmset -g batt"
		set percentStr to do shell script "echo " & quoted form of batteryOutput & " | grep -o '[0-9]*%' | head -1 | tr -d '%'"
		
		if percentStr is "" then
			set batteryPercent to 100
		else
			set batteryPercent to percentStr as integer
		end if
		
		set isOnAC to (batteryOutput contains "AC Power")
		set isDischarging to (batteryOutput contains "discharging")
		set isCharging to (isOnAC or not isDischarging)
		
		return {batteryPercent, isCharging}
	on error
		return {100, true}
	end try
end getBatteryInfo

on isBatteryCritical()
	set {batteryPercent, isCharging} to getBatteryInfo()
	if isCharging then return false
	return batteryPercent < batteryCriticalThreshold
end isBatteryCritical


-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │                           TIME WINDOW LOGIC                               │
-- └───────────────────────────────────────────────────────────────────────────┘

on shouldExitNow()
	set d to current date
	set mins to (hours of d) * 60 + (minutes of d)
	set startMins to toMinutes(alertStartHour, alertStartMin)
	set endMins to toMinutes(alertEndHour, alertEndMin)
	
	if endMins < startMins then
		if mins > endMins and mins < startMins then return true
	else
		if mins < startMins or mins > endMins then return true
	end if
	
	return false
end shouldExitNow

on isWithinAlertWindow()
	set d to current date
	set wd to weekday of d
	set mins to (hours of d) * 60 + (minutes of d)
	set startMins to toMinutes(alertStartHour, alertStartMin)
	set endMins to toMinutes(alertEndHour, alertEndMin)
	
	if wd is in alertDaysEvening then
		if mins ≥ startMins then return true
	end if
	
	if wd is in alertDaysMorning then
		if mins ≤ endMins then return true
	end if
	
	return false
end isWithinAlertWindow

on getWindowStatus()
	set d to current date
	set wd to weekday of d as string
	set h to hours of d
	set m to minutes of d
	set timeStr to wd & " " & formatTime(h, m)
	
	if isWithinAlertWindow() then
		return "ACTIVE (" & timeStr & ")"
	else
		return "INACTIVE (" & timeStr & ")"
	end if
end getWindowStatus

on getWindowDescription()
	return formatTime(alertStartHour, alertStartMin) & " → " & formatTime(alertEndHour, alertEndMin)
end getWindowDescription


-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │                              ALARM LOGIC                                  │
-- └───────────────────────────────────────────────────────────────────────────┘

on playAlarmWithDialog(badgeCount, attemptNum, maxAttempts)
	global soundFile
	
	-- Phase 1: Prealarm (10 second grace period)
	if alertMode is "deadman" then
		set prealarmMessage to "Slack Alert!" & return & return & ¬
			badgeCount & " unread notification(s)" & return & return & ¬
			"Alarm will start in 10 seconds." & return & return & ¬
			"Click to acknowledge."
	else
		set prealarmMessage to "Slack Alert!" & return & return & ¬
			badgeCount & " unread notification(s)" & return & ¬
			"Attempt " & attemptNum & " of " & maxAttempts & return & return & ¬
			"Alarm will start in 10 seconds." & return & return & ¬
			"Click to acknowledge."
	end if
	
	try
		display dialog prealarmMessage buttons {"Acknowledge"} default button 1 giving up after 10 with title "Slack Watch Keeper"
		set dialogResult to result
		if not (gave up of dialogResult) then
			printSuccess(nowStamp() & " ✓ Acknowledged.")
			return true
		end if
	on error
		-- Continue to alarm
	end try
	
	-- Phase 2: Alarm playing
	set dialogTimeout to getAlarmDuration()
	printWarning(nowStamp() & " Playing alarm ...")
	
	repeat
		set alarmPID to do shell script "nohup afplay " & quoted form of soundFile & " </dev/null >/dev/null 2>&1 & echo $!"
		
		if alertMode is "deadman" then
			set alarmMessage to "Slack Alert!" & return & return & ¬
				badgeCount & " unread notification(s)" & return & return & ¬
				"Click to acknowledge."
		else
			set alarmMessage to "Slack Alert!" & return & return & ¬
				badgeCount & " unread notification(s)" & return & ¬
				"Attempt " & attemptNum & " of " & maxAttempts & return & return & ¬
				"Click to acknowledge."
		end if
		
		try
			display dialog alarmMessage buttons {"Acknowledge"} default button 1 giving up after dialogTimeout with title "Slack Watch Keeper"
			set dialogResult to result
			do shell script "(kill -9 " & alarmPID & " 2>/dev/null || true) &"
			
			if gave up of dialogResult then
				if alertMode is "deadman" then
					-- Safety checks before replay
					if isBatteryCritical() then
						printLog("")
						printError(nowStamp() & " ✗ Battery critical — stopping alarm")
						return false
					end if
					
					if shouldExitNow() then
						printLog("")
						printInfo(nowStamp() & " Outside alert window — stopping alarm")
						return false
					end if
					
					set currentBadge to ""
					try
						tell application "System Events"
							tell process "Dock"
								tell UI element "Slack" of list 1
									set currentBadge to value of attribute "AXStatusLabel"
								end tell
							end tell
						end tell
					end try
					if currentBadge is missing value then set currentBadge to ""
					
					if not isNumericBadge(currentBadge) then
						printSuccess(nowStamp() & " ✓ Notifications cleared.")
						return true
					end if
				else
					printDim(nowStamp() & " Alarm stopped playing.")
					return false
				end if
			else
				printSuccess(nowStamp() & " ✓ Acknowledged. Alarm stopped.")
				return true
			end if
		on error
			do shell script "(kill -9 " & alarmPID & " 2>/dev/null || true) &"
			if alertMode is not "deadman" then return false
			if isBatteryCritical() then return false
			if shouldExitNow() then return false
		end try
	end repeat
end playAlarmWithDialog


-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │                               CLEANUP                                     │
-- └───────────────────────────────────────────────────────────────────────────┘

on cleanup()
	printLog("")
	printWarning("┌─────────────────────────────────┐")
	printWarning("│         SHUTTING DOWN           │")
	printWarning("└─────────────────────────────────┘")
	
	if caffeinatePID is not "" then
		try
			do shell script "kill " & caffeinatePID & " 2>/dev/null || true"
			printSuccess(nowStamp() & " ✓ Caffeinate terminated (PID: " & caffeinatePID & ")")
		on error
			printDim(nowStamp() & " ⚠ Caffeinate already stopped")
		end try
	end if
	
	try
		do shell script "rm -f " & quoted form of pidFile
		printSuccess(nowStamp() & " ✓ PID file removed")
	end try
	
	printSuccess(nowStamp() & " ✓ Slack Watch Keeper stopped")
	printLog("")
end cleanup

on quit
	cleanup()
	continue quit
end quit


-- ═══════════════════════════════════════════════════════════════════════════
--                            STARTUP SEQUENCE
-- ═══════════════════════════════════════════════════════════════════════════

printLog("")
printInfo("╔═══════════════════════════════════════════════════════════╗")
printInfo("║               SLACK WATCH KEEPER                          ║")
printInfo("║               Notification Monitor                        ║")
printInfo("╚═══════════════════════════════════════════════════════════╝")
printLog("")

set allChecksPassed to true


-- [1/6] Alarm file
printDim(nowStamp() & " [1/6] Checking alarm sound file...")
try
	set fileExists to do shell script "test -f " & quoted form of soundFile & " && echo 'yes' || echo 'no'"
	if fileExists is "yes" then
		set alarmDuration to getAlarmDuration()
		if alarmDuration < 1 then
			printError("  ✗ Found: " & soundFileName & " (" & alarmDuration & "s)")
			printError("    Alarm file too short (must be >= 1 second)")
			set allChecksPassed to false
		else
			printSuccess("  ✓ Found: " & soundFileName & " (" & alarmDuration & "s)")
		end if
	else
		printError("  ✗ Not found: " & soundFile)
		set allChecksPassed to false
	end if
on error errMsg
	printError("  ✗ " & errMsg)
	set allChecksPassed to false
end try


-- [2/6] Volume control
printLog("")
printDim(nowStamp() & " [2/6] Checking volume control...")
try
	set volSettings to get volume settings
	set originalVol to output volume of volSettings
	set originalMuted to output muted of volSettings
	
	if debugMode then
		printDim("    Before: " & originalVol & "% | Muted: " & originalMuted)
	end if
	
	set volume output volume 50
	set testVol to output volume of (get volume settings)
	set volume with output muted
	set testMuted to output muted of (get volume settings)
	set volume without output muted
	set testUnmuted to output muted of (get volume settings)
	
	if debugMode then
		printDim("    After:  50% | Muted: false")
	end if
	
	set volume output volume originalVol
	if originalMuted then
		set volume with output muted
	else
		set volume without output muted
	end if
	
	if testVol is 50 and testMuted is true and testUnmuted is false then
		printSuccess("  ✓ Volume control working")
		if debugMode then
			printDim("    Restored: " & originalVol & "% | Muted: " & originalMuted)
		end if
	else
		printError("  ✗ Volume control test failed")
		set allChecksPassed to false
	end if
on error errMsg
	printError("  ✗ " & errMsg)
	set allChecksPassed to false
end try


-- [3/6] Network connectivity
printLog("")
printDim(nowStamp() & " [3/6] Checking network (slack.com)...")
if checkNetwork() then
	printSuccess("  ✓ Network OK")
else
	printError("  ✗ Cannot reach slack.com")
	printError("    Please check your internet connection")
	set allChecksPassed to false
end if


-- [4/6] Slack
printLog("")
printDim(nowStamp() & " [4/6] Checking Slack...")
try
	if not isSlackRunning() then
		printWarning("  ⚠ Slack not running. Starting...")
		if startSlack() then
			printDim("    Waiting 15 seconds for Slack to start...")
			delay 15
			if isSlackRunning() then
				printSuccess("  ✓ Slack started")
			else
				printError("  ✗ Slack failed to start")
				set allChecksPassed to false
			end if
		else
			set allChecksPassed to false
		end if
	else
		printSuccess("  ✓ Slack is running")
	end if
	
	if allChecksPassed then
		try
			tell application "System Events"
				tell process "Dock"
					tell UI element "Slack" of list 1
						set testBadge to value of attribute "AXStatusLabel"
					end tell
				end tell
			end tell
			
			if testBadge is missing value or testBadge is "" then
				printSuccess("  ✓ Dock badge accessible (no active notifications)")
			else if testBadge is "•" then
				printSuccess("  ✓ Dock badge accessible (no active notifications)")
			else
				printSuccess("  ✓ Dock badge accessible (badge: \"" & testBadge & "\")")
				if isNumericBadge(testBadge) then
					printWarning("  ⚠ Unread notifications detected!")
				end if
			end if
		on error accessErr
			printError("  ✗ Cannot read Dock badge")
			printError("    " & accessErr)
			printLog("")
			printWarning("  FIX: System Settings → Privacy → Accessibility")
			printWarning("       Add Script Editor or Terminal")
			set allChecksPassed to false
		end try
	end if
on error errMsg
	printError("  ✗ " & errMsg)
	set allChecksPassed to false
end try


-- [5/6] Battery
printLog("")
printDim(nowStamp() & " [5/6] Checking battery...")
set {currentBattery, currentCharging} to getBatteryInfo()

if currentCharging then
	set batteryDisplay to "🔋 " & currentBattery & "% 🔌"
else
	set batteryDisplay to "🔋 " & currentBattery & "%"
end if

if currentBattery < batteryCriticalThreshold then
	if currentCharging then
		printWarning("  ⚠ " & batteryDisplay)
		printWarning("    Keep plugged in. Auto-stop below " & batteryCriticalThreshold & "% if unplugged")
	else
		printError("  ✗ " & batteryDisplay)
		printError("    Cannot start below " & batteryCriticalThreshold & "%. Please plug in")
		set allChecksPassed to false
	end if
else if currentBattery < batteryWarningThreshold then
	if currentCharging then
		printWarning("  ⚠ " & batteryDisplay)
		printWarning("    Keep plugged in. Auto-stop below " & batteryCriticalThreshold & "% if unplugged")
	else
		printWarning("  ⚠ " & batteryDisplay)
		printWarning("    Please plug in. Auto-stop below " & batteryCriticalThreshold & "%")
	end if
else
	printSuccess("  ✓ " & batteryDisplay)
end if


-- [6/6] Caffeinate
if allChecksPassed then
	printLog("")
	printDim(nowStamp() & " [6/6] Starting caffeinate...")
	try
		set caffeinatePID to do shell script "nohup caffeinate -dimsu </dev/null >/dev/null 2>&1 & echo $!"
		delay 0.3
		
		set isRunning to do shell script "ps -p " & caffeinatePID & " >/dev/null 2>&1 && echo 'yes' || echo 'no'"
		
		if isRunning is "yes" then
			do shell script "echo " & caffeinatePID & " > " & quoted form of pidFile
			printSuccess("  ✓ Caffeinate running (PID: " & caffeinatePID & ")")
		else
			printError("  ✗ Caffeinate failed to start")
			set allChecksPassed to false
		end if
	on error errMsg
		printError("  ✗ " & errMsg)
		set allChecksPassed to false
	end try
end if


-- Startup verdict
printLog("")

if not allChecksPassed then
	printError("  ✗ STARTUP FAILED")
	printLog("")
	if caffeinatePID is not "" then
		try
			do shell script "kill " & caffeinatePID & " 2>/dev/null || true"
		end try
	end if
	return
end if

if debugMode then
	printDim("┌─────────────────────────────────────────────────────────┐")
	printDim("│  Interval:     " & intervalSeconds & " seconds")
	printDim("│  Alert window: " & getWindowDescription())
	printDim("│  Alert volume: " & alertVolume & "%")
	printDim("│  Status:       " & getWindowStatus())
	printDim("└─────────────────────────────────────────────────────────┘")
	printLog("")
end if


-- ═══════════════════════════════════════════════════════════════════════════
--                              MAIN LOOP
-- ═══════════════════════════════════════════════════════════════════════════

if alertMode is "deadman" then
	printSuccess(nowStamp() & " Slack Watch Keeper started (deadman mode)")
else
	printSuccess(nowStamp() & " Slack Watch Keeper started (max " & maxAlertAttempts & " attempts)")
end if
printLog("")

set loopCount to 0

repeat
	set loopCount to loopCount + 1
	
	
	-- Safety: Time window check
	if shouldExitNow() then
		printInfo(nowStamp() & " Outside alert window — auto-exiting")
		cleanup()
		exit repeat
	end if
	
	
	-- Safety: Battery check
	set {loopBattery, loopCharging} to getBatteryInfo()
	
	if loopCharging then
		set loopBatteryDisplay to "🔋 " & loopBattery & "% 🔌"
	else
		set loopBatteryDisplay to "🔋 " & loopBattery & "%"
	end if
	
	if not loopCharging and loopBattery < batteryCriticalThreshold then
		printLog("")
		printError(nowStamp() & " ✗ " & loopBatteryDisplay & " — Battery below " & batteryCriticalThreshold & "%")
		printWarning(nowStamp() & " Auto-exiting. Please plug in and restart.")
		cleanup()
		exit repeat
	end if
	
	if debugMode then
		printDim(nowStamp() & " " & loopBatteryDisplay)
	end if
	
	
	-- Network check
	set networkOK to checkNetwork()
	
	if not networkOK then
		set networkFailCount to networkFailCount + 1
		
		if debugMode then
			printWarning(nowStamp() & " Network check failed (" & networkFailCount & "/" & networkFailThreshold & ")")
		end if
		
		if networkFailCount >= networkFailThreshold then
			if not networkWaiting then
				printLog("")
				printError(nowStamp() & " ✗ Network unreachable (slack.com)")
				printWarning(nowStamp() & " Paused. Waiting for network...")
				
				setAlertVolume()
				playNetworkAlert()
				
				set networkWaiting to true
				set lastNetworkAlertTime to getUnixTime()
			else
				set currentTime to getUnixTime()
				set elapsedMinutes to (currentTime - lastNetworkAlertTime) / 60
				
				if elapsedMinutes >= networkRealertMinutes then
					printLog("")
					printWarning(nowStamp() & " Network still down (" & (round elapsedMinutes) & " min). Re-alerting...")
					
					setAlertVolume()
					playNetworkAlert()
					
					set lastNetworkAlertTime to currentTime
				end if
			end if
		end if
		
		if debugMode then
			printDim(nowStamp() & " Skipping badge check (network down)")
		end if
		
	else
		if networkWaiting then
			printLog("")
			printSuccess(nowStamp() & " ✓ Network restored. Monitoring resumed.")
			set networkWaiting to false
		end if
		set networkFailCount to 0
		
		
		-- Slack running check
		if not isSlackRunning() then
			printLog("")
			printWarning(nowStamp() & " Slack not running. Restarting...")
			if startSlack() then
				delay 15
				if isSlackRunning() then
					printSuccess(nowStamp() & " ✓ Slack restarted")
				else
					printError(nowStamp() & " ✗ Failed to restart Slack")
				end if
			end if
		end if
		
		
		-- Badge check
		set inWindow to isWithinAlertWindow()
		
		if debugMode then
			printLog("")
			printDim(nowStamp() & " ─── Loop #" & loopCount & " ───")
			if inWindow then
				printSuccess(nowStamp() & " Window: ACTIVE")
			else
				printDim(nowStamp() & " Window: INACTIVE (skipping)")
			end if
		end if
		
		if inWindow then
			set badge to ""
			
			try
				tell application "System Events"
					tell process "Dock"
						tell UI element "Slack" of list 1
							set badge to value of attribute "AXStatusLabel"
						end tell
					end tell
				end tell
			on error
				set badge to ""
			end try
			
			if badge is missing value then set badge to ""
			
			if debugMode then
				if badge is "" then
					printDim(nowStamp() & " Badge: (none)")
				else
					printDim(nowStamp() & " Badge: \"" & badge & "\"")
				end if
			end if
			
			if badge is not "" and badge is not "•" then
				if isNumericBadge(badge) then
					set alertAttemptCount to alertAttemptCount + 1
					
					printLog("")
					printError(nowStamp() & " ALERT! " & badge & " unread notification(s)")
					
					if debugMode then
						printWarning(nowStamp() & " Showing alert (attempt " & alertAttemptCount & "/" & maxAlertAttempts & ")...")
					else
						printWarning(nowStamp() & " Showing alert...")
					end if
					
					setAlertVolume()
					set acknowledged to playAlarmWithDialog(badge, alertAttemptCount, maxAlertAttempts)
					
					if acknowledged then
						set alertAttemptCount to 0
					else
						if alertMode is "deadman" then
							if debugMode then
								printDim(nowStamp() & " Will retry next loop...")
							end if
						else
							if alertAttemptCount ≥ maxAlertAttempts then
								printLog("")
								printError(nowStamp() & " ✗ Max attempts reached (" & maxAlertAttempts & ")")
								printWarning(nowStamp() & " Exiting — user appears away")
								cleanup()
								return
							else
								if debugMode then
									printDim(nowStamp() & " " & (maxAlertAttempts - alertAttemptCount) & " attempts left")
								end if
							end if
						end if
					end if
				else
					set alertAttemptCount to 0
					if debugMode then
						printDim(nowStamp() & " Badge not numeric — ignoring")
					end if
				end if
			else
				if alertAttemptCount > 0 then
					printSuccess(nowStamp() & " ✓ Notifications cleared.")
				end if
				set alertAttemptCount to 0
				
				if debugMode then
					if badge is "•" then
						printDim(nowStamp() & " Presence dot — no action")
					else
						printDim(nowStamp() & " No notifications — no action")
					end if
				end if
			end if
		end if
	end if
	
	if debugMode then
		printDim(nowStamp() & " Sleeping " & intervalSeconds & "s...")
	end if
	
	delay intervalSeconds
end repeat
