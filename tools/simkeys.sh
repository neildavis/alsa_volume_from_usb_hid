#!/bin/bash

# Configuration & Defaults
MAX_REPEAT=12
SLEEP_DURATION=0.5
DEVICE=""
VERBOSE=false

# Function to display help information
usage() {
    echo "Usage: $0 [OPTIONS] [COMMANDS...]"
    echo ""
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -v              Enable verbose mode"
    echo "  -s VALUE        Sleep duration (default: 0.5)"
    echo "  -i DEVICE       Input device path"
    echo ""
    echo "Commands:"
    echo "  up[:N]          Volume Up (N times, max $MAX_REPEAT)"
    echo "  down[:N]        Volume Down (N times, max $MAX_REPEAT)"
    echo "  mute[:N]        Mute (N times, max $MAX_REPEAT)"
    exit 0
}

# 1. Show help if no arguments
[[ $# -eq 0 || "$1" == "--help" ]] && usage

# 2. Check for sudo privileges
if [ "$EUID" -ne 0 ]; then
    sudo -v || { echo "Sudo required. Exiting."; exit 1; }
fi

# 3. Check for evemu-event
command -v evemu-event &> /dev/null || { 
    echo "Error: evemu-tools not found. Install with: sudo apt install evemu-tools"; 
    exit 1; 
}

# 4. Parse options
while getopts "s:i:hv" opt; do
  case $opt in
    s)
      if [[ ! "$OPTARG" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          echo "Error: Sleep duration must be a number." >&2
          exit 1
      fi
      SLEEP_DURATION="$OPTARG"
      ;;
    i) DEVICE="$OPTARG" ;;
    v) VERBOSE=true ;;
    h) usage ;;
    \?) exit 1 ;;
  esac
done

shift $((OPTIND -1))

# 5. Auto-detect device
if [ -z "$DEVICE" ]; then
    KBD_EVENT=$(grep -E 'Handlers=.*kbd' /proc/bus/input/devices | grep -o 'event[0-9]\+' | head -n 1)
    [ -n "$KBD_EVENT" ] && DEVICE="/dev/input/$KBD_EVENT"
fi

# 6. Validate device
if [[ ! -c "$DEVICE" ]]; then
    echo "Error: Device '$DEVICE' is not a valid character device." >&2
    exit 1
fi

[ "$VERBOSE" = true ] && echo "Targeting device: $DEVICE"

# 7. Process commands
for arg in "$@"; do
    IFS=':' read -r cmd count <<< "$arg"
    
    # Validation: Default to 1 if count is missing or not a number
    [[ ! "$count" =~ ^[0-9]+$ ]] && count=1

    # Safety Check: Cap at MAX_REPEAT
    if [ "$count" -gt "$MAX_REPEAT" ]; then
        [ "$VERBOSE" = true ] && echo "Notice: Capping repeat count from $count to $MAX_REPEAT."
        count=$MAX_REPEAT
    fi

    case "$cmd" in
        "up")    KEY="KEY_VOLUMEUP" ;;
        "down")  KEY="KEY_VOLUMEDOWN" ;;
        "mute")  KEY="KEY_MUTE" ;;
        *)       continue ;;
    esac

    for ((i=1; i<=count; i++)); do
        if [ "$VERBOSE" = true ]; then
            echo "[$i/$count] Sending $KEY..."
        fi

        sudo evemu-event "$DEVICE" --type EV_KEY --code "$KEY" --value 1 --sync
        sudo evemu-event "$DEVICE" --type EV_KEY --code "$KEY" --value 0 --sync
        
        sleep "$SLEEP_DURATION"
    done
done