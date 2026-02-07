import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

MouseArea {
    id: root
    required property var schemeData
    required property int index
    property bool isSelected: schemeData ? (Colorschemes.currentScheme === schemeData.id) : false
    property bool isHovered: containsMouse
    property var colors: schemeData && schemeData.colors ? schemeData.colors : ({})
    property bool isDarkMode: schemeData ? schemeData.darkMode : true

    property alias colBackground: background.color
    property alias colText: schemeName.color
    property alias radius: background.radius

    signal activated()

    hoverEnabled: true
    onClicked: root.activated()

    onContainsMouseChanged: {
        if (containsMouse && schemeData) {
            Colorschemes.startPreview(schemeData.id)
        }
    }

    Rectangle {
        id: background
        anchors.fill: parent
        anchors.margins: 6
        radius: Appearance.rounding.normal
        color: root.isSelected ? Appearance.colors.colSecondaryContainer :
               root.isHovered ? Appearance.colors.colLayer1Hover :
               Appearance.colors.colLayer1

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            // Color preview area with gradient and circles
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Gradient background showing main scheme colors
                Rectangle {
                    id: gradientPreview
                    anchors.fill: parent
                    radius: Appearance.rounding.small
                    clip: true

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: root.colors.m3background || "#1e1e2e" }
                        GradientStop { position: 0.5; color: root.colors.m3surface || "#11111b" }
                        GradientStop { position: 1.0; color: root.colors.m3surfaceContainer || "#313244" }
                    }

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: gradientPreview.width
                            height: gradientPreview.height
                            radius: Appearance.rounding.small
                        }
                    }

                    // Color circles row
                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Repeater {
                            model: [
                                { color: root.colors.m3primary || "#89b4fa", name: "primary" },
                                { color: root.colors.m3secondary || "#a6adc8", name: "secondary" },
                                { color: root.colors.m3tertiary || "#f5c2e7", name: "tertiary" },
                                { color: root.colors.m3error || "#f38ba8", name: "error" },
                                { color: root.colors.m3onBackground || "#cdd6f4", name: "text" }
                            ]

                            Rectangle {
                                required property var modelData
                                required property int index
                                width: 24
                                height: 24
                                radius: 12
                                color: modelData.color || "#ffffff"
                                border.width: 2
                                border.color: Qt.rgba(
                                    root.isDarkMode ? 1 : 0,
                                    root.isDarkMode ? 1 : 0,
                                    root.isDarkMode ? 1 : 0,
                                    0.2
                                )

                                scale: root.isHovered ? 1.1 : 1.0
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 150
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }

                    // Dark/Light mode indicator
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 6
                        width: 24
                        height: 24
                        radius: 12
                        color: Qt.rgba(0, 0, 0, 0.4)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 16
                            text: root.isDarkMode ? "dark_mode" : "light_mode"
                            color: "#ffffff"
                        }
                    }
                }
            }

            // Scheme name
            StyledText {
                id: schemeName
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: root.isSelected ? Font.Medium : Font.Normal
                color: root.isSelected ? Appearance.colors.colOnSecondaryContainer :
                       Appearance.colors.colOnLayer1

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                text: schemeData ? (schemeData.name || schemeData.id || "Unknown") : "Loading..."
            }
        }

        // Selection indicator
        Rectangle {
            visible: root.isSelected
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 4
            width: 32
            height: 4
            radius: 2
            color: Appearance.colors.colOnSecondaryContainer

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
        }
    }
}
