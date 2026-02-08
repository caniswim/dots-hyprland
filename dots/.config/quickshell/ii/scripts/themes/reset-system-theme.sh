#!/usr/bin/env bash
# reset-system-theme.sh - Reset GTK, Kvantum, and icon themes to defaults.
# Called when wallpaper changes to revert from a manual color scheme.
#
# Usage: reset-system-theme.sh [dark|light]

set -euo pipefail

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
STATE_DIR="$XDG_STATE_HOME/quickshell"

mode_flag="${1:-}"

# If no mode given, detect from gsettings
if [[ -z "$mode_flag" ]]; then
    current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
    if [[ "$current_mode" == "prefer-dark" ]]; then
        mode_flag="dark"
    else
        mode_flag="light"
    fi
fi

# ── Remove active scheme marker ─────────────────────────────────
rm -f "$STATE_DIR/user/generated/active_scheme.txt"

# ── Reset GTK theme ─────────────────────────────────────────────
if [[ "$mode_flag" == "dark" ]]; then
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
else
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' 2>/dev/null || true
fi

# ── Reset Kvantum to MaterialAdw ────────────────────────────────
if [[ -f "$CONFIG_DIR/scripts/kvantum/materialQT.sh" ]]; then
    bash "$CONFIG_DIR/scripts/kvantum/materialQT.sh" 2>/dev/null || true
fi
if command -v python &>/dev/null && [[ -f "$CONFIG_DIR/scripts/kvantum/changeAdwColors.py" ]]; then
    python "$CONFIG_DIR/scripts/kvantum/changeAdwColors.py" 2>/dev/null || true
fi
kvantummanager --set MaterialAdw 2>/dev/null || true

# ── Restore original KDE widgetStyle ─────────────────────────────
original_style=""
if [[ -f "$STATE_DIR/user/generated/original_widget_style.txt" ]]; then
    original_style=$(cat "$STATE_DIR/user/generated/original_widget_style.txt")
    rm -f "$STATE_DIR/user/generated/original_widget_style.txt"
fi
if [[ -n "$original_style" ]]; then
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --group "KDE" --key "widgetStyle" "$original_style"
    elif command -v kwriteconfig5 &>/dev/null; then
        kwriteconfig5 --group "KDE" --key "widgetStyle" "$original_style"
    fi
fi

# ── Reset icons to Papirus ──────────────────────────────────────
# Restore original KDE icon theme
original_icons=""
if [[ -f "$STATE_DIR/user/generated/original_icon_theme.txt" ]]; then
    original_icons=$(cat "$STATE_DIR/user/generated/original_icon_theme.txt")
    rm -f "$STATE_DIR/user/generated/original_icon_theme.txt"
fi

if [[ "$mode_flag" == "dark" ]]; then
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
else
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus' 2>/dev/null || true
fi

# KDE/Qt icons
kde_icon_theme="${original_icons:-Papirus-Dark}"
if command -v kwriteconfig6 &>/dev/null; then
    kwriteconfig6 --group "Icons" --key "Theme" "$kde_icon_theme"
elif command -v kwriteconfig5 &>/dev/null; then
    kwriteconfig5 --group "Icons" --key "Theme" "$kde_icon_theme"
fi

echo "[reset-system-theme] Reset to defaults (mode=$mode_flag)"
