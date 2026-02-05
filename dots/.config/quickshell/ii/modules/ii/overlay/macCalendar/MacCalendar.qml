pragma ComponentBehavior: Bound
import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.overlay

Item {
    id: root

    required property var modelData
    readonly property string identifier: modelData.identifier

    readonly property var persistentState: Persistent.states.overlay.macCalendar
    readonly property bool isPinned: persistentState.pinned
    readonly property real sharedSize: Persistent.states.overlay.sharedMacWidgetSize

    readonly property real minWidgetSize: 120
    readonly property real maxWidgetSize: 300
    readonly property real widgetRadius: 28

    // Sync: when this widget is resized/moved, update shared state
    Connections {
        target: root.persistentState
        function onWidthChanged() {
            if (Math.abs(root.persistentState.width - Persistent.states.overlay.sharedMacWidgetSize) > 1) {
                Persistent.states.overlay.sharedMacWidgetSize = root.persistentState.width
            }
        }
        function onYChanged() {
            if (Math.abs(root.persistentState.y - Persistent.states.overlay.sharedMacWidgetY) > 1) {
                Persistent.states.overlay.sharedMacWidgetY = root.persistentState.y
            }
        }
    }

    // Sync: when shared state changes (other widget changed), update ours
    Connections {
        target: Persistent.states.overlay
        function onSharedMacWidgetSizeChanged() {
            if (Math.abs(root.persistentState.width - Persistent.states.overlay.sharedMacWidgetSize) > 1) {
                root.persistentState.width = Persistent.states.overlay.sharedMacWidgetSize
                root.persistentState.height = Persistent.states.overlay.sharedMacWidgetSize
            }
        }
        function onSharedMacWidgetYChanged() {
            if (Math.abs(root.persistentState.y - Persistent.states.overlay.sharedMacWidgetY) > 1) {
                root.persistentState.y = Persistent.states.overlay.sharedMacWidgetY
            }
        }
    }

    onIsPinnedChanged: {
        OverlayContext.pin(identifier, isPinned)
    }
    Component.onCompleted: {
        if (isPinned) OverlayContext.pin(identifier, true)
    }
    Component.onDestruction: {
        OverlayContext.pin(identifier, false)
    }

    function togglePinned() {
        persistentState.pinned = !persistentState.pinned
    }

    function close() {
        Persistent.states.overlay.open = Persistent.states.overlay.open.filter(type => type !== root.identifier)
    }

    function savePosition(x, y, w, h) {
        persistentState.x = Math.round(x)
        persistentState.y = Math.round(y)
        const size = Math.max(w, h)
        // Save to shared state so MacClock syncs
        Persistent.states.overlay.sharedMacWidgetSize = Math.round(size)
    }

    // OVERLAY WIDGET
    StyledOverlayWidget {
        id: overlayWidget
        visible: GlobalStates.overlayOpen
        parent: root.parent

        modelData: root.modelData
        showClickabilityButton: false
        resizable: true
        clickthrough: true
        title: "Calendar"
        fancyBorders: true

        minimumWidth: root.minWidgetSize
        minimumHeight: root.minWidgetSize

        contentItem: CalendarContent {
            property real size: Math.min(
                Math.max(root.sharedSize, root.minWidgetSize),
                root.maxWidgetSize
            )
            widgetSize: size
            widgetRadius: root.widgetRadius * (size / 160)
        }
    }

    // BACKGROUND WINDOW (pinned)
    PanelWindow {
        id: backgroundWindow
        visible: root.isPinned && !GlobalStates.overlayOpen
        color: "transparent"

        WlrLayershell.namespace: "quickshell:macCalendar"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            left: true
        }

        property real widgetSize: Math.min(
            Math.max(root.sharedSize, root.minWidgetSize),
            root.maxWidgetSize
        )

        width: widgetSize + 20
        height: widgetSize + 20

        margins {
            top: root.persistentState.y
            left: root.persistentState.x
        }

        Item {
            anchors.fill: parent
            anchors.margins: 10

            CalendarContent {
                anchors.fill: parent
                widgetSize: backgroundWindow.widgetSize
                widgetRadius: root.widgetRadius * (backgroundWindow.widgetSize / 160)
            }
        }
    }

    // CALENDAR CONTENT COMPONENT
    component CalendarContent: Item {
        id: content
        property real widgetSize: 160
        property real widgetRadius: 28

        implicitWidth: widgetSize
        implicitHeight: widgetSize

        property real scaleFactor: widgetSize / 160

        // Date properties using Portuguese locale (remove periods from abbreviations)
        property string dayOfWeek: {
            const date = DateTime.clock.date
            return Qt.locale("pt_BR").toString(date, "ddd").replace(".", "")
        }
        property string month: {
            const date = DateTime.clock.date
            return Qt.locale("pt_BR").toString(date, "MMM").replace(".", "")
        }
        property string dayNumber: {
            const date = DateTime.clock.date
            return Qt.locale().toString(date, "d")
        }

        property color dayOfWeekColor: Appearance.colors.colError
        property color monthColor: Appearance.colors.colPrimary
        property color dayNumberColor: Appearance.colors.colPrimary

        Rectangle {
            id: bg
            anchors.fill: parent
            radius: content.widgetRadius
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: bg.width
                    height: bg.height
                    radius: bg.radius
                }
            }

            // CONTENT
            Column {
                anchors.centerIn: parent
                spacing: 2 * content.scaleFactor

                // Day of week + Month row
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8 * content.scaleFactor

                    // Day of week (red)
                    Text {
                        text: content.dayOfWeek
                        font.family: "SF Pro Display"
                        font.pixelSize: 22 * content.scaleFactor
                        font.weight: Font.Bold
                        font.capitalization: Font.Capitalize
                        color: content.dayOfWeekColor
                    }

                    // Month (primary color)
                    Text {
                        text: content.month
                        font.family: "SF Pro Display"
                        font.pixelSize: 22 * content.scaleFactor
                        font.weight: Font.Bold
                        font.capitalization: Font.Capitalize
                        color: content.monthColor
                    }
                }

                // Day number (large)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: content.dayNumber
                    font.family: "SF Pro Display"
                    font.pixelSize: 85 * content.scaleFactor
                    font.weight: Font.Black
                    color: content.dayNumberColor
                }
            }
        }
    }
}
