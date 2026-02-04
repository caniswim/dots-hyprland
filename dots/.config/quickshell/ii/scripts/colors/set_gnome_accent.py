#!/usr/bin/env python3
"""
Maps Material You primary color to GNOME accent and Papirus folder colors.
"""

import subprocess
import json
import colorsys
import os

# GNOME accent colors with hue ranges
GNOME_ACCENTS = {
    'red': [(0, 15), (345, 360)],
    'orange': [(15, 45)],
    'yellow': [(45, 70)],
    'green': [(70, 165)],
    'teal': [(165, 195)],
    'blue': [(195, 255)],
    'purple': [(255, 290)],
    'pink': [(290, 345)],
}

# Papirus folder colors with hue ranges (more granular)
PAPIRUS_COLORS = {
    'red': [(0, 10), (350, 360)],
    'carmine': [(10, 20)],
    'deeporange': [(20, 30)],
    'orange': [(30, 45)],
    'paleorange': [(45, 55)],
    'yellow': [(55, 70)],
    'green': [(70, 150)],
    'teal': [(150, 180)],
    'cyan': [(180, 200)],
    'darkcyan': [(200, 210)],
    'blue': [(210, 240)],
    'indigo': [(240, 260)],
    'violet': [(260, 280)],
    'magenta': [(280, 310)],
    'pink': [(310, 350)],
}

PAPIRUS_NEUTRAL = {
    'grey': (0, 0.08),
    'bluegrey': (0.08, 0.20),
}

def hex_to_hsl(hex_color):
    """Convert hex color to HSL."""
    hex_color = hex_color.lstrip('#')
    r, g, b = tuple(int(hex_color[i:i+2], 16) / 255.0 for i in (0, 2, 4))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return h * 360, s, l

def get_gnome_accent(h, s):
    """Get GNOME accent color."""
    if s < 0.12:
        return 'slate'

    for accent, ranges in GNOME_ACCENTS.items():
        for low, high in ranges:
            if low <= h < high:
                return accent
    return 'blue'

def get_papirus_color(h, s):
    """Get Papirus folder color."""
    if s < 0.08:
        return 'grey'
    if s < 0.20:
        return 'bluegrey'

    for color, ranges in PAPIRUS_COLORS.items():
        for low, high in ranges:
            if low <= h < high:
                return color
    return 'blue'

def main():
    state_dir = os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state'))
    colors_file = f"{state_dir}/quickshell/user/generated/colors.json"

    try:
        with open(colors_file, 'r') as f:
            colors = json.load(f)

        primary = colors.get('primary', '#3584e4')
        h, s, l = hex_to_hsl(primary)

        # Set GNOME accent
        gnome_accent = get_gnome_accent(h, s)
        subprocess.run(['gsettings', 'set', 'org.gnome.desktop.interface', 'accent-color', gnome_accent], check=True)

        # Set Papirus folder color
        papirus_color = get_papirus_color(h, s)
        subprocess.run(['papirus-folders', '-C', papirus_color, '-t', 'Papirus', '--once'], check=True)

        # Update icon cache
        icons_dir = os.path.expanduser('~/.local/share/icons/Papirus')
        subprocess.run(['gtk-update-icon-cache', '-f', '-t', icons_dir], check=False)

        # Force GTK to reload icons by toggling theme with delay
        import time
        subprocess.run(['gsettings', 'set', 'org.gnome.desktop.interface', 'icon-theme', 'hicolor'], check=False)
        time.sleep(0.3)
        subprocess.run(['gsettings', 'set', 'org.gnome.desktop.interface', 'icon-theme', 'Papirus-Dark'], check=False)

        print(f"Primary: {primary} (H:{h:.0f} S:{s:.2f})")
        print(f"GNOME accent: {gnome_accent}")
        print(f"Papirus folders: {papirus_color}")

    except FileNotFoundError:
        print("Colors file not found")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    main()
