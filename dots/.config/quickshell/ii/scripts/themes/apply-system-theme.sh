#!/usr/bin/env bash
# apply-system-theme.sh - Apply GTK, Kvantum, and icon themes for a color scheme.
#
# Usage: apply-system-theme.sh --gtk-theme "NAME" --kvantum-theme "NAME" \
#   --icon-theme "NAME" --papirus-color "COLOR" --color-scheme "prefer-dark" \
#   --scheme-id "ID"

set -euo pipefail

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
STATE_DIR="$XDG_STATE_HOME/quickshell"

gtk_theme=""
kvantum_theme=""
icon_theme=""
papirus_color=""
color_scheme=""
scheme_id=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gtk-theme) gtk_theme="$2"; shift 2 ;;
        --kvantum-theme) kvantum_theme="$2"; shift 2 ;;
        --icon-theme) icon_theme="$2"; shift 2 ;;
        --papirus-color) papirus_color="$2"; shift 2 ;;
        --color-scheme) color_scheme="$2"; shift 2 ;;
        --scheme-id) scheme_id="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# ── 1. GTK theme + color-scheme ─────────────────────────────────
if [[ -n "$color_scheme" ]]; then
    gsettings set org.gnome.desktop.interface color-scheme "$color_scheme" 2>/dev/null || true
fi

if [[ -n "$gtk_theme" ]]; then
    gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" 2>/dev/null || true
fi

# ── 2. Kvantum theme ────────────────────────────────────────────
if [[ -n "$kvantum_theme" ]]; then
    if [[ "$kvantum_theme" == "MaterialAdw" ]]; then
        # Re-generate MaterialAdw using existing pipeline
        if [[ -f "$CONFIG_DIR/scripts/kvantum/materialQT.sh" ]]; then
            bash "$CONFIG_DIR/scripts/kvantum/materialQT.sh" 2>/dev/null || true
        fi
        if command -v python &>/dev/null && [[ -f "$CONFIG_DIR/scripts/kvantum/changeAdwColors.py" ]]; then
            python "$CONFIG_DIR/scripts/kvantum/changeAdwColors.py" 2>/dev/null || true
        fi
        kvantummanager --set MaterialAdw 2>/dev/null || true
    else
        kvantummanager --set "$kvantum_theme" 2>/dev/null || true
    fi

    # Save current widgetStyle before overriding, so reset can restore it
    mkdir -p "$STATE_DIR/user/generated"
    if [[ ! -f "$STATE_DIR/user/generated/original_widget_style.txt" ]]; then
        if command -v kreadconfig6 &>/dev/null; then
            kreadconfig6 --group "KDE" --key "widgetStyle" > "$STATE_DIR/user/generated/original_widget_style.txt" 2>/dev/null || true
        elif command -v kreadconfig5 &>/dev/null; then
            kreadconfig5 --group "KDE" --key "widgetStyle" > "$STATE_DIR/user/generated/original_widget_style.txt" 2>/dev/null || true
        fi
    fi

    # Set KDE widgetStyle to kvantum so Qt apps actually use it
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --group "KDE" --key "widgetStyle" "kvantum"
    elif command -v kwriteconfig5 &>/dev/null; then
        kwriteconfig5 --group "KDE" --key "widgetStyle" "kvantum"
    fi
fi

# ── 3. Icon theme ───────────────────────────────────────────────
if [[ -n "$papirus_color" ]] && command -v papirus-folders &>/dev/null; then
    # Determine which Papirus variant to target
    local_icon_theme="$icon_theme"
    if [[ "$local_icon_theme" == "Papirus-Dark" ]] || [[ "$local_icon_theme" == "Papirus" ]]; then
        papirus-folders -C "$papirus_color" -t "$local_icon_theme" --once 2>/dev/null || true
    fi
fi

if [[ -n "$icon_theme" ]]; then
    # Save original KDE icon theme before overriding
    mkdir -p "$STATE_DIR/user/generated"
    if [[ ! -f "$STATE_DIR/user/generated/original_icon_theme.txt" ]]; then
        if command -v kreadconfig6 &>/dev/null; then
            kreadconfig6 --group "Icons" --key "Theme" > "$STATE_DIR/user/generated/original_icon_theme.txt" 2>/dev/null || true
        elif command -v kreadconfig5 &>/dev/null; then
            kreadconfig5 --group "Icons" --key "Theme" > "$STATE_DIR/user/generated/original_icon_theme.txt" 2>/dev/null || true
        fi
    fi

    # GTK
    gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" 2>/dev/null || true
    # KDE/Qt
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --group "Icons" --key "Theme" "$icon_theme"
    elif command -v kwriteconfig5 &>/dev/null; then
        kwriteconfig5 --group "Icons" --key "Theme" "$icon_theme"
    fi
fi

# ── 4. Mark scheme as active ────────────────────────────────────
if [[ -n "$scheme_id" ]]; then
    mkdir -p "$STATE_DIR/user/generated"
    echo "$scheme_id" > "$STATE_DIR/user/generated/active_scheme.txt"
fi

echo "[apply-system-theme] Applied: gtk=$gtk_theme kvantum=$kvantum_theme icons=$icon_theme scheme=$scheme_id"
