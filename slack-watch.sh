#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#                       Slack Watch Keeper
#             Overnight Notification Monitor
# ═══════════════════════════════════════════════════════════════
# This wrapper handles Ctrl+C cleanup properly.
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/slack-watch.scpt"
PID_FILE="/tmp/slack-watch-caffeinate.pid"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

# Timestamp function
timestamp() {
    date "+[%H:%M:%S]"
}

cleanup() {
    echo ""
    echo -e "${YELLOW}┌─────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│         SHUTTING DOWN           │${NC}"
    echo -e "${YELLOW}└─────────────────────────────────┘${NC}"
    
    if [[ -f "$PID_FILE" ]]; then
        CAFF_PID=$(cat "$PID_FILE")
        if [[ -n "$CAFF_PID" ]] && ps -p "$CAFF_PID" > /dev/null 2>&1; then
            kill "$CAFF_PID" 2>/dev/null
            echo -e "${GREEN}$(timestamp) ✓ Caffeinate terminated (PID: $CAFF_PID)${NC}"
        else
            echo -e "${DIM}$(timestamp) ⚠ Caffeinate already stopped${NC}"
        fi
        rm -f "$PID_FILE"
        echo -e "${GREEN}$(timestamp) ✓ PID file removed${NC}"
    else
        echo -e "${DIM}$(timestamp) ⚠ No PID file found${NC}"
    fi
    
    echo -e "${GREEN}$(timestamp) ✓ Slack Watch Keeper stopped${NC}"
    echo ""
    exit 0
}

# Trap signals
trap cleanup SIGINT SIGTERM

# Verify script exists
if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo -e "${RED}✗ Script not found: $SCRIPT_PATH${NC}"
    exit 1
fi

# Run AppleScript
osascript "$SCRIPT_PATH"
EXIT_CODE=$?

# Normal exit cleanup
if [[ -f "$PID_FILE" ]]; then
    cleanup
fi

exit $EXIT_CODE
