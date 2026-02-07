import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    Loader {
        id: colorschemeSelectorLoader
        active: GlobalStates.colorschemeSelectorOpen

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:colorschemeSelector"
            WlrLayershell.layer: WlrLayer.Overlay
            color: "transparent"

            anchors.top: true
            margins {
                top: Config?.options.bar.vertical ? Appearance.sizes.hyprlandGapsOut : Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
            }

            mask: Region {
                item: content
            }

            implicitHeight: 500
            implicitWidth: 700

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow)
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow)
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    Colorschemes.cancelPreview()
                    GlobalStates.colorschemeSelectorOpen = false
                }
            }

            ColorschemeSelectorContent {
                id: content
                anchors {
                    fill: parent
                }
            }
        }
    }

    function toggleColorschemeSelector() {
        GlobalStates.colorschemeSelectorOpen = !GlobalStates.colorschemeSelectorOpen
    }

    IpcHandler {
        target: "colorschemeSelector"

        function toggle(): void {
            root.toggleColorschemeSelector()
        }

        function open(): void {
            GlobalStates.colorschemeSelectorOpen = true
        }

        function close(): void {
            Colorschemes.cancelPreview()
            GlobalStates.colorschemeSelectorOpen = false
        }
    }

    GlobalShortcut {
        name: "colorschemeSelectorToggle"
        description: "Toggle colorscheme selector"
        onPressed: {
            root.toggleColorschemeSelector()
        }
    }
}
