#!/bin/bash
# pick_accent.sh - Pick accent color from screen with mouse
# Usage: Bind to a keybinding, click anywhere to pick color

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Capture color with hyprpicker
color=$(hyprpicker -a -n)

# Exit if cancelled (ESC or right-click)
if [ -z "$color" ]; then
    notify-send "Color Picker" "Cancelled" -t 1500
    exit 0
fi

notify-send "Color Picker" "Applying: $color" -t 2000

# Call the full color pipeline
"$SCRIPT_DIR/switchwall.sh" --color "$color"

notify-send "Color Picker" "Theme updated with $color" -t 3000
