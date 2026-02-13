#!/usr/bin/env bash
# write-scheme-scss.sh - Write scheme colors to material_colors.scss
# so that changeAdwColors.py picks them up when regenerating MaterialAdw.
#
# Reads JSON from stdin with scheme colors (keys like m3primary, m3onPrimary, term0, etc.)
# Optionally accepts --darkmode true/false as CLI argument.
#
# Usage: echo '{"m3primary":"#bd93f9",...}' | write-scheme-scss.sh [--darkmode true]

XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCSS_FILE="$STATE_DIR/user/generated/material_colors.scss"

darkmode=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --darkmode) darkmode="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Read JSON from stdin
json=$(cat)
if [[ -z "$json" ]]; then
    echo "[write-scheme-scss] No JSON input received" >&2
    exit 1
fi

mkdir -p "$STATE_DIR/user/generated"

# Build SCSS output
{
    # Write darkmode flag if provided
    if [[ "$darkmode" == "true" ]]; then
        echo '$darkmode: True;'
    elif [[ "$darkmode" == "false" ]]; then
        echo '$darkmode: False;'
    fi

    # Convert JSON keys to SCSS variables:
    # - Strip "m3" prefix from keys that have it
    # - Keep camelCase (matching existing generate_colors_material.py output)
    # - term0-term15 keys have no m3 prefix, pass through as-is
    echo "$json" | jq -r 'to_entries[] | "\(.key) \(.value)"' | while read -r key value; do
        # Strip m3 prefix if present
        if [[ "$key" == m3* ]]; then
            scss_key="${key#m3}"
            # Lowercase first character (m3primary -> primary, m3onPrimary -> onPrimary)
            scss_key="$(echo "${scss_key:0:1}" | tr '[:upper:]' '[:lower:]')${scss_key:1}"
        else
            scss_key="$key"
        fi
        echo "\$${scss_key}: ${value};"
    done
} > "$SCSS_FILE"

echo "[write-scheme-scss] Wrote $(wc -l < "$SCSS_FILE") lines to $SCSS_FILE"
