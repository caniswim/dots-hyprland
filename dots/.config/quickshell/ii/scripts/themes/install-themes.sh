#!/usr/bin/env bash
# install-themes.sh - Download and install GTK, Kvantum, and icon themes
# for color scheme integration.
#
# Usage: bash install-themes.sh [--gtk] [--kvantum] [--icons] [--all]

set -euo pipefail

THEMES_DIR="${HOME}/.local/share/themes"
ICONS_DIR="${HOME}/.local/share/icons"
KVANTUM_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Kvantum"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

install_gtk=false
install_kvantum=false
install_icons=false

if [[ $# -eq 0 ]] || [[ "$*" == *"--all"* ]]; then
    install_gtk=true
    install_kvantum=true
    install_icons=true
else
    [[ "$*" == *"--gtk"* ]] && install_gtk=true
    [[ "$*" == *"--kvantum"* ]] && install_kvantum=true
    [[ "$*" == *"--icons"* ]] && install_icons=true
fi

clone_repo() {
    local url="$1"
    local name="$2"
    echo "[install-themes] Cloning $name..."
    git clone --depth 1 "$url" "$TMP_DIR/$name" 2>/dev/null || {
        echo "[install-themes] Warning: Failed to clone $name"
        return 1
    }
}

# ── GTK Themes ──────────────────────────────────────────────────
install_gtk_themes() {
    echo "=== Installing GTK Themes ==="
    mkdir -p "$THEMES_DIR"

    # Catppuccin GTK (Fausto-Korpsvart)
    if clone_repo "https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme" "catppuccin-gtk"; then
        cp -r "$TMP_DIR/catppuccin-gtk/themes/"* "$THEMES_DIR/" 2>/dev/null || true
        echo "  -> Catppuccin GTK installed"
    fi

    # Gruvbox GTK
    if clone_repo "https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme" "gruvbox-gtk"; then
        cp -r "$TMP_DIR/gruvbox-gtk/themes/"* "$THEMES_DIR/" 2>/dev/null || true
        echo "  -> Gruvbox GTK installed"
    fi

    # Tokyo Night GTK
    if clone_repo "https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme" "tokyonight-gtk"; then
        cp -r "$TMP_DIR/tokyonight-gtk/themes/"* "$THEMES_DIR/" 2>/dev/null || true
        echo "  -> Tokyo Night GTK installed"
    fi

    # Everforest GTK
    if clone_repo "https://github.com/Fausto-Korpsvart/Everforest-GTK-Theme" "everforest-gtk"; then
        cp -r "$TMP_DIR/everforest-gtk/themes/"* "$THEMES_DIR/" 2>/dev/null || true
        echo "  -> Everforest GTK installed"
    fi

    # Kanagawa GTK
    if clone_repo "https://github.com/Fausto-Korpsvart/Kanagawa-GKT-Theme" "kanagawa-gtk"; then
        cp -r "$TMP_DIR/kanagawa-gtk/themes/"* "$THEMES_DIR/" 2>/dev/null || true
        echo "  -> Kanagawa GTK installed"
    fi

    # Material GTK
    if clone_repo "https://github.com/Fausto-Korpsvart/Material-GTK-Themes" "material-gtk"; then
        cp -r "$TMP_DIR/material-gtk/themes/"* "$THEMES_DIR/" 2>/dev/null || true
        echo "  -> Material GTK installed"
    fi

    # Rose Pine GTK
    if clone_repo "https://github.com/rose-pine/gtk" "rose-pine-gtk"; then
        cp -r "$TMP_DIR/rose-pine-gtk/gtk4" "$THEMES_DIR/rose-pine-gtk/" 2>/dev/null || true
        cp -r "$TMP_DIR/rose-pine-gtk/gtk3" "$THEMES_DIR/rose-pine-gtk/" 2>/dev/null || true
        # Check for variant dirs
        for variant in rose-pine-gtk rose-pine-moon-gtk rose-pine-dawn-gtk; do
            if [ -d "$TMP_DIR/rose-pine-gtk/$variant" ]; then
                cp -r "$TMP_DIR/rose-pine-gtk/$variant" "$THEMES_DIR/" 2>/dev/null || true
            fi
        done
        echo "  -> Rose Pine GTK installed"
    fi

    # Dracula GTK
    if clone_repo "https://github.com/dracula/gtk" "dracula-gtk"; then
        cp -r "$TMP_DIR/dracula-gtk" "$THEMES_DIR/Dracula" 2>/dev/null || true
        echo "  -> Dracula GTK installed"
    fi

    # Nordic GTK
    if clone_repo "https://github.com/EliverLara/Nordic" "nordic-gtk"; then
        cp -r "$TMP_DIR/nordic-gtk" "$THEMES_DIR/Nordic-darker" 2>/dev/null || true
        echo "  -> Nordic GTK installed"
    fi

    # Ayu GTK
    if clone_repo "https://github.com/dnordstrom/ayu-theme" "ayu-gtk"; then
        for d in "$TMP_DIR/ayu-gtk/"*/; do
            [ -d "$d" ] && cp -r "$d" "$THEMES_DIR/" 2>/dev/null || true
        done
        echo "  -> Ayu GTK installed"
    fi

    # Numix Solarized
    if clone_repo "https://github.com/Ferdi265/numix-solarized-gtk-theme" "numix-solarized"; then
        for d in "$TMP_DIR/numix-solarized/"Numix-Solarized*/; do
            [ -d "$d" ] && cp -r "$d" "$THEMES_DIR/" 2>/dev/null || true
        done
        echo "  -> Numix Solarized installed"
    fi

    echo "=== GTK Themes done ==="
}

# ── Kvantum Themes ──────────────────────────────────────────────
install_kvantum_themes() {
    echo "=== Installing Kvantum Themes ==="
    mkdir -p "$KVANTUM_DIR"

    # Catppuccin Kvantum
    if clone_repo "https://github.com/catppuccin/kvantum" "catppuccin-kvantum"; then
        for d in "$TMP_DIR/catppuccin-kvantum/themes/"*/; do
            basename_d=$(basename "$d")
            cp -r "$d" "$KVANTUM_DIR/$basename_d" 2>/dev/null || true
        done
        echo "  -> Catppuccin Kvantum installed"
    fi

    # Rose Pine Kvantum
    if clone_repo "https://github.com/rose-pine/kvantum" "rose-pine-kvantum"; then
        for d in "$TMP_DIR/rose-pine-kvantum/"*/; do
            basename_d=$(basename "$d")
            # Only copy directories that look like Kvantum themes
            if [ -f "$d"/*.kvconfig ] 2>/dev/null || [ -f "$d"/*.svg ] 2>/dev/null; then
                cp -r "$d" "$KVANTUM_DIR/$basename_d" 2>/dev/null || true
            fi
        done
        echo "  -> Rose Pine Kvantum installed"
    fi

    echo "=== Kvantum Themes done ==="
}

# ── Icon Themes ─────────────────────────────────────────────────
install_icon_themes() {
    echo "=== Installing Icon Themes ==="
    mkdir -p "$ICONS_DIR"

    # Catppuccin Papirus Folders
    if clone_repo "https://github.com/catppuccin/papirus-folders" "catppuccin-papirus"; then
        if [ -f "$TMP_DIR/catppuccin-papirus/install.sh" ]; then
            echo "  -> Catppuccin Papirus: run 'install.sh' from the repo manually if needed"
        fi
        cp -r "$TMP_DIR/catppuccin-papirus" "$ICONS_DIR/catppuccin-papirus-folders" 2>/dev/null || true
        echo "  -> Catppuccin Papirus Folders downloaded"
    fi

    # Gruvbox Plus Icons
    if clone_repo "https://github.com/SylEleuth/gruvbox-plus-icon-pack" "gruvbox-plus-icons"; then
        for d in "$TMP_DIR/gruvbox-plus-icons/"Gruvbox-Plus*/; do
            [ -d "$d" ] && cp -r "$d" "$ICONS_DIR/" 2>/dev/null || true
        done
        echo "  -> Gruvbox Plus Icons installed"
    fi

    # Tokyo Night Icons
    if clone_repo "https://github.com/ljmill/tokyo-night-icons" "tokyonight-icons"; then
        if [ -d "$TMP_DIR/tokyonight-icons/TokyoNight-SE" ]; then
            cp -r "$TMP_DIR/tokyonight-icons/TokyoNight-SE" "$ICONS_DIR/" 2>/dev/null || true
        else
            cp -r "$TMP_DIR/tokyonight-icons" "$ICONS_DIR/TokyoNight-SE" 2>/dev/null || true
        fi
        echo "  -> Tokyo Night Icons installed"
    fi

    # Rose Pine Icons
    if clone_repo "https://github.com/Henriquehnnm/rose-pine-icon-theme" "rose-pine-icons"; then
        if [ -d "$TMP_DIR/rose-pine-icons/Rose-Pine-icons" ]; then
            cp -r "$TMP_DIR/rose-pine-icons/Rose-Pine-icons" "$ICONS_DIR/" 2>/dev/null || true
        else
            cp -r "$TMP_DIR/rose-pine-icons" "$ICONS_DIR/Rose-Pine-icons" 2>/dev/null || true
        fi
        echo "  -> Rose Pine Icons installed"
    fi

    # Dracula Icons
    if clone_repo "https://github.com/m4thewz/dracula-icons" "dracula-icons"; then
        if [ -d "$TMP_DIR/dracula-icons/Dracula" ]; then
            cp -r "$TMP_DIR/dracula-icons/Dracula" "$ICONS_DIR/" 2>/dev/null || true
        else
            cp -r "$TMP_DIR/dracula-icons" "$ICONS_DIR/Dracula" 2>/dev/null || true
        fi
        echo "  -> Dracula Icons installed"
    fi

    # Nordzy Icons
    if clone_repo "https://github.com/alvatip/Nordzy-icon" "nordzy-icons"; then
        if [ -f "$TMP_DIR/nordzy-icons/install.sh" ]; then
            cd "$TMP_DIR/nordzy-icons"
            bash install.sh 2>/dev/null || {
                # Fallback: just copy
                for d in "$TMP_DIR/nordzy-icons/"Nordzy*/; do
                    [ -d "$d" ] && cp -r "$d" "$ICONS_DIR/" 2>/dev/null || true
                done
            }
            cd -
        else
            for d in "$TMP_DIR/nordzy-icons/"Nordzy*/; do
                [ -d "$d" ] && cp -r "$d" "$ICONS_DIR/" 2>/dev/null || true
            done
        fi
        echo "  -> Nordzy Icons installed"
    fi

    echo "=== Icon Themes done ==="
}

# ── Main ────────────────────────────────────────────────────────
echo "[install-themes] Starting theme installation..."
$install_gtk && install_gtk_themes
$install_kvantum && install_kvantum_themes
$install_icons && install_icon_themes
echo "[install-themes] Done!"
