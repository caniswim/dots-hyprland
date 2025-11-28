#!/usr/bin/env bash

# Detect Wallpaper Engine wallpaper type and extract metadata
# Usage: ./detect-we-type.sh <workshop_id_or_path>

set -e

WORKSHOP_BASE="/mnt/Games/SteamLibrary/steamapps/workshop/content/431960"

# Parse argument
if [[ "$1" =~ ^[0-9]+$ ]]; then
    # Workshop ID provided
    WORKSHOP_ID="$1"
    WORKSHOP_PATH="$WORKSHOP_BASE/$WORKSHOP_ID"
else
    # Full path provided
    WORKSHOP_PATH="$1"
    WORKSHOP_ID=$(basename "$WORKSHOP_PATH")
fi

PROJECT_JSON="$WORKSHOP_PATH/project.json"

# Check if project.json exists
if [ ! -f "$PROJECT_JSON" ]; then
    echo "ERROR: project.json not found at $PROJECT_JSON" >&2
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is not installed" >&2
    exit 1
fi

# Extract metadata
TYPE=$(jq -r '.type // "unknown"' "$PROJECT_JSON")
TITLE=$(jq -r '.title // "Untitled"' "$PROJECT_JSON")
FILE=$(jq -r '.file // ""' "$PROJECT_JSON")
PREVIEW=$(jq -r '.preview // "preview.jpg"' "$PROJECT_JSON")
TAGS=$(jq -r '.tags // [] | join(",")' "$PROJECT_JSON")
SCHEME_COLOR=$(jq -r '.general.properties.schemecolor.value // ""' "$PROJECT_JSON")

# Build preview path
PREVIEW_PATH="$WORKSHOP_PATH/$PREVIEW"
if [ ! -f "$PREVIEW_PATH" ]; then
    PREVIEW_PATH=""
fi

# Output as JSON for easy parsing in QML
cat <<EOF
{
  "workshopId": "$WORKSHOP_ID",
  "type": "$TYPE",
  "title": "$TITLE",
  "file": "$FILE",
  "preview": "$PREVIEW",
  "previewPath": "$PREVIEW_PATH",
  "workshopPath": "$WORKSHOP_PATH",
  "tags": "$TAGS",
  "schemeColor": "$SCHEME_COLOR"
}
EOF
