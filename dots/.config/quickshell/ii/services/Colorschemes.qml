pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string schemesPath: "/home/brunno/.config/quickshell/ii/modules/ii/colorschemeSelector/colorschemes"
    property alias schemes: schemesModel
    property var schemesData: []  // Raw data for lookup
    property string currentScheme: ""
    property var previewScheme: null
    property var originalColors: ({})
    property bool isPreviewActive: false

    signal schemesLoaded()
    signal schemeApplied(string schemeId)
    signal schemePreviewStarted(string schemeId)
    signal schemePreviewCancelled()

    ListModel {
        id: schemesModel
    }

    function load() {
        loadSchemes()
    }

    Component.onCompleted: {
        loadSchemes()
    }

    property var _loadBuffer: []

    function loadSchemes() {
        root._loadBuffer = []
        loadAllProc.running = true
    }

    Process {
        id: loadAllProc
        command: ["bash", "-c", `
            cd "${root.schemesPath}" &&
            for f in *.json; do
                [ "$f" = "index.json" ] && continue
                cat "$f"
                echo "---SCHEME_SEPARATOR---"
            done
        `]
        stdout: SplitParser {
            splitMarker: "---SCHEME_SEPARATOR---"
            onRead: data => {
                if (data.trim().length === 0) return
                try {
                    const scheme = JSON.parse(data.trim())
                    if (scheme.id) {
                        root._loadBuffer.push(scheme)
                    }
                } catch (e) {
                    console.error("[Colorschemes] Failed to parse scheme:", e)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root._loadBuffer.length > 0) {
                schemesModel.clear()
                root.schemesData = root._loadBuffer
                for (let i = 0; i < root._loadBuffer.length; i++) {
                    const s = root._loadBuffer[i]
                    schemesModel.append({
                        schemeId: s.id,
                        schemeName: s.name,
                        darkMode: s.darkMode,
                        colorsJson: JSON.stringify(s.colors)
                    })
                }
                console.log("[Colorschemes] Loaded", schemesModel.count, "schemes into ListModel")
                root.schemesLoaded()
            }
        }
    }

    function getScheme(schemeId) {
        for (let i = 0; i < root.schemesData.length; i++) {
            if (root.schemesData[i].id === schemeId) {
                return root.schemesData[i]
            }
        }
        return null
    }

    function applyScheme(schemeId) {
        const scheme = getScheme(schemeId)
        if (!scheme) {
            console.warn("[Colorschemes] Scheme not found:", schemeId)
            return
        }

        if (root.isPreviewActive) {
            root.isPreviewActive = false
            root.previewScheme = null
            root.originalColors = {}
        }

        applyColorsToAppearance(scheme.colors)
        Appearance.m3colors.darkmode = scheme.darkMode

        root.currentScheme = schemeId
        root.schemeApplied(schemeId)
    }

    function startPreview(schemeId) {
        const scheme = getScheme(schemeId)
        if (!scheme) return

        if (!root.isPreviewActive) {
            saveOriginalColors()
        }

        root.isPreviewActive = true
        root.previewScheme = scheme
        applyColorsToAppearance(scheme.colors)
        Appearance.m3colors.darkmode = scheme.darkMode
        root.schemePreviewStarted(schemeId)
    }

    function cancelPreview() {
        if (!root.isPreviewActive) return

        restoreOriginalColors()
        root.isPreviewActive = false
        root.previewScheme = null
        root.originalColors = {}
        root.schemePreviewCancelled()
    }

    function saveOriginalColors() {
        root.originalColors = {}
        const m3 = Appearance.m3colors
        const colorKeys = [
            "darkmode", "transparent",
            "m3background", "m3onBackground",
            "m3surface", "m3surfaceDim", "m3surfaceBright",
            "m3surfaceContainerLowest", "m3surfaceContainerLow",
            "m3surfaceContainer", "m3surfaceContainerHigh", "m3surfaceContainerHighest",
            "m3onSurface", "m3surfaceVariant", "m3onSurfaceVariant",
            "m3inverseSurface", "m3inverseOnSurface",
            "m3outline", "m3outlineVariant",
            "m3shadow", "m3scrim", "m3surfaceTint",
            "m3primary", "m3onPrimary",
            "m3primaryContainer", "m3onPrimaryContainer",
            "m3inversePrimary",
            "m3secondary", "m3onSecondary",
            "m3secondaryContainer", "m3onSecondaryContainer",
            "m3tertiary", "m3onTertiary",
            "m3tertiaryContainer", "m3onTertiaryContainer",
            "m3error", "m3onError",
            "m3errorContainer", "m3onErrorContainer",
            "m3primaryFixed", "m3primaryFixedDim",
            "m3onPrimaryFixed", "m3onPrimaryFixedVariant",
            "m3secondaryFixed", "m3secondaryFixedDim",
            "m3onSecondaryFixed", "m3onSecondaryFixedVariant",
            "m3tertiaryFixed", "m3tertiaryFixedDim",
            "m3onTertiaryFixed", "m3onTertiaryFixedVariant",
            "m3success", "m3onSuccess",
            "m3successContainer", "m3onSuccessContainer",
            "term0", "term1", "term2", "term3", "term4", "term5", "term6", "term7",
            "term8", "term9", "term10", "term11", "term12", "term13", "term14", "term15"
        ]
        for (const key of colorKeys) {
            if (m3[key] !== undefined) {
                root.originalColors[key] = m3[key]
            }
        }
    }

    function restoreOriginalColors() {
        const m3 = Appearance.m3colors
        for (const key in root.originalColors) {
            if (root.originalColors.hasOwnProperty(key)) {
                m3[key] = root.originalColors[key]
            }
        }
    }

    function applyColorsToAppearance(colors) {
        const m3 = Appearance.m3colors
        for (const key in colors) {
            if (colors.hasOwnProperty(key) && m3[key] !== undefined) {
                m3[key] = colors[key]
            }
        }
    }

    IpcHandler {
        target: "colorschemes"

        function apply(schemeId: string): void {
            root.applyScheme(schemeId)
        }

        function list(): string {
            let result = []
            for (let i = 0; i < schemesModel.count; i++) {
                const s = schemesModel.get(i)
                result.push({ id: s.schemeId, name: s.schemeName, darkMode: s.darkMode })
            }
            return JSON.stringify(result)
        }

        function reload(): void {
            schemesModel.clear()
            root.schemesData = []
            root.loadSchemes()
        }
    }
}
