#!/usr/bin/env bash

# Cleanup all wallpaper-related processes
# Kills mpvpaper and linux-wallpaperengine to prevent process stacking

set -e

echo "Cleaning up wallpaper processes..."

# Kill mpvpaper processes
if pgrep -f mpvpaper > /dev/null; then
    echo "Killing mpvpaper processes..."
    pkill -f -9 mpvpaper 2>/dev/null || true
fi

# Kill linux-wallpaperengine processes
if pgrep -f linux-wallpaperengine > /dev/null; then
    echo "Killing linux-wallpaperengine processes..."
    pkill -f -9 linux-wallpaperengine 2>/dev/null || true
fi

# Give processes time to terminate
sleep 0.3

echo "Cleanup complete."
