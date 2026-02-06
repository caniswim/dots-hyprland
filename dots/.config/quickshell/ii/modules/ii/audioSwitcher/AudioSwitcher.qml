import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)

    Loader {
        id: audioSwitcherLoader
        active: GlobalStates.audioSwitcherOpen
        onActiveChanged: {
            if (audioSwitcherLoader.active)
                AudioProfileSwitcher.refresh();
        }

        sourceComponent: PanelWindow {
            id: audioSwitcherRoot
            visible: audioSwitcherLoader.active
            property string subtitle: {
                if (AudioProfileSwitcher.activeProfileIndex >= 0)
                    return AudioProfileSwitcher.profiles[AudioProfileSwitcher.activeProfileIndex].name;
                return "";
            }

            function hide() {
                GlobalStates.audioSwitcherOpen = false;
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:audioSwitcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: ColorUtils.transparentize(Appearance.m3colors.m3background, Appearance.m3colors.darkmode ? 0.05 : 0.12)

            anchors {
                top: true
                left: true
                right: true
            }

            implicitWidth: root.focusedScreen?.width ?? 0
            implicitHeight: root.focusedScreen?.height ?? 0

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    audioSwitcherRoot.hide();
                }
            }

            ColumnLayout {
                id: contentColumn
                anchors.centerIn: parent
                spacing: 15

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        audioSwitcherRoot.hide();
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 0
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.title
                            variableAxes: Appearance.font.variableAxes.title
                        }
                        text: "Audio"
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.normal
                        text: "Select an audio output\nEsc or click anywhere to cancel"
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 15

                    Repeater {
                        model: AudioProfileSwitcher.profiles

                        AudioDeviceButton {
                            required property var modelData
                            required property int index
                            focus: audioSwitcherRoot.visible && index === 0
                            deviceIcon: modelData.icon
                            deviceName: modelData.name
                            isActive: AudioProfileSwitcher.activeProfileIndex === index
                            hasEq: modelData.hasEq
                            onClicked: {
                                AudioProfileSwitcher.switchTo(index);
                            }
                            onFocusChanged: {
                                if (focus)
                                    audioSwitcherRoot.subtitle = modelData.name;
                            }
                            KeyNavigation.left: index > 0 ? parent.children[index - 1] : null
                            KeyNavigation.right: index < AudioProfileSwitcher.profiles.length - 1 ? parent.children[index + 1] : null
                        }
                    }
                }

                DescriptionLabel {
                    Layout.alignment: Qt.AlignHCenter
                    text: audioSwitcherRoot.subtitle
                }
            }
        }
    }

    component DescriptionLabel: Rectangle {
        id: descriptionLabel
        property string text
        property color textColor: Appearance.colors.colOnTooltip
        color: Appearance.colors.colTooltip
        clip: true
        radius: Appearance.rounding.normal
        implicitHeight: descriptionLabelText.implicitHeight + 10 * 2
        implicitWidth: descriptionLabelText.implicitWidth + 15 * 2

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        StyledText {
            id: descriptionLabelText
            anchors.centerIn: parent
            color: descriptionLabel.textColor
            text: descriptionLabel.text
        }
    }

    IpcHandler {
        target: "audioSwitcher"

        function toggle(): void {
            GlobalStates.audioSwitcherOpen = !GlobalStates.audioSwitcherOpen;
        }

        function close(): void {
            GlobalStates.audioSwitcherOpen = false;
        }

        function open(): void {
            GlobalStates.audioSwitcherOpen = true;
        }
    }

    GlobalShortcut {
        name: "audioSwitcherToggle"
        description: "Toggles audio switcher on press"

        onPressed: {
            GlobalStates.audioSwitcherOpen = !GlobalStates.audioSwitcherOpen;
        }
    }
}
