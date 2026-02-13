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
    readonly property string scriptsPath: "/home/brunno/.config/quickshell/ii/scripts/themes"
    readonly property string colorsScriptsPath: "/home/brunno/.config/quickshell/ii/scripts/colors"
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
    property var _pendingScheme: null

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
                        colorsJson: JSON.stringify(s.colors),
                        themeJson: s.theme ? JSON.stringify(s.theme) : ""
                    })
                }
                console.log("[Colorschemes] Loaded", schemesModel.count, "schemes into ListModel")
                root.schemesLoaded()
            }
        }
    }

    Process {
        id: applyThemeProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("[Colorschemes] apply-system-theme.sh exited with code", exitCode)
            }
        }
    }

    Process {
        id: writeSchemeScssProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("[Colorschemes] write-scheme-scss.sh exited with code", exitCode)
            }
            // SCSS is written, now apply system theme (MaterialAdw will read correct colors)
            if (root._pendingScheme) {
                root.applySystemTheme(root._pendingScheme)
                root._pendingScheme = null
            }
        }
    }

    Process {
        id: applyTermColorsProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("[Colorschemes] apply-term-colors.sh exited with code", exitCode)
            }
        }
    }

    Process {
        id: setGnomeAccentProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("[Colorschemes] set_gnome_accent.py exited with code", exitCode)
            }
        }
    }

    function applySystemTheme(scheme) {
        if (!scheme || !scheme.theme) return

        const t = scheme.theme
        const args = [
            "bash", root.scriptsPath + "/apply-system-theme.sh",
            "--gtk-theme", t.gtkTheme || "",
            "--kvantum-theme", t.kvantumTheme || "",
            "--icon-theme", t.iconTheme || "",
            "--papirus-color", t.papirusFolderColor || "",
            "--color-scheme", t.colorScheme || "",
            "--scheme-id", scheme.id || ""
        ]
        applyThemeProc.command = args
        applyThemeProc.running = true
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

        // 1. Write SCSS first, then applySystemTheme on completion (sequential)
        const colorsJson = JSON.stringify(scheme.colors)
        const dm = scheme.darkMode ? "true" : "false"
        root._pendingScheme = scheme
        writeSchemeScssProc.command = [
            "bash", "-c",
            "printf '%s' \"$1\" | " + root.colorsScriptsPath + "/write-scheme-scss.sh --darkmode " + dm,
            "_", colorsJson
        ]
        writeSchemeScssProc.running = true

        // 2. Apply terminal colors (parallel, independent)
        const c = scheme.colors
        applyTermColorsProc.command = [
            "bash", root.colorsScriptsPath + "/apply-term-colors.sh",
            "--term0", c.term0 || "", "--term1", c.term1 || "",
            "--term2", c.term2 || "", "--term3", c.term3 || "",
            "--term4", c.term4 || "", "--term5", c.term5 || "",
            "--term6", c.term6 || "", "--term7", c.term7 || "",
            "--term8", c.term8 || "", "--term9", c.term9 || "",
            "--term10", c.term10 || "", "--term11", c.term11 || "",
            "--term12", c.term12 || "", "--term13", c.term13 || "",
            "--term14", c.term14 || "", "--term15", c.term15 || "",
            "--bg", c.m3background || "", "--fg", c.m3onBackground || "",
            "--selBg", c.m3surfaceVariant || ""
        ]
        applyTermColorsProc.running = true

        // 3. Set GNOME accent color (parallel, independent)
        if (c.m3primary) {
            setGnomeAccentProc.command = [
                "python3", root.colorsScriptsPath + "/set_gnome_accent.py",
                "--color", c.m3primary
            ]
            setGnomeAccentProc.running = true
        }

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
