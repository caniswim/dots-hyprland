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

    readonly property var persistentState: Persistent.states.overlay.macClock
    readonly property bool isPinned: persistentState.pinned
    readonly property real sharedSize: Persistent.states.overlay.sharedMacWidgetSize

    readonly property real minWidgetSize: 120
    readonly property real maxWidgetSize: 300
    readonly property real widgetRadius: 28

    readonly property string cityName: "Santos"

    property int currentSeconds: {
        const date = new Date()
        return date.getSeconds()
    }

    // Sync: when this widget is resized, update shared size
    Connections {
        target: root.persistentState
        function onWidthChanged() {
            if (Math.abs(root.persistentState.width - Persistent.states.overlay.sharedMacWidgetSize) > 1) {
                Persistent.states.overlay.sharedMacWidgetSize = root.persistentState.width
            }
        }
    }

    // Sync: when shared size changes (other widget resized), update our size
    Connections {
        target: Persistent.states.overlay
        function onSharedMacWidgetSizeChanged() {
            if (Math.abs(root.persistentState.width - Persistent.states.overlay.sharedMacWidgetSize) > 1) {
                root.persistentState.width = Persistent.states.overlay.sharedMacWidgetSize
                root.persistentState.height = Persistent.states.overlay.sharedMacWidgetSize
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const date = new Date()
            root.currentSeconds = date.getSeconds()
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
        // Save to shared state so MacCalendar syncs
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
        title: "Clock"
        fancyBorders: true

        minimumWidth: root.minWidgetSize
        minimumHeight: root.minWidgetSize

        contentItem: ClockContent {
            property real size: Math.min(
                Math.max(root.sharedSize, root.minWidgetSize),
                root.maxWidgetSize
            )
            widgetSize: size
            widgetRadius: root.widgetRadius * (size / 160)
            cityName: root.cityName
            currentSeconds: root.currentSeconds
        }
    }

    // BACKGROUND WINDOW (pinned)
    PanelWindow {
        id: backgroundWindow
        visible: root.isPinned && !GlobalStates.overlayOpen
        color: "transparent"

        WlrLayershell.namespace: "quickshell:macClock"
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

            ClockContent {
                anchors.fill: parent
                widgetSize: backgroundWindow.widgetSize
                widgetRadius: root.widgetRadius * (backgroundWindow.widgetSize / 160)
                cityName: root.cityName
                currentSeconds: root.currentSeconds
            }
        }
    }

    // CLOCK CONTENT COMPONENT
    component ClockContent: Item {
        id: content
        property real widgetSize: 160
        property real widgetRadius: 28
        property string cityName: "Santos"
        property int currentSeconds: 0

        implicitWidth: widgetSize
        implicitHeight: widgetSize

        property real scaleFactor: widgetSize / 160

        property string currentHour: {
            const time = DateTime.time
            const match = time.match(/^(\d{1,2}):/)
            return match ? match[1] : ""
        }
        property string currentMinute: {
            const time = DateTime.time
            const match = time.match(/:(\d{2})/)
            return match ? match[1] : ""
        }

        property color textColor: Appearance.colors.colPrimary

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

            // DOTS - Starting from TOP CENTER (12 o'clock) going clockwise
            Item {
                id: dotsContainer
                anchors.fill: parent

                property int seconds: content.currentSeconds
                property color dotColor: content.textColor
                property real scale: content.scaleFactor
                property real containerW: width > 0 ? width : content.widgetSize
                property real containerH: height > 0 ? height : content.widgetSize

                Repeater {
                    model: 60

                    Rectangle {
                        id: dotRect
                        required property int index

                        // Geometry calculations
                        property real pad: 12 * dotsContainer.scale
                        property real iW: dotsContainer.containerW - 2 * pad
                        property real iH: dotsContainer.containerH - 2 * pad
                        property real r: Math.min(content.widgetRadius - pad, Math.min(iW, iH) / 2)
                        property real sH: iW - 2 * r  // horizontal straight
                        property real sV: iH - 2 * r  // vertical straight
                        property real arc: (Math.PI / 2) * r
                        property real perim: 2 * sH + 2 * sV + 4 * arc

                        // Start from top center
                        property real offset: arc + sH / 2
                        property real dist: ((dotRect.index / 60) * perim + offset) % perim

                        property real dotX: {
                            var d = dist
                            if (d < arc) {
                                return pad + r + r * Math.cos(Math.PI + d / r)
                            } else if (d < arc + sH) {
                                return pad + r + (d - arc)
                            } else if (d < 2*arc + sH) {
                                return pad + iW - r + r * Math.cos(-Math.PI/2 + (d - arc - sH) / r)
                            } else if (d < 2*arc + sH + sV) {
                                return pad + iW
                            } else if (d < 3*arc + sH + sV) {
                                return pad + iW - r + r * Math.cos((d - 2*arc - sH - sV) / r)
                            } else if (d < 3*arc + 2*sH + sV) {
                                return pad + iW - r - (d - 3*arc - sH - sV)
                            } else if (d < 4*arc + 2*sH + sV) {
                                return pad + r + r * Math.cos(Math.PI/2 + (d - 3*arc - 2*sH - sV) / r)
                            } else {
                                return pad
                            }
                        }

                        property real dotY: {
                            var d = dist
                            if (d < arc) {
                                return pad + r + r * Math.sin(Math.PI + d / r)
                            } else if (d < arc + sH) {
                                return pad
                            } else if (d < 2*arc + sH) {
                                return pad + r + r * Math.sin(-Math.PI/2 + (d - arc - sH) / r)
                            } else if (d < 2*arc + sH + sV) {
                                return pad + r + (d - 2*arc - sH)
                            } else if (d < 3*arc + sH + sV) {
                                return pad + iH - r + r * Math.sin((d - 2*arc - sH - sV) / r)
                            } else if (d < 3*arc + 2*sH + sV) {
                                return pad + iH
                            } else if (d < 4*arc + 2*sH + sV) {
                                return pad + iH - r + r * Math.sin(Math.PI/2 + (d - 3*arc - 2*sH - sV) / r)
                            } else {
                                return pad + iH - r - (d - 4*arc - 2*sH - sV)
                            }
                        }

                        property int currentSecs: content.currentSeconds
                        property bool isLit: dotRect.index < currentSecs

                        x: dotX - width / 2
                        y: dotY - height / 2
                        width: 4 * dotsContainer.scale
                        height: width
                        radius: width / 2
                        color: dotsContainer.dotColor
                        opacity: isLit ? 1.0 : 0.15

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }
            }

            // CONTENT
            Column {
                anchors.centerIn: parent
                spacing: 2 * content.scaleFactor

                // City name
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: content.cityName
                    font.family: "SF Pro Display"
                    font.pixelSize: 14 * content.scaleFactor
                    font.weight: Font.Medium
                    color: content.textColor
                    opacity: 0.9
                }

                // Time
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 0

                    AnimatedDigit {
                        value: content.currentHour
                        fontSize: Math.round(44 * content.scaleFactor)
                        textColor: content.textColor
                    }

                    // Colon - two dots vertically centered
                    Item {
                        width: 10 * content.scaleFactor
                        height: parent.height
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: 6 * content.scaleFactor
                            height: width
                            radius: width / 2
                            color: content.textColor
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -12 * content.scaleFactor
                        }

                        Rectangle {
                            width: 6 * content.scaleFactor
                            height: width
                            radius: width / 2
                            color: content.textColor
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 12 * content.scaleFactor
                        }
                    }

                    AnimatedDigit {
                        value: content.currentMinute
                        fontSize: Math.round(44 * content.scaleFactor)
                        textColor: content.textColor
                    }
                }
            }
        }
    }

    // ANIMATED DIGIT COMPONENT
    component AnimatedDigit: Item {
        id: digitRoot
        property string value: "00"
        property int fontSize: 44
        property color textColor: "#d4c4a0"
        property string previousValue: ""

        width: digitText.implicitWidth
        height: fontSize

        onValueChanged: {
            if (previousValue !== "" && previousValue !== value) {
                slideAnimation.restart()
            }
            previousValue = value
        }

        Text {
            id: digitText
            anchors.centerIn: parent
            text: digitRoot.value
            font.family: "SF Pro Display"
            font.pixelSize: digitRoot.fontSize
            font.weight: Font.Black
            color: digitRoot.textColor

            transform: Scale {
                id: scaleTransform
                origin.x: digitText.width / 2
                origin.y: digitText.height / 2
                xScale: 1.0
                yScale: 1.0
            }

            SequentialAnimation {
                id: slideAnimation

                ParallelAnimation {
                    NumberAnimation {
                        target: scaleTransform
                        property: "xScale"
                        from: 1.0; to: 0.92
                        duration: 100
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: scaleTransform
                        property: "yScale"
                        from: 1.0; to: 0.92
                        duration: 100
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: digitText
                        property: "opacity"
                        from: 1.0; to: 0.5
                        duration: 100
                        easing.type: Easing.OutQuad
                    }
                }

                ParallelAnimation {
                    NumberAnimation {
                        target: scaleTransform
                        property: "xScale"
                        from: 0.92; to: 1.0
                        duration: 250
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                    NumberAnimation {
                        target: scaleTransform
                        property: "yScale"
                        from: 0.92; to: 1.0
                        duration: 250
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                    NumberAnimation {
                        target: digitText
                        property: "opacity"
                        from: 0.5; to: 1.0
                        duration: 250
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }
}
