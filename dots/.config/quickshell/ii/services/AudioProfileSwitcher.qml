pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Manages audio output profiles. Detects the active sink and switches
 * between configurable profiles using wpctl/pw-dump.
 */
Singleton {
    id: root

    property int activeProfileIndex: -1
    property bool ready: false

    readonly property var profiles: [
        {
            name: "Speakers",
            sinkName: "alsa_output.usb-Burr-Brown_from_TI_USB_Audio_CODEC-00.analog-stereo-output",
            icon: "speaker_group",
            hasEq: false,
        },
        {
            name: "HIFIMAN HE400se",
            sinkName: "effect_input.eq_convolution",
            icon: "headphones",
            hasEq: true,
        },
    ]

    function refresh() {
        inspectProc.running = true;
    }

    function switchTo(profileIndex) {
        if (profileIndex < 0 || profileIndex >= profiles.length)
            return;
        const profile = profiles[profileIndex];
        getSinkIdProc.targetIndex = profileIndex;
        getSinkIdProc.command = [
            "bash", "-c",
            `pw-dump 2>/dev/null | jq -r --arg name '${profile.sinkName}' '.[] | select(.info.props["node.name"] == $name) | .id' | head -1`
        ];
        getSinkIdProc.running = true;
    }

    function cycleNext() {
        if (profiles.length === 0)
            return;
        const next = (activeProfileIndex + 1) % profiles.length;
        switchTo(next);
    }

    Component.onCompleted: refresh()

    // Detect current default sink
    Process {
        id: inspectProc
        command: ["bash", "-c", "wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep 'node.name' | head -1 | sed 's/.*\"\\(.*\\)\".*/\\1/'"]
        stdout: SplitParser {
            onRead: data => {
                const nodeName = data.trim();
                let found = -1;
                for (let i = 0; i < root.profiles.length; i++) {
                    if (root.profiles[i].sinkName === nodeName) {
                        found = i;
                        break;
                    }
                }
                root.activeProfileIndex = found;
                root.ready = true;
            }
        }
    }

    // Get PipeWire node ID for target sink
    Process {
        id: getSinkIdProc
        property int targetIndex: -1
        stdout: SplitParser {
            onRead: data => {
                const nodeId = data.trim();
                if (nodeId !== "") {
                    setDefaultProc.command = ["wpctl", "set-default", nodeId];
                    setDefaultProc.running = true;
                    root.activeProfileIndex = getSinkIdProc.targetIndex;
                }
            }
        }
    }

    // Set the default sink
    Process {
        id: setDefaultProc
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }
}
