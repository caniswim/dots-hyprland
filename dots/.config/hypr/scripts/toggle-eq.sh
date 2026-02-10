#!/usr/bin/env bash
#
# Toggle PipeWire Convolution EQ (HIFIMAN HE400se)
#

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

if [[ "$current" == "$EQ_SINK" ]]; then
    wpctl set-default "$(get_id "$DIRECT_SINK")"
    notify-send -u low -t 2000 -h string:x-canonical-private-synchronous:eq-toggle \
        "EQ Desativado" "Saída direta: USB Audio Codec"
else
    wpctl set-default "$(get_id "$EQ_SINK")"
    notify-send -u low -t 2000 -h string:x-canonical-private-synchronous:eq-toggle \
        "EQ Ativado" "HIFIMAN HE400se Convolution EQ"
fi
