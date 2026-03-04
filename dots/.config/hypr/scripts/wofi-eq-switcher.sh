#!/usr/bin/env bash
#
# Wofi-based PipeWire EQ Switcher (Chicago95 style with icons)
#

ICON_DIR="/usr/share/icons/Chicago95/devices/48"
ICON_HEADPHONE="$ICON_DIR/audio-headphones.png"
ICON_SPEAKER="$ICON_DIR/audio-speakers.png"
STYLE_FILE="$HOME/.config/wofi/style-eq.css"

EQ_SINK="effect_input.eq_convolution"
DIRECT_SINK="alsa_output.usb-Burr-Brown_from_TI_USB_Audio_CODEC-00.analog-stereo-output"

get_id() {
    pw-dump 2>/dev/null \
        | jq -r --arg name "$1" '.[] | select(.info.props["node.name"] == $name) | .id' \
        | head -1
}

current=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
    | grep 'node.name' | head -1 \
    | sed 's/.*"\(.*\)".*/\1/')

# Build menu with icons — mark current with ●
if [[ "$current" == "$EQ_SINK" ]]; then
    options="img:$ICON_HEADPHONE:text:● HIFIMAN HE400se (EQ)\nimg:$ICON_SPEAKER:text:   Speakers (Direto)"
else
    options="img:$ICON_HEADPHONE:text:   HIFIMAN HE400se (EQ)\nimg:$ICON_SPEAKER:text:● Speakers (Direto)"
fi

choice=$(echo -e "$options" | wofi --dmenu \
    --prompt "Saída de Áudio" \
    --cache-file /dev/null \
    --allow-images \
    --style "$STYLE_FILE" \
    --columns 2 \
    --width 500 \
    --height 90 \
    --lines 1)

[ -z "$choice" ] && exit 0

case "$choice" in
    *"HIFIMAN"*)
        wpctl set-default "$(get_id "$EQ_SINK")"
        notify-send -u low -t 2000 -h string:x-canonical-private-synchronous:eq-toggle \
            -i "$ICON_HEADPHONE" "EQ Ativado" "HIFIMAN HE400se Convolution EQ"
        ;;
    *"Speakers"*)
        wpctl set-default "$(get_id "$DIRECT_SINK")"
        notify-send -u low -t 2000 -h string:x-canonical-private-synchronous:eq-toggle \
            -i "$ICON_SPEAKER" "EQ Desativado" "Saída direta: USB Audio Codec"
        ;;
esac
