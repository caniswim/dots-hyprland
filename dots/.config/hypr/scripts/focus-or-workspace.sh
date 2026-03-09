#!/bin/bash
# Focus window in direction (u/d), or switch workspace if no window exists there.
# Usage: focus-or-workspace.sh u|d
# u = try focus up, fallback to prev workspace
# d = try focus down, fallback to next workspace

direction="$1"

# Get current focused window address
before=$(hyprctl activewindow -j | jq -r '.address')

# Try to move focus in the given direction
hyprctl dispatch movefocus "$direction"

# Get new focused window address
after=$(hyprctl activewindow -j | jq -r '.address')

# If focus didn't change, switch workspace
if [ "$before" = "$after" ]; then
    case "$direction" in
        u) hyprctl dispatch workspace r-1 ;;
        d) hyprctl dispatch workspace r+1 ;;
    esac
fi
