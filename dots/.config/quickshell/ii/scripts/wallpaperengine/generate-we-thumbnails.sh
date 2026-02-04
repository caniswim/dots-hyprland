#!/usr/bin/env bash

# Generate thumbnails for Wallpaper Engine wallpapers
# Usage: ./generate-we-thumbnails.sh [--size normal|large|x-large|xx-large] [--workshop-id <id>]

set -e

WORKSHOP_BASE="/mnt/Games/SteamLibrary/steamapps/workshop/content/431960"
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/thumbnails"

# Thumbnail sizes
get_thumbnail_size() {
    case "$1" in
        normal) echo 128 ;;
        large) echo 256 ;;
        x-large) echo 512 ;;
        xx-large) echo 1024 ;;
        *) echo 128 ;;
    esac
}

# Parse arguments
SIZE_NAME="normal"
WORKSHOP_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --size|-s)
            SIZE_NAME="$2"
            shift 2
            ;;
        --workshop-id|-w)
            WORKSHOP_ID="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

THUMBNAIL_SIZE=$(get_thumbnail_size "$SIZE_NAME")
CACHE_DIR="$CACHE_BASE/$SIZE_NAME"
mkdir -p "$CACHE_DIR"

# MD5 hash function for Freedesktop spec
md5_hash() {
    echo -n "$1" | md5sum | awk '{print $1}'
}

# URL encode function
urlencode() {
    local str="$1"
    local encoded=""
    local c
    for ((i=0; i<${#str}; i++)); do
        c="${str:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]|/) encoded+="$c" ;;
            *) printf -v hex '%%%02X' "'${c}'"; encoded+="$hex" ;;
        esac
    done
    echo "$encoded"
}

# Generate thumbnail for a single wallpaper
generate_thumbnail() {
    local workshop_id="$1"
    local workshop_path="$WORKSHOP_BASE/$workshop_id"
    local project_json="$workshop_path/project.json"

    # Skip if project.json doesn't exist
    [ -f "$project_json" ] || return

    # Get preview filename
    local preview_file=$(jq -r '.preview // "preview.jpg"' "$project_json")
    local preview_path="$workshop_path/$preview_file"

    # Skip if preview doesn't exist
    [ -f "$preview_path" ] || return

    # Generate URI and hash (Freedesktop spec)
    local abs_path=$(realpath "$preview_path")
    local encoded_path=$(urlencode "$abs_path")
    local uri="file://$encoded_path"
    local hash=$(md5_hash "$uri")
    local output="$CACHE_DIR/${hash}.png"

    # Skip if thumbnail already exists
    [ -f "$output" ] && return

    # Generate thumbnail
    if [[ "$preview_file" == *.gif ]]; then
        # For GIFs, extract first frame
        convert "$preview_path[0]" -resize "${THUMBNAIL_SIZE}x${THUMBNAIL_SIZE}" "$output" 2>/dev/null || \
        magick "$preview_path[0]" -resize "${THUMBNAIL_SIZE}x${THUMBNAIL_SIZE}" "$output"
    else
        # For JPG/PNG
        magick "$preview_path" -resize "${THUMBNAIL_SIZE}x${THUMBNAIL_SIZE}" "$output" 2>/dev/null || \
        convert "$preview_path" -resize "${THUMBNAIL_SIZE}x${THUMBNAIL_SIZE}" "$output"
    fi

    echo "Generated: $workshop_id -> $output"
}

# Generate thumbnails
if [ -n "$WORKSHOP_ID" ]; then
    # Single wallpaper
    generate_thumbnail "$WORKSHOP_ID"
else
    # All wallpapers
    for workshop_dir in "$WORKSHOP_BASE"/*/; do
        [ -d "$workshop_dir" ] || continue
        workshop_id=$(basename "$workshop_dir")
        generate_thumbnail "$workshop_id" &
    done
    wait
fi

echo "Thumbnail generation complete for size: $SIZE_NAME ($THUMBNAIL_SIZE px)"
