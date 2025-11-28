#!/usr/bin/env bash
# Pick a random Wallpaper Engine wallpaper

XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_FILE="$XDG_CACHE_HOME/quickshell/we-wallpapers-index.json"
IGNORED_FILE="$XDG_CACHE_HOME/quickshell/we-wallpapers-ignored.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"

# Check cache exists
if [ ! -f "$CACHE_FILE" ]; then
    echo "WE wallpapers cache not found: $CACHE_FILE"
    exit 1
fi

# Get all workshop IDs
ALL_IDS=$(jq -r '.wallpapers[].workshopId' "$CACHE_FILE")

# Get ignored IDs (if file exists)
if [ -f "$IGNORED_FILE" ]; then
    IGNORED_IDS=$(jq -r '.ignored[]? // empty' "$IGNORED_FILE" 2>/dev/null)
else
    IGNORED_IDS=""
fi

# Filter out ignored IDs
AVAILABLE_IDS=""
for id in $ALL_IDS; do
    if ! echo "$IGNORED_IDS" | grep -q "^${id}$"; then
        AVAILABLE_IDS="$AVAILABLE_IDS $id"
    fi
done

# Convert to array and pick random
IDS_ARRAY=($AVAILABLE_IDS)
COUNT=${#IDS_ARRAY[@]}

if [ "$COUNT" -eq 0 ]; then
    echo "No available wallpapers"
    exit 1
fi

RANDOM_INDEX=$((RANDOM % COUNT))
RANDOM_ID="${IDS_ARRAY[$RANDOM_INDEX]}"

echo "Randomly selected: $RANDOM_ID"

# Get current mode from gsettings
MODE=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
if [ "$MODE" = "prefer-dark" ]; then
    MODE_FLAG="dark"
else
    MODE_FLAG="light"
fi

# Apply wallpaper
"$SCRIPT_DIR/apply-we-wallpaper.sh" --id "$RANDOM_ID" --mode "$MODE_FLAG"
