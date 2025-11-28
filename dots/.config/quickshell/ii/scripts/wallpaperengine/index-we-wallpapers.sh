#!/usr/bin/env bash
set -e

WORKSHOP_BASE="/mnt/Games/SteamLibrary/steamapps/workshop/content/431960"
CACHE_DIR="/home/brunno/.cache/quickshell"
CACHE_FILE="$CACHE_DIR/we-wallpapers-index.json"
SCRIPT_DIR="/home/brunno/.config/quickshell/ii/scripts/wallpaperengine"

mkdir -p "$CACHE_DIR"

echo "{" > "$CACHE_FILE"
echo "  \"lastScan\": \"$(date -Iseconds)\"," >> "$CACHE_FILE"
echo "  \"workshopPath\": \"$WORKSHOP_BASE\"," >> "$CACHE_FILE"
echo "  \"wallpapers\": [" >> "$CACHE_FILE"

first=true

for workshop_dir in "$WORKSHOP_BASE"/*/; do
    [ -d "$workshop_dir" ] || continue
    workshop_id=$(basename "$workshop_dir")
    project_json="$workshop_dir/project.json"
    [ -f "$project_json" ] || continue

    metadata=$("$SCRIPT_DIR/detect-we-type.sh" "$workshop_id" 2>/dev/null || echo "")
    
    [ -z "$metadata" ] && continue
    [ "$metadata" = "{}" ] && continue

    if [ "$first" = false ]; then
        echo "," >> "$CACHE_FILE"
    fi

    echo -n "    $metadata" >> "$CACHE_FILE"
    first=false
done

echo "" >> "$CACHE_FILE"
echo "  ]" >> "$CACHE_FILE"
echo "}" >> "$CACHE_FILE"

echo "$CACHE_FILE"
