pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.overlay
import "./calendar_layout.js" as CalendarLayout

Item {
    id: root

    required property var modelData
    readonly property string identifier: modelData.identifier

    readonly property var persistentState: Persistent.states.overlay.googleCalendar
    readonly property bool isPinned: persistentState.pinned

    // Configuration
    readonly property int refreshIntervalMs: Config.options.overlay.googleCalendar.refreshIntervalMinutes * 60 * 1000
    readonly property int daysAhead: Config.options.overlay.googleCalendar.daysAhead
    readonly property string googleCalendarUrl: Config.options.overlay.googleCalendar.googleCalendarUrl

    // State
    property var events: []
    property var eventsByDate: ({})
    property bool loading: true
    property bool hasError: false
    property string errorMessage: ""

    // Current date for calendar
    property date currentDate: new Date()

    onIsPinnedChanged: {
        OverlayContext.pin(identifier, isPinned)
    }
    Component.onCompleted: {
        fetchEvents()
        if (isPinned) OverlayContext.pin(identifier, true)
    }
    Component.onDestruction: {
        OverlayContext.pin(identifier, false)
    }

    // Timer for periodic refresh
    Timer {
        interval: root.refreshIntervalMs
        running: true
        repeat: true
        onTriggered: root.fetchEvents()
    }

    // Timer for updating current date at midnight
    Timer {
        id: midnightTimer
        interval: {
            const now = new Date()
            const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 1)
            return tomorrow - now
        }
        running: true
        repeat: false
        onTriggered: {
            root.currentDate = new Date()
            root.fetchEvents()
            midnightTimer.restart()
        }
    }

    // Process for gcalcli
    Process {
        id: gcalcliProcess
        property var buffer: []

        command: ["gcalcli", "agenda", "--nocolor", "--tsv", "today", "+" + root.daysAhead + " days"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                if (trimmed.length > 0) {
                    gcalcliProcess.buffer.push(trimmed)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.parseEvents(gcalcliProcess.buffer)
                root.hasError = false
                root.errorMessage = ""
            } else {
                root.hasError = true
                if (exitCode === 127) {
                    root.errorMessage = "gcalcli not installed"
                } else {
                    root.errorMessage = "gcalcli error (code: " + exitCode + ")"
                }
                root.events = []
                root.eventsByDate = {}
            }
            gcalcliProcess.buffer = []
            root.loading = false
        }
    }

    function fetchEvents() {
        root.loading = true
        gcalcliProcess.buffer = []
        gcalcliProcess.running = true
    }

    function parseEvents(lines: var) {
        const parsedEvents = []
        const byDate = {}

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            const parts = line.split('\t')

            // TSV format: date, start_time, end_time, link, title, location, description
            if (parts.length >= 5) {
                const dateStr = parts[0]
                const startTime = parts[1]
                const endTime = parts[2]
                const link = parts[3] || ""
                const title = parts[4] || ""
                const location = parts.length > 5 ? parts[5] : ""

                // Parse date (YYYY-MM-DD format)
                const dateParts = dateStr.split('-')
                if (dateParts.length === 3) {
                    const eventDate = new Date(
                        parseInt(dateParts[0]),
                        parseInt(dateParts[1]) - 1,
                        parseInt(dateParts[2])
                    )

                    const event = {
                        date: eventDate,
                        dateStr: dateStr,
                        startTime: startTime,
                        endTime: endTime,
                        link: link,
                        title: title,
                        location: location
                    }

                    parsedEvents.push(event)

                    // Group by date
                    if (!byDate[dateStr]) {
                        byDate[dateStr] = []
                    }
                    byDate[dateStr].push(event)
                }
            }
        }

        root.events = parsedEvents
        root.eventsByDate = byDate
    }

    function hasEventsOnDate(date: date): bool {
        const dateStr = formatDateKey(date)
        return root.eventsByDate[dateStr] !== undefined && root.eventsByDate[dateStr].length > 0
    }

    function formatDateKey(date: date): string {
        const year = date.getFullYear()
        const month = String(date.getMonth() + 1).padStart(2, '0')
        const day = String(date.getDate()).padStart(2, '0')
        return year + "-" + month + "-" + day
    }

    function openGoogleCalendar() {
        Qt.openUrlExternally(root.googleCalendarUrl)
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
        persistentState.width = Math.round(w)
        persistentState.height = Math.round(h)
    }

    // ==========================================
    // WIDGET NO OVERLAY (quando overlay aberto)
    // ==========================================
    StyledOverlayWidget {
        id: overlayWidget
        visible: GlobalStates.overlayOpen
        parent: root.parent

        modelData: root.modelData
        showClickabilityButton: false
        resizable: true
        clickthrough: true
        title: "Google Calendar"

        minimumWidth: 400
        minimumHeight: 250

        contentItem: GoogleCalendarContent {
            widgetWidth: Math.max(400, root.persistentState.width)
            widgetHeight: Math.max(250, root.persistentState.height)
            currentDate: root.currentDate
            events: root.events
            eventsByDate: root.eventsByDate
            loading: root.loading
            hasError: root.hasError
            errorMessage: root.errorMessage
            hasEventsOnDate: root.hasEventsOnDate
            onOpenCalendar: root.openGoogleCalendar()
        }
    }

    // ==========================================
    // JANELA BACKGROUND (quando pinned e overlay fechado)
    // ==========================================
    PanelWindow {
        id: backgroundWindow
        visible: root.isPinned && !GlobalStates.overlayOpen
        color: "transparent"

        WlrLayershell.namespace: "quickshell:googleCalendar"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            left: true
        }

        property real widgetWidth: Math.max(400, root.persistentState.width)
        property real widgetHeight: Math.max(250, root.persistentState.height)

        width: widgetWidth + 20
        height: widgetHeight + 20

        margins {
            top: root.persistentState.y
            left: root.persistentState.x
        }

        Item {
            anchors.fill: parent
            anchors.margins: 10

            GoogleCalendarContent {
                anchors.fill: parent
                widgetWidth: backgroundWindow.widgetWidth
                widgetHeight: backgroundWindow.widgetHeight
                currentDate: root.currentDate
                events: root.events
                eventsByDate: root.eventsByDate
                loading: root.loading
                hasError: root.hasError
                errorMessage: root.errorMessage
                hasEventsOnDate: root.hasEventsOnDate
                radius: Appearance.rounding.windowRounding
                onOpenCalendar: root.openGoogleCalendar()
            }
        }
    }

    // ==========================================
    // CALENDAR CONTENT COMPONENT
    // ==========================================
    component GoogleCalendarContent: Item {
        id: content
        property real widgetWidth: 500
        property real widgetHeight: 300
        property date currentDate: new Date()
        property var events: []
        property var eventsByDate: ({})
        property bool loading: false
        property bool hasError: false
        property string errorMessage: ""
        property var hasEventsOnDate: function(date) { return false }
        property real radius: Appearance.rounding.windowRounding - 6

        // Responsive scaling based on widget size
        readonly property real baseWidth: 500
        readonly property real baseHeight: 300
        readonly property real scaleFactor: Math.min(widgetWidth / baseWidth, widgetHeight / baseHeight)

        implicitWidth: widgetWidth
        implicitHeight: widgetHeight

        signal openCalendar()

        Rectangle {
            id: bg
            anchors.fill: parent
            color: Appearance.colors.colLayer0
            radius: content.radius
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: content.openCalendar()
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16 * content.scaleFactor
                spacing: 16 * content.scaleFactor

                // Left side: Calendar grid
                Item {
                    id: calendarContainer
                    Layout.fillHeight: true
                    Layout.preferredWidth: 240 * content.scaleFactor

                    // Responsive cell size based on available space
                    readonly property real cellSpacing: 1 * content.scaleFactor
                    readonly property real headerHeight: monthHeader.implicitHeight + columnLayout.spacing
                    readonly property real availableHeight: height - headerHeight - (columnLayout.spacing * 2)
                    readonly property real cellSizeFromHeight: (availableHeight / 6.6) - cellSpacing  // 6 semanas + header dias
                    readonly property real cellSizeFromWidth: (width - 6 * cellSpacing) / 7           // 7 dias - 6 espaçamentos
                    readonly property real cellSize: Math.max(20, Math.min(cellSizeFromHeight, cellSizeFromWidth))

                    ColumnLayout {
                        id: columnLayout
                        anchors.fill: parent
                        spacing: 2 * content.scaleFactor

                        // Month/Year header
                        Text {
                            id: monthHeader
                            readonly property real gridWidth: 7 * calendarContainer.cellSize + 6 * calendarContainer.cellSpacing
                            Layout.leftMargin: (calendarContainer.width - gridWidth) / 2 + 6 * content.scaleFactor
                            text: content.currentDate.toLocaleDateString(Qt.locale("en_US"), "MMMM yyyy")
                            font.family: Appearance.font.family.main
                            font.pixelSize: Math.round(Appearance.font.pixelSize.normal * content.scaleFactor)
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                        }

                        // Weekday headers
                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: calendarContainer.cellSpacing

                            Repeater {
                                model: CalendarLayout.weekDays

                                Item {
                                    required property var modelData
                                    width: calendarContainer.cellSize
                                    height: calendarContainer.cellSize * 0.6

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.day
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * content.scaleFactor)
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }
                                }
                            }
                        }

                        // Calendar grid - Row-based pattern
                        Repeater {
                            id: calendarRows
                            model: 6  // 6 weeks

                            delegate: Row {
                                required property int index

                                Layout.alignment: Qt.AlignHCenter
                                spacing: calendarContainer.cellSpacing

                                Repeater {
                                    model: CalendarLayout.getCalendarLayout(content.currentDate, true)[index] || []

                                    delegate: Item {
                                        required property var modelData
                                        required property int index

                                        width: calendarContainer.cellSize
                                        height: calendarContainer.cellSize

                                        property int weekIndex: parent.parent.index
                                        property bool isCurrentMonth: modelData.today >= 0
                                        property bool isToday: modelData.today === 1
                                        property date cellDate: {
                                            const firstDayOfMonth = new Date(content.currentDate.getFullYear(), content.currentDate.getMonth(), 1)
                                            const weekdayOfFirst = (firstDayOfMonth.getDay() + 6) % 7
                                            const dayOffset = (weekIndex * 7) + index - weekdayOfFirst
                                            return new Date(content.currentDate.getFullYear(), content.currentDate.getMonth(), dayOffset + 1)
                                        }
                                        property bool hasEvents: isCurrentMonth && content.hasEventsOnDate(cellDate)

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: parent.width * 0.85
                                            height: width
                                            radius: width / 2
                                            color: isToday ? Appearance.colors.colPrimary : "transparent"
                                        }

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 1

                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: modelData.day
                                                font.family: Appearance.font.family.numbers
                                                font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * content.scaleFactor)
                                                font.weight: isToday ? Font.Bold : Font.Normal
                                                color: isToday ? Appearance.colors.colOnPrimary :
                                                       isCurrentMonth ? Appearance.colors.colOnSurface :
                                                       Appearance.colors.colOnSurfaceVariant
                                                opacity: isCurrentMonth ? 1.0 : 0.4
                                            }

                                            // Event dot indicator
                                            Rectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: Math.max(3, 4 * content.scaleFactor)
                                                height: width
                                                radius: width / 2
                                                color: isToday ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                                                visible: hasEvents
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Separator
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    color: Appearance.colors.colOutlineVariant
                }

                // Right side: Events list
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                    spacing: 8 * content.scaleFactor

                    // Header
                    Text {
                        text: "Upcoming Events"
                        font.family: Appearance.font.family.main
                        font.pixelSize: Math.round(Appearance.font.pixelSize.normal * content.scaleFactor)
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }

                    // Loading state
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: content.loading

                        Column {
                            anchors.centerIn: parent
                            spacing: 8 * content.scaleFactor

                            MaterialSymbol {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "sync"
                                iconSize: Math.round(32 * content.scaleFactor)
                                color: Appearance.colors.colOnSurfaceVariant

                                RotationAnimation on rotation {
                                    from: 0
                                    to: 360
                                    duration: 1000
                                    loops: Animation.Infinite
                                    running: content.loading
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Loading..."
                                font.family: Appearance.font.family.main
                                font.pixelSize: Math.round(Appearance.font.pixelSize.small * content.scaleFactor)
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    // Error state
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !content.loading && content.hasError

                        Column {
                            anchors.centerIn: parent
                            spacing: 8 * content.scaleFactor

                            MaterialSymbol {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "error"
                                iconSize: Math.round(32 * content.scaleFactor)
                                color: Appearance.colors.colError
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: content.errorMessage
                                font.family: Appearance.font.family.main
                                font.pixelSize: Math.round(Appearance.font.pixelSize.small * content.scaleFactor)
                                color: Appearance.colors.colOnSurfaceVariant
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: content.errorMessage === "gcalcli not installed" ?
                                      "Install with: pip install gcalcli" : ""
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * content.scaleFactor)
                                color: Appearance.colors.colOnSurfaceVariant
                                visible: text.length > 0
                            }
                        }
                    }

                    // Empty state
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !content.loading && !content.hasError && content.events.length === 0

                        Column {
                            anchors.centerIn: parent
                            spacing: 8 * content.scaleFactor

                            MaterialSymbol {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "event_available"
                                iconSize: Math.round(32 * content.scaleFactor)
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "No upcoming events"
                                font.family: Appearance.font.family.main
                                font.pixelSize: Math.round(Appearance.font.pixelSize.small * content.scaleFactor)
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    // Events list
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !content.loading && !content.hasError && content.events.length > 0
                        clip: true
                        spacing: 4 * content.scaleFactor
                        model: content.events

                        section.property: "dateStr"
                        section.delegate: Item {
                            required property string section

                            width: ListView.view.width
                            height: sectionText.implicitHeight + 8 * content.scaleFactor

                            Text {
                                id: sectionText
                                anchors.bottom: parent.bottom
                                text: {
                                    const parts = section.split('-')
                                    const date = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]))
                                    const today = new Date()
                                    const tomorrow = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1)

                                    if (date.toDateString() === today.toDateString()) {
                                        return "TODAY"
                                    } else if (date.toDateString() === tomorrow.toDateString()) {
                                        return "TOMORROW"
                                    } else {
                                        return date.toLocaleDateString(Qt.locale(), "ddd, MMM d")
                                    }
                                }
                                font.family: Appearance.font.family.main
                                font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * content.scaleFactor)
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: sectionText.right
                                anchors.leftMargin: 8 * content.scaleFactor
                                anchors.right: parent.right
                                height: 1
                                color: Appearance.colors.colOutlineVariant
                                opacity: 0.5
                            }
                        }

                        delegate: Item {
                            id: eventDelegate
                            required property var modelData
                            required property int index

                            width: ListView.view.width
                            height: eventRow.implicitHeight + 6 * content.scaleFactor

                            RowLayout {
                                id: eventRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 4 * content.scaleFactor
                                spacing: 8 * content.scaleFactor

                                // Time
                                Text {
                                    Layout.preferredWidth: 45 * content.scaleFactor
                                    text: eventDelegate.modelData.startTime || ""
                                    font.family: Appearance.font.family.numbers
                                    font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * content.scaleFactor)
                                    color: Appearance.colors.colOnSurfaceVariant
                                }

                                // Color bar
                                Rectangle {
                                    Layout.preferredWidth: 3 * content.scaleFactor
                                    Layout.fillHeight: true
                                    Layout.topMargin: 2 * content.scaleFactor
                                    Layout.bottomMargin: 2 * content.scaleFactor
                                    radius: 1.5 * content.scaleFactor
                                    color: Appearance.colors.colPrimary
                                }

                                // Event details
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        Layout.fillWidth: true
                                        text: eventDelegate.modelData.title || ""
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: Math.round(Appearance.font.pixelSize.small * content.scaleFactor) + 1
                                        color: Appearance.colors.colOnSurface
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: eventDelegate.modelData.location || ""
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * content.scaleFactor)
                                        color: Appearance.colors.colOnSurfaceVariant
                                        elide: Text.ElideRight
                                        visible: text.length > 0
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
