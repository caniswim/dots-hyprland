#!/usr/bin/env bash

# Apply Wallpaper Engine wallpaper
# Usage: ./apply-we-wallpaper.sh --id <workshop_id> [--mode dark|light] [--type scheme-type] [--no-color-gen]

set -e

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"

WORKSHOP_BASE="/mnt/Games/SteamLibrary/steamapps/workshop/content/431960"
ASSETS_DIR="/mnt/Games/SteamLibrary/steamapps/common/wallpaper_engine/assets"
THUMBNAIL_DIR="$CACHE_DIR/media/we-wallpapers"
RESTORE_SCRIPT_DIR="$XDG_CONFIG_HOME/hypr/custom/scripts"
RESTORE_SCRIPT="$RESTORE_SCRIPT_DIR/__restore_we_wallpaper.sh"

# Pre-process function (matches switchwall.sh)
pre_process() {
    local mode_flag="$1"
    # Set GNOME color-scheme if mode_flag is dark or light
    if [[ "$mode_flag" == "dark" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    elif [[ "$mode_flag" == "light" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
    fi

    if [ ! -d "$STATE_DIR"/user/generated ]; then
        mkdir -p "$STATE_DIR"/user/generated
    fi
}

# Post-process function (matches switchwall.sh)
post_process() {
    # Handle KDE Material You colors if enabled
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_qt_apps=$(jq -r '.appearance.wallpaperTheming.enableQtApps' "$SHELL_CONFIG_FILE")
        if [ "$enable_qt_apps" == "true" ]; then
            "$XDG_CONFIG_HOME"/matugen/templates/kde/kde-material-you-colors-wrapper.sh --scheme-variant "$TYPE_FLAG" &
        fi
    fi

    # Apply VSCode colors
    "$CONFIG_DIR/scripts/colors/code/material-code-set-color.sh" &
}

# Default values
WORKSHOP_ID=""
MODE_FLAG="dark"
TYPE_FLAG="scheme-tonal-spot"
NO_COLOR_GEN=false
FPS=60

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --id)
            WORKSHOP_ID="$2"
            shift 2
            ;;
        --mode)
            MODE_FLAG="$2"
            shift 2
            ;;
        --type)
            TYPE_FLAG="$2"
            shift 2
            ;;
        --no-color-gen)
            NO_COLOR_GEN=true
            shift
            ;;
        --fps)
            FPS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate workshop ID
if [[ -z "$WORKSHOP_ID" ]]; then
    echo "ERROR: Workshop ID is required (--id <workshop_id>)"
    exit 1
fi

WORKSHOP_PATH="$WORKSHOP_BASE/$WORKSHOP_ID"
PROJECT_JSON="$WORKSHOP_PATH/project.json"

# Check if workshop directory exists
if [ ! -d "$WORKSHOP_PATH" ]; then
    echo "ERROR: Workshop directory not found: $WORKSHOP_PATH"
    exit 1
fi

# Check if project.json exists
if [ ! -f "$PROJECT_JSON" ]; then
    echo "ERROR: project.json not found: $PROJECT_JSON"
    exit 1
fi

echo "Applying Wallpaper Engine wallpaper: $WORKSHOP_ID"

# Cleanup previous processes
echo "Cleaning up previous wallpaper processes..."
"$SCRIPT_DIR/cleanup-we-processes.sh"

# Detect wallpaper type and metadata
echo "Detecting wallpaper type..."
METADATA=$("$SCRIPT_DIR/detect-we-type.sh" "$WORKSHOP_ID")
WE_TYPE=$(echo "$METADATA" | jq -r '.type')
WE_TITLE=$(echo "$METADATA" | jq -r '.title')
WE_FILE=$(echo "$METADATA" | jq -r '.file')
WE_PREVIEW=$(echo "$METADATA" | jq -r '.preview')

echo "Type: $WE_TYPE"
echo "Title: $WE_TITLE"
echo "File: $WE_FILE"

# Get monitors
MONITORS=$(hyprctl monitors -j | jq -r '.[] | .name')

# Apply wallpaper using linux-wallpaperengine
echo "Starting linux-wallpaperengine..."

# Build command
CMD="linux-wallpaperengine"
CMD="$CMD --assets-dir \"$ASSETS_DIR\""
CMD="$CMD --fps $FPS"
CMD="$CMD --silent"  # Mute by default

# Add monitors
for monitor in $MONITORS; do
    CMD="$CMD --screen-root $monitor"
done

# Add wallpaper path
CMD="$CMD \"$WORKSHOP_PATH\""

# Execute in background with nohup to prevent termination when parent exits
nohup bash -c "$CMD" > /tmp/wallpaper-engine.log 2>&1 &
WE_PID=$!
disown

echo "linux-wallpaperengine started with PID: $WE_PID"

# Save wallpaper path in config
if [ -f "$SHELL_CONFIG_FILE" ]; then
    jq --arg workshopId "$WORKSHOP_ID" \
       --arg type "$WE_TYPE" \
       --arg title "$WE_TITLE" \
       '.background.wallpaperEngine.isActive = true |
        .background.wallpaperEngine.workshopId = $workshopId |
        .background.wallpaperEngine.type = $type |
        .background.wallpaperPath = ("WE:" + $workshopId)' \
       "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
fi

# Create restore script
mkdir -p "$RESTORE_SCRIPT_DIR"
cat > "$RESTORE_SCRIPT" << 'EOFSCRIPT'
#!/bin/bash
# Generated by apply-we-wallpaper.sh
# Restores Wallpaper Engine wallpaper after reboot

WORKSHOP_BASE="/mnt/Games/SteamLibrary/steamapps/workshop/content/431960"
ASSETS_DIR="/mnt/Games/SteamLibrary/steamapps/common/wallpaper_engine/assets"
SHELL_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"

# Read workshop ID from config
if [ ! -f "$SHELL_CONFIG_FILE" ]; then
    echo "Config file not found: $SHELL_CONFIG_FILE"
    exit 1
fi

IS_ACTIVE=$(jq -r '.background.wallpaperEngine.isActive // false' "$SHELL_CONFIG_FILE")
if [ "$IS_ACTIVE" != "true" ]; then
    echo "WE wallpaper not active"
    exit 0
fi

WORKSHOP_ID=$(jq -r '.background.wallpaperEngine.workshopId // ""' "$SHELL_CONFIG_FILE")
if [ -z "$WORKSHOP_ID" ]; then
    echo "No workshop ID in config"
    exit 0
fi

WORKSHOP_PATH="$WORKSHOP_BASE/$WORKSHOP_ID"

if [ ! -d "$WORKSHOP_PATH" ]; then
    echo "Workshop directory not found: $WORKSHOP_PATH"
    exit 1
fi

# Get monitors
MONITORS=$(hyprctl monitors -j | jq -r '.[] | .name')

# Apply wallpaper
CMD="linux-wallpaperengine"
CMD="$CMD --assets-dir \"$ASSETS_DIR\""
CMD="$CMD --fps 60"
CMD="$CMD --silent"

for monitor in $MONITORS; do
    CMD="$CMD --screen-root $monitor"
done

CMD="$CMD \"$WORKSHOP_PATH\""

eval "$CMD" &

echo "Wallpaper Engine wallpaper restored: $WORKSHOP_ID"
EOFSCRIPT

chmod +x "$RESTORE_SCRIPT"

# Generate colors if not disabled
if [ "$NO_COLOR_GEN" = false ]; then
    echo "Generating color scheme..."

    # Use preview from workshop directory
    PREVIEW_PATH="$WORKSHOP_PATH/$WE_PREVIEW"

    if [ ! -f "$PREVIEW_PATH" ]; then
        echo "WARNING: Preview not found: $PREVIEW_PATH"
        echo "Skipping color generation"
    else
        # Create thumbnail for color extraction
        mkdir -p "$THUMBNAIL_DIR"
        THUMBNAIL="$THUMBNAIL_DIR/${WORKSHOP_ID}.jpg"

        # Copy/convert preview
        if [[ "$PREVIEW_PATH" == *.gif ]]; then
            # Extract first frame from GIF
            convert "$PREVIEW_PATH[0]" "$THUMBNAIL" 2>/dev/null || cp "$PREVIEW_PATH" "$THUMBNAIL"
        else
            cp "$PREVIEW_PATH" "$THUMBNAIL"
        fi

        # Update thumbnail path in config
        if [ -f "$SHELL_CONFIG_FILE" ]; then
            jq --arg path "$THUMBNAIL" \
               '.background.thumbnailPath = $path' \
               "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
        fi

        # Generate colors using existing system
        if [ -f "$THUMBNAIL" ]; then
            # Pre-process (set GNOME theme)
            pre_process "$MODE_FLAG"

            # Color generation
            COLORS_DIR="$CONFIG_DIR/scripts/colors"
            VENV_PATH="${ILLOGICAL_IMPULSE_VIRTUAL_ENV/#\~/$HOME}"

            # Generate colors using matugen (generates colors.json)
            echo "Running matugen..."
            matugen image "$THUMBNAIL" --mode "$MODE_FLAG" --type "$TYPE_FLAG"

            # Source venv and generate terminal colors
            if [ -f "$VENV_PATH/bin/activate" ]; then
                source "$VENV_PATH/bin/activate"
                python3 "$COLORS_DIR/generate_colors_material.py" \
                    --path "$THUMBNAIL" \
                    --mode "$MODE_FLAG" \
                    --scheme "$TYPE_FLAG" \
                    --termscheme "$COLORS_DIR/terminal/scheme-base.json" \
                    --blend_bg_fg \
                    --cache "$STATE_DIR/user/generated/color.txt" \
                    > "$STATE_DIR/user/generated/material_colors.scss"
                deactivate

                # Apply colors to terminal
                "$COLORS_DIR/applycolor.sh"

                # Post-process (KDE colors, VSCode colors)
                post_process

                echo "Color scheme generated and applied"
            else
                echo "WARNING: Python venv not found at $VENV_PATH"
                echo "Skipping terminal color generation"
            fi
        fi
    fi
fi

echo "Wallpaper Engine wallpaper applied successfully: $WE_TITLE ($WORKSHOP_ID)"
