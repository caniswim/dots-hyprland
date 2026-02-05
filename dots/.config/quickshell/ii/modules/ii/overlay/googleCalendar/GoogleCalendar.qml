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
    readonly property bool tasksEnabled: Config.options.overlay.googleCalendar.tasksEnabled

    // State
    property var events: []
    property var tasks: []
    property var combinedItems: []
    property var eventsByDate: ({})
    property bool loading: true
    property bool tasksLoading: false
    property bool hasError: false
    property string errorMessage: ""

    // Current date for calendar
    property date currentDate: new Date()

    onIsPinnedChanged: {
        OverlayContext.pin(identifier, isPinned)
    }
    Component.onCompleted: {
        fetchAll()
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
        onTriggered: root.fetchAll()
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
            root.fetchAll()
            midnightTimer.restart()
        }
    }

    // Process for gcalcli
    Process {
        id: gcalcliProcess
        property var buffer: []

        command: ["gcalcli", "agenda", "--nocolor", "--tsv", "--details", "all", "today", "+" + root.daysAhead + " days"]
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
            root.mergeEventsAndTasks()
        }
    }

    // Process for gtasks-cli (Google Tasks CLI)
    Process {
        id: gtasksProcess
        property string buffer: ""

        command: [Directories.home + "/.local/bin/gtasks-cli", "list"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                gtasksProcess.buffer += data
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.parseTasks(gtasksProcess.buffer)
            } else {
                // Silently fail for tasks - don't show error if gtasks-cli not installed
                root.tasks = []
            }
            gtasksProcess.buffer = ""
            root.tasksLoading = false
            root.mergeEventsAndTasks()
        }
    }

    // Process for completing a task
    Process {
        id: completeTaskProcess
        property string taskId: ""
        command: [Directories.home + "/.local/bin/gtasks-cli", "done", taskId]
        onExited: root.fetchTasks()
    }

    function fetchAll() {
        fetchEvents()
        if (root.tasksEnabled) {
            fetchTasks()
        }
    }

    function fetchTasks() {
        root.tasksLoading = true
        gtasksProcess.buffer = []
        gtasksProcess.running = true
    }

    function fetchEvents() {
        root.loading = true
        gcalcliProcess.buffer = []
        gcalcliProcess.running = true
    }

    function parseEvents(lines: var) {
        const parsedEvents = []
        const byDate = {}

        // Skip header line (first line with --details all)
        for (let i = 1; i < lines.length; i++) {
            const line = lines[i]
            const parts = line.split('\t')

            // TSV format with --details all:
            // [0]=id, [1]=start_date, [2]=start_time, [3]=end_date, [4]=end_time,
            // [5]=html_link, [6]=hangout_link, [7]=conference_type, [8]=conference_uri,
            // [9]=title, [10]=location, [11]=description
            if (parts.length >= 10) {
                const dateStr = parts[1]
                const startTime = parts[2]
                const endTime = parts[4]
                const link = parts[5] || ""
                const title = parts[9] || ""
                const location = parts.length > 10 ? parts[10] : ""

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

    function parseTasks(jsonStr: string) {
        const parsedTasks = []

        // Calculate date range: today to today + daysAhead
        const today = new Date()
        today.setHours(0, 0, 0, 0)
        const maxDate = new Date(today)
        maxDate.setDate(maxDate.getDate() + root.daysAhead)

        try {
            const tasksData = JSON.parse(jsonStr)
            for (let i = 0; i < tasksData.length; i++) {
                const t = tasksData[i]
                if (t.due && t.status !== "completed") {
                    // Parse due date and filter by range
                    const dueParts = t.due.split('-')
                    if (dueParts.length === 3) {
                        const dueDate = new Date(
                            parseInt(dueParts[0]),
                            parseInt(dueParts[1]) - 1,
                            parseInt(dueParts[2])
                        )
                        dueDate.setHours(0, 0, 0, 0)

                        // Only include tasks within the date range
                        if (dueDate >= today && dueDate <= maxDate) {
                            const task = {
                                type: "task",
                                title: t.title || "",
                                dateStr: t.due,
                                completed: t.status === "completed",
                                taskId: t.tasklist_id + ":" + t.id
                            }
                            parsedTasks.push(task)
                        }
                    }
                }
            }
        } catch (e) {
            console.log("Failed to parse tasks JSON:", e)
        }
        root.tasks = parsedTasks
    }

    function mergeEventsAndTasks() {
        // Only merge if both calendar and tasks have finished loading
        if (root.loading || root.tasksLoading) {
            return
        }

        const combined = []
        const byDate = {}

        // Add events with type marker
        for (const event of root.events) {
            const item = {
                type: "event",
                date: event.date,
                dateStr: event.dateStr,
                startTime: event.startTime,
                endTime: event.endTime,
                title: event.title,
                location: event.location,
                link: event.link,
                completed: false,
                taskId: ""
            }
            combined.push(item)

            // Group by date
            if (!byDate[event.dateStr]) {
                byDate[event.dateStr] = []
            }
            byDate[event.dateStr].push(item)
        }

        // Add tasks
        for (const task of root.tasks) {
            if (task.completed) continue // Skip completed tasks

            const dateParts = task.dateStr.split('-')
            if (dateParts.length === 3) {
                const taskDate = new Date(
                    parseInt(dateParts[0]),
                    parseInt(dateParts[1]) - 1,
                    parseInt(dateParts[2])
                )

                const item = {
                    type: "task",
                    date: taskDate,
                    dateStr: task.dateStr,
                    title: task.title,
                    startTime: "",
                    endTime: "",
                    location: "",
                    link: "",
                    completed: task.completed,
                    taskId: task.taskId
                }
                combined.push(item)

                // Group by date
                if (!byDate[task.dateStr]) {
                    byDate[task.dateStr] = []
                }
                byDate[task.dateStr].push(item)
            }
        }

        // Sort combined items by date, then events before tasks, then by startTime
        combined.sort((a, b) => {
            // First: sort by date
            if (a.dateStr !== b.dateStr) {
                return a.dateStr.localeCompare(b.dateStr)
            }
            // Same date: events always before tasks
            if (a.type !== b.type) {
                return a.type === "event" ? -1 : 1
            }
            // Both are events: sort by startTime
            if (a.type === "event" && a.startTime && b.startTime) {
                return a.startTime.localeCompare(b.startTime)
            }
            return 0
        })

        // Sort items within each date group using Object.keys
        const dateKeys = Object.keys(byDate)
        for (let i = 0; i < dateKeys.length; i++) {
            const dateStr = dateKeys[i]
            byDate[dateStr].sort((a, b) => {
                // Events always before tasks
                if (a.type !== b.type) {
                    return a.type === "event" ? -1 : 1
                }
                // Both are events: sort by startTime
                if (a.type === "event" && a.startTime && b.startTime) {
                    return a.startTime.localeCompare(b.startTime)
                }
                return 0
            })
        }

        root.combinedItems = combined
        root.eventsByDate = byDate
    }

    function toggleTaskComplete(taskId: string) {
        completeTaskProcess.taskId = taskId
        completeTaskProcess.running = true
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
            events: root.combinedItems
            eventsByDate: root.eventsByDate
            loading: root.loading || root.tasksLoading
            hasError: root.hasError
            errorMessage: root.errorMessage
            hasEventsOnDate: root.hasEventsOnDate
            onOpenCalendar: root.openGoogleCalendar()
            onToggleTask: (taskId) => root.toggleTaskComplete(taskId)
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
                events: root.combinedItems
                eventsByDate: root.eventsByDate
                loading: root.loading || root.tasksLoading
                hasError: root.hasError
                errorMessage: root.errorMessage
                hasEventsOnDate: root.hasEventsOnDate
                radius: Appearance.rounding.windowRounding
                onOpenCalendar: root.openGoogleCalendar()
                onToggleTask: (taskId) => root.toggleTaskComplete(taskId)
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
        signal toggleTask(string taskId)

        Rectangle {
            id: bg
            anchors.fill: parent
            color: ColorUtils.transparentize(Appearance.colors.colLayer0, Config.options.overlay.widgetTransparency)
            radius: content.radius
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.colors.colLayer0Border, Config.options.overlay.widgetTransparency)

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

                                // Time (for events) or Checkbox (for tasks)
                                Loader {
                                    Layout.preferredWidth: 45 * content.scaleFactor
                                    Layout.alignment: Qt.AlignTop
                                    sourceComponent: eventDelegate.modelData.type === "task" ? taskCheckboxComponent : eventTimeComponent
                                }

                                // Color bar - different color for tasks
                                Rectangle {
                                    Layout.preferredWidth: 3 * content.scaleFactor
                                    Layout.fillHeight: true
                                    Layout.topMargin: 2 * content.scaleFactor
                                    Layout.bottomMargin: 2 * content.scaleFactor
                                    radius: 1.5 * content.scaleFactor
                                    color: eventDelegate.modelData.type === "task" ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
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

                            // Component for event time display
                            Component {
                                id: eventTimeComponent
                                ColumnLayout {
                                    spacing: 0

                                    Text {
                                        text: eventDelegate.modelData.startTime || ""
                                        font.family: Appearance.font.family.numbers
                                        font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * content.scaleFactor)
                                        color: Appearance.colors.colOnSurface
                                    }

                                    Text {
                                        text: eventDelegate.modelData.endTime || ""
                                        font.family: Appearance.font.family.numbers
                                        font.pixelSize: Math.round(Appearance.font.pixelSize.smaller * content.scaleFactor)
                                        color: Appearance.colors.colOnSurfaceVariant
                                        visible: text.length > 0
                                    }
                                }
                            }

                            // Component for task checkbox display
                            Component {
                                id: taskCheckboxComponent
                                Item {
                                    width: 45 * content.scaleFactor
                                    height: 24 * content.scaleFactor

                                    Rectangle {
                                        id: checkbox
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        width: 18 * content.scaleFactor
                                        height: 18 * content.scaleFactor
                                        radius: 4 * content.scaleFactor
                                        color: "transparent"
                                        border.color: Appearance.colors.colSecondary
                                        border.width: 1.5 * content.scaleFactor

                                        Text {
                                            anchors.centerIn: parent
                                            text: eventDelegate.modelData.completed ? "\u2713" : ""
                                            font.pixelSize: Math.round(12 * content.scaleFactor)
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colSecondary
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: content.toggleTask(eventDelegate.modelData.taskId)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Add Task button (bottom right corner)
            Rectangle {
                id: addTaskButton
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12 * content.scaleFactor
                width: 32 * content.scaleFactor
                height: 32 * content.scaleFactor
                radius: width / 2
                color: addTaskMouseArea.containsMouse ? Qt.lighter(Appearance.colors.colSecondary, 1.2) : Appearance.colors.colSecondary

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    font.pixelSize: Math.round(20 * content.scaleFactor)
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSecondary
                }

                MouseArea {
                    id: addTaskMouseArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: Qt.openUrlExternally("https://tasks.google.com")
                }
            }
        }
    }
}
