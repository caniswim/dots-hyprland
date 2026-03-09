#!/bin/bash
# Adjust workspace gaps dynamically (gapsout: top right bottom left)
# Usage: adjust-gaps.sh <h|v|u|d|l|r> <+|->
# h = horizontal (left+right), v = vertical (top+bottom)
# u/d/l/r = shift tiling: u=up, d=down, l=left, r=right
# + = increase, - = decrease (ignored for u/d/l/r)
# Applies to ALL workspaces on the active monitor.

AXIS="$1"
DIR="$2"
STEP=10

MONITOR=$(hyprctl activeworkspace -j | jq -r '.monitor')
STATE_DIR="/tmp/hypr-gaps"
STATE_FILE="$STATE_DIR/mon-$MONITOR"

mkdir -p "$STATE_DIR"

# Default gaps
if [[ -f "$STATE_FILE" ]]; then
    read -r TOP RIGHT BOTTOM LEFT < "$STATE_FILE"
else
    TOP=80 RIGHT=80 BOTTOM=80 LEFT=80
fi

case "$AXIS" in
    h)
        if [[ "$DIR" == "+" ]]; then
            LEFT=$((LEFT + STEP))
            RIGHT=$((RIGHT + STEP))
        else
            LEFT=$((LEFT - STEP))
            RIGHT=$((RIGHT - STEP))
        fi
        ;;
    v)
        if [[ "$DIR" == "+" ]]; then
            TOP=$((TOP + STEP))
            BOTTOM=$((BOTTOM + STEP))
        else
            TOP=$((TOP - STEP))
            BOTTOM=$((BOTTOM - STEP))
        fi
        ;;
    u) TOP=$((TOP - STEP)); BOTTOM=$((BOTTOM + STEP)) ;;
    d) TOP=$((TOP + STEP)); BOTTOM=$((BOTTOM - STEP)) ;;
    l) LEFT=$((LEFT - STEP)); RIGHT=$((RIGHT + STEP)) ;;
    r) LEFT=$((LEFT + STEP)); RIGHT=$((RIGHT - STEP)) ;;
esac

# Clamp to minimum 0
TOP=$((TOP < 0 ? 0 : TOP))
RIGHT=$((RIGHT < 0 ? 0 : RIGHT))
BOTTOM=$((BOTTOM < 0 ? 0 : BOTTOM))
LEFT=$((LEFT < 0 ? 0 : LEFT))

echo "$TOP $RIGHT $BOTTOM $LEFT" > "$STATE_FILE"

# Apply to all workspaces on this monitor
hyprctl workspaces -j | jq -r --arg mon "$MONITOR" '.[] | select(.monitor == $mon) | .id' | while read -r ws_id; do
    hyprctl keyword workspace "$ws_id, gapsout:$TOP $RIGHT $BOTTOM $LEFT"
done
