# Cria um script para alternar entre pressionar e soltar
# Crie o arquivo ~/.config/hypr/scripts/mouse-toggle.sh
#!/bin/bash
STATE_FILE="/tmp/mouse_drag_state"

if [ -f "$STATE_FILE" ]; then
    wlrctl pointer release left
    rm "$STATE_FILE"
else
    wlrctl pointer press left
    touch "$STATE_FILE"
fi
