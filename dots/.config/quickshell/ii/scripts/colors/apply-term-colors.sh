#!/usr/bin/env bash
# apply-term-colors.sh - Apply terminal colors from CLI arguments.
# Called by Colorschemes.qml when a color scheme is selected.
#
# Usage: apply-term-colors.sh --term0 "#hex" ... --term15 "#hex" \
#          --bg "#hex" --fg "#hex" --selBg "#hex"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$XDG_STATE_HOME/quickshell"
CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"

term_alpha=100

# Check enableTerminal config flag first
if [[ -f "$CONFIG_FILE" ]]; then
    enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$CONFIG_FILE")
    if [[ "$enable_terminal" == "false" ]]; then
        echo "[apply-term-colors] Terminal theming disabled in config"
        exit 0
    fi
fi

# Parse arguments
declare -A term_colors
bg_color=""
fg_color=""
sel_bg_color=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --term[0-9]|--term1[0-5])
            key="${1#--}"
            term_colors["$key"]="$2"
            shift 2
            ;;
        --bg) bg_color="$2"; shift 2 ;;
        --fg) fg_color="$2"; shift 2 ;;
        --selBg) sel_bg_color="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Verify we have at least term0 and term7
if [[ -z "${term_colors[term0]:-}" || -z "${term_colors[term7]:-}" ]]; then
    echo "[apply-term-colors] Missing required terminal colors (term0, term7)" >&2
    exit 1
fi

# Check if terminal escape sequence template exists
if [[ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]]; then
    echo "[apply-term-colors] Template file not found: $SCRIPT_DIR/terminal/sequences.txt" >&2
    exit 1
fi

# Copy template
mkdir -p "$STATE_DIR/user/generated/terminal"
cp "$SCRIPT_DIR/terminal/sequences.txt" "$STATE_DIR/user/generated/terminal/sequences.txt"

SEQFILE="$STATE_DIR/user/generated/terminal/sequences.txt"

# Substitute $termN placeholders with hex values (strip leading #)
for i in $(seq 0 15); do
    key="term${i}"
    val="${term_colors[$key]:-}"
    if [[ -n "$val" ]]; then
        val_no_hash="${val#\#}"
        sed -i "s/\$${key} #/${val_no_hash}/g" "$SEQFILE"
    fi
done

# Substitute terminal special colors (background, foreground, selection)
if [[ -n "$bg_color" ]]; then
    val_no_hash="${bg_color#\#}"
    sed -i "s/\$background #/${val_no_hash}/g" "$SEQFILE"
fi
if [[ -n "$fg_color" ]]; then
    val_no_hash="${fg_color#\#}"
    sed -i "s/\$onBackground #/${val_no_hash}/g" "$SEQFILE"
fi
if [[ -n "$sel_bg_color" ]]; then
    val_no_hash="${sel_bg_color#\#}"
    sed -i "s/\$surfaceVariant #/${val_no_hash}/g" "$SEQFILE"
fi

# Substitute $alpha
sed -i "s/\$alpha/$term_alpha/g" "$SEQFILE"

# Write escape sequences to all terminals
for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
        {
        cat "$SEQFILE" >"$file"
        } & disown || true
    fi
done
