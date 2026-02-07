import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

MouseArea {
    id: root
    property int columns: 4
    property real previewCellAspectRatio: 4 / 3

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            Colorschemes.cancelPreview()
            GlobalStates.colorschemeSelectorOpen = false
            event.accepted = true
        } else if (event.key === Qt.Key_Left) {
            grid.moveSelection(-1)
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            grid.moveSelection(1)
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            grid.moveSelection(-grid.columns)
            event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            grid.moveSelection(grid.columns)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            grid.activateCurrent()
            event.accepted = true
        }
    }

    onExited: {
        Colorschemes.cancelPreview()
    }

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: mainLayout.implicitWidth

    StyledRectangularShadow {
        target: selectorBackground
    }

    Rectangle {
        id: selectorBackground
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        focus: true
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        ColumnLayout {
            id: mainLayout
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 4
                implicitHeight: headerRow.implicitHeight + 16
                color: Appearance.colors.colLayer1
                radius: selectorBackground.radius - 4

                RowLayout {
                    id: headerRow
                    anchors {
                        fill: parent
                        margins: 8
                    }

                    MaterialSymbol {
                        Layout.leftMargin: 8
                        iconSize: Appearance.font.pixelSize.larger
                        text: "palette"
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        font {
                            pixelSize: Appearance.font.pixelSize.normal
                            weight: Font.Medium
                        }
                        text: Translation.tr("Select Color Scheme")
                        color: Appearance.colors.colOnLayer1
                    }

                    IconToolbarButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: {
                            Colorschemes.cancelPreview()
                            GlobalStates.colorschemeSelectorOpen = false
                        }
                        text: "close"
                        StyledToolTip {
                            text: Translation.tr("Close")
                        }
                    }
                }
            }

            // Grid area
            Item {
                id: gridDisplayRegion
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 4
                Layout.minimumHeight: 300

                GridView {
                    id: grid
                    anchors.fill: parent
                    anchors.margins: 4

                    readonly property int columns: root.columns
                    property int currentIndex: 0

                    cellWidth: Math.max(100, width / root.columns)
                    cellHeight: Math.max(75, cellWidth / root.previewCellAspectRatio)
                    interactive: true
                    clip: true
                    keyNavigationWraps: true
                    boundsBehavior: Flickable.StopAtBounds
                    bottomMargin: toolbar.implicitHeight + 8
                    ScrollBar.vertical: StyledScrollBar {}

                    function moveSelection(delta) {
                        currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta))
                        positionViewAtIndex(currentIndex, GridView.Contain)
                        const item = Colorschemes.schemes.get(currentIndex)
                        if (item) {
                            Colorschemes.startPreview(item.schemeId)
                        }
                    }

                    function activateCurrent() {
                        const item = Colorschemes.schemes.get(currentIndex)
                        if (item) {
                            Colorschemes.applyScheme(item.schemeId)
                            GlobalStates.colorschemeSelectorOpen = false
                        }
                    }

                    model: Colorschemes.schemes

                    delegate: Rectangle {
                        id: delegateRoot
                        required property int index
                        required property string schemeId
                        required property string schemeName
                        required property bool darkMode
                        required property string colorsJson

                        property var colors: colorsJson ? JSON.parse(colorsJson) : ({})
                        property bool isSelected: Colorschemes.currentScheme === schemeId
                        property bool isHovered: delegateMouseArea.containsMouse

                        width: grid.cellWidth
                        height: grid.cellHeight

                        color: "transparent"

                        Rectangle {
                            id: itemBackground
                            anchors.fill: parent
                            anchors.margins: 6
                            radius: Appearance.rounding.normal
                            color: delegateRoot.isSelected ? Appearance.colors.colSecondaryContainer :
                                   delegateRoot.isHovered ? Appearance.colors.colLayer1Hover :
                                   Appearance.colors.colLayer1

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                // Color preview
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Appearance.rounding.small
                                    clip: true

                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: delegateRoot.colors.m3background || "#1e1e2e" }
                                        GradientStop { position: 0.5; color: delegateRoot.colors.m3surface || "#11111b" }
                                        GradientStop { position: 1.0; color: delegateRoot.colors.m3surfaceContainer || "#313244" }
                                    }

                                    // Color circles
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Repeater {
                                            model: [
                                                delegateRoot.colors.m3primary || "#89b4fa",
                                                delegateRoot.colors.m3secondary || "#a6adc8",
                                                delegateRoot.colors.m3tertiary || "#f5c2e7",
                                                delegateRoot.colors.m3error || "#f38ba8",
                                                delegateRoot.colors.m3onBackground || "#cdd6f4"
                                            ]

                                            Rectangle {
                                                required property string modelData
                                                width: 20
                                                height: 20
                                                radius: 10
                                                color: modelData
                                                border.width: 1
                                                border.color: Qt.rgba(delegateRoot.darkMode ? 1 : 0, delegateRoot.darkMode ? 1 : 0, delegateRoot.darkMode ? 1 : 0, 0.3)
                                            }
                                        }
                                    }

                                    // Dark/Light indicator
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 4
                                        width: 20
                                        height: 20
                                        radius: 10
                                        color: Qt.rgba(0, 0, 0, 0.5)

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            iconSize: 12
                                            text: delegateRoot.darkMode ? "dark_mode" : "light_mode"
                                            color: "#ffffff"
                                        }
                                    }
                                }

                                // Name
                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: delegateRoot.isSelected ? Font.Medium : Font.Normal
                                    color: delegateRoot.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    text: delegateRoot.schemeName
                                }
                            }
                        }

                        MouseArea {
                            id: delegateMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                Colorschemes.applyScheme(delegateRoot.schemeId)
                                GlobalStates.colorschemeSelectorOpen = false
                            }
                            onEntered: {
                                grid.currentIndex = delegateRoot.index
                                Colorschemes.startPreview(delegateRoot.schemeId)
                            }
                        }

                        Component.onCompleted: {
                            console.log("[Delegate] Created:", index, schemeId)
                        }
                    }

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: gridDisplayRegion.width
                            height: gridDisplayRegion.height
                            radius: selectorBackground.radius - 8
                        }
                    }
                }

                // Bottom toolbar
                Toolbar {
                    id: toolbar
                    anchors {
                        bottom: parent.bottom
                        horizontalCenter: parent.horizontalCenter
                        bottomMargin: 8
                    }

                    IconToolbarButton {
                        implicitWidth: height
                        onClicked: {
                            Colorschemes.loadSchemes()
                        }
                        text: "refresh"
                        StyledToolTip {
                            text: Translation.tr("Reload schemes")
                        }
                    }

                    IconToolbarButton {
                        implicitWidth: height
                        onClicked: {
                            Colorschemes.cancelPreview()
                            GlobalStates.colorschemeSelectorOpen = false
                        }
                        text: "close"
                        StyledToolTip {
                            text: Translation.tr("Cancel")
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onColorschemeSelectorOpenChanged() {
            if (GlobalStates.colorschemeSelectorOpen) {
                selectorBackground.forceActiveFocus()
            } else {
                Colorschemes.cancelPreview()
            }
        }
    }
}
