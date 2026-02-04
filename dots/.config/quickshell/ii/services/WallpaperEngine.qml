import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Service for managing Wallpaper Engine wallpapers from Steam Workshop
 * Provides listing, metadata parsing, and application of WE wallpapers
 */
Singleton {
    id: root

    // Paths
    property string workshopPath: "/mnt/Games/SteamLibrary/steamapps/workshop/content/431960"
    property string assetsPath: "/mnt/Games/SteamLibrary/steamapps/common/wallpaper_engine/assets"
    property string indexScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/wallpaperengine/index-we-wallpapers.sh`
    property string detectScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/wallpaperengine/detect-we-type.sh`
    property string thumbnailScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/wallpaperengine/generate-we-thumbnails.sh`
    property string cacheFile: `${FileUtils.trimFileProtocol(Directories.cache)}/we-wallpapers-index.json`
    property string ignoredFile: `${FileUtils.trimFileProtocol(Directories.cache)}/we-wallpapers-ignored.json`

    // State
    property list<var> weWallpapers: []
    property var ignoredWallpapers: ({})
    property bool isIndexing: false
    property bool isLoaded: false
    property string errorMessage: ""

    signal wallpapersLoaded()
    signal indexingStarted()
    signal indexingCompleted()

    // Ignore list management
    function loadIgnoredList() {
        loadIgnoredProc.exec(["test", "-f", root.ignoredFile])
    }

    function toggleIgnoreWallpaper(workshopId) {
        const newIgnored = Object.assign({}, root.ignoredWallpapers)

        if (newIgnored[workshopId]) {
            delete newIgnored[workshopId]
            console.log(`[WallpaperEngine] Removed ${workshopId} from ignore list`)
        } else {
            newIgnored[workshopId] = true
            console.log(`[WallpaperEngine] Added ${workshopId} to ignore list`)
        }

        root.ignoredWallpapers = newIgnored
        root.saveIgnoredList()
        root.wallpapersLoaded() // Trigger UI update
    }

    function saveIgnoredList() {
        const ignored = Object.keys(root.ignoredWallpapers)
        const json = JSON.stringify({ ignored: ignored }, null, 2)
        saveIgnoredProc.exec(["bash", "-c", `echo '${json}' > '${root.ignoredFile}'`])
    }

    Process {
        id: loadIgnoredProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                readIgnoredProc.exec(["cat", root.ignoredFile])
            } else {
                console.log("[WallpaperEngine] No ignored list found, starting fresh")
                root.ignoredWallpapers = {}
            }
        }
    }

    Process {
        id: readIgnoredProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    const ignoredObj = {}
                    if (data && data.ignored) {
                        data.ignored.forEach(id => {
                            ignoredObj[id] = true
                        })
                    }
                    root.ignoredWallpapers = ignoredObj
                    console.log(`[WallpaperEngine] Loaded ${data.ignored?.length || 0} ignored wallpapers`)
                } catch (e) {
                    console.log("[WallpaperEngine] Failed to parse ignored list:", e)
                    root.ignoredWallpapers = {}
                }
            }
        }
    }

    Process {
        id: saveIgnoredProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                console.log("[WallpaperEngine] Ignored list saved")
            }
        }
    }

    function load() {
        if (isLoaded) return;

        // Check if workshop directory exists
        checkWorkshopProc.exec(["test", "-d", root.workshopPath])
    }

    function forceReindex() {
        root.isLoaded = false;
        root.weWallpapers = [];
        root.indexWallpapers();
    }

    // Check if workshop directory exists
    Process {
        id: checkWorkshopProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.errorMessage = `Workshop directory not found: ${root.workshopPath}`
                console.log("[WallpaperEngine]", root.errorMessage)
                return
            }
            // Directory exists, try to load cache or index
            root.loadCacheOrIndex()
        }
    }

    function loadCacheOrIndex() {
        // Try to load from cache first
        loadCacheProc.exec(["test", "-f", root.cacheFile])
    }

    Process {
        id: loadCacheProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                // Cache exists, load it
                readCacheProc.exec(["cat", root.cacheFile])
            } else {
                // Cache doesn't exist, index wallpapers
                root.indexWallpapers()
            }
        }
    }

    Process {
        id: readCacheProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const cache = JSON.parse(text)
                    root.parseWallpapersFromCache(cache)
                    root.isLoaded = true
                    root.wallpapersLoaded()
                    console.log(`[WallpaperEngine] Loaded ${root.weWallpapers.length} wallpapers from cache`)
                } catch (e) {
                    console.log("[WallpaperEngine] Failed to parse cache, re-indexing:", e)
                    root.indexWallpapers()
                }
            }
        }
    }

    function parseWallpapersFromCache(cache) {
        if (!cache || !cache.wallpapers) {
            return
        }

        root.weWallpapers = cache.wallpapers.map(wp => ({
            workshopId: wp.workshopId || "",
            title: wp.title || "Untitled",
            type: wp.type || "unknown",
            file: wp.file || "",
            preview: wp.preview || "preview.jpg",
            previewPath: wp.previewPath || "",
            workshopPath: wp.workshopPath || "",
            tags: wp.tags || "",
            schemeColor: wp.schemeColor || "",
            // Computed properties
            isWallpaperEngine: true,
            filePath: wp.workshopPath || "",
            fileName: wp.title || "Untitled",
            fileIsDir: true
        }))

        // Generate thumbnails after loading wallpapers
        root.generateThumbnails()
    }

    function indexWallpapers() {
        if (root.isIndexing) {
            console.log("[WallpaperEngine] Indexing already in progress")
            return
        }

        console.log("[WallpaperEngine] Indexing wallpapers...")
        root.isIndexing = true
        root.indexingStarted()

        indexProc.exec([root.indexScriptPath])
    }

    Process {
        id: indexProc
        stdout: StdioCollector {
            onStreamFinished: {
                const cacheFilePath = text.trim()
                console.log(`[WallpaperEngine] Index created at: ${cacheFilePath}`)

                // Now read the cache
                readCacheProc.exec(["cat", root.cacheFile])

                root.isIndexing = false
                root.indexingCompleted()
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.log("[WallpaperEngine] Indexing errors:", text)
                }
            }
        }
    }

    function getWallpaperById(workshopId) {
        for (let i = 0; i < root.weWallpapers.length; i++) {
            if (root.weWallpapers[i].workshopId === workshopId) {
                return root.weWallpapers[i]
            }
        }
        return null
    }

    function getWallpaperMetadata(workshopId) {
        const wp = root.getWallpaperById(workshopId)
        if (!wp) {
            console.log(`[WallpaperEngine] Wallpaper ${workshopId} not found`)
            return {}
        }
        return wp
    }

    // Pick random WE wallpaper (excludes ignored ones)
    function randomWallpaper(darkMode = Appearance.m3colors.darkmode) {
        const visibleWallpapers = root.weWallpapers.filter(wp => !root.ignoredWallpapers[wp.workshopId])
        if (visibleWallpapers.length === 0) return
        const randomIndex = Math.floor(Math.random() * visibleWallpapers.length)
        const wp = visibleWallpapers[randomIndex]
        console.log("[WallpaperEngine] Randomly selected:", wp.title, wp.workshopId)
        Wallpapers.applyWEWallpaper(wp.workshopId, darkMode)
    }

    // Get wallpaper type icon for UI
    function getTypeIcon(type) {
        switch (type) {
            case "scene": return "videogame_asset"
            case "video": return "movie"
            case "web": return "language"
            default: return "image"
        }
    }

    // Get wallpaper type display name
    function getTypeName(type) {
        switch (type) {
            case "scene": return "Scene"
            case "video": return "Video"
            case "web": return "Web"
            default: return "Unknown"
        }
    }

    // Check if linux-wallpaperengine is installed
    function checkWallpaperEngineInstalled() {
        checkInstalledProc.exec(["which", "linux-wallpaperengine"])
    }

    Process {
        id: checkInstalledProc
        property bool installed: false
        onExited: (exitCode, exitStatus) => {
            checkInstalledProc.installed = (exitCode === 0)
            if (!checkInstalledProc.installed) {
                root.errorMessage = "linux-wallpaperengine not found. Please install it."
                console.log("[WallpaperEngine]", root.errorMessage)
            }
        }
    }

    // Generate thumbnails for all WE wallpapers
    function generateThumbnails() {
        console.log("[WallpaperEngine] Generating thumbnails...")
        thumbnailProc.exec([
            root.thumbnailScriptPath,
            "--size", "large"
        ])
    }

    Process {
        id: thumbnailProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                console.log("[WallpaperEngine] Thumbnails generated successfully")
            } else {
                console.log("[WallpaperEngine] Thumbnail generation failed with exit code:", exitCode)
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.log("[WallpaperEngine] Thumbnail generation:", text)
                }
            }
        }
    }

    Component.onCompleted: {
        // Check if linux-wallpaperengine is installed
        checkWallpaperEngineInstalled()

        // Load ignored wallpapers list
        loadIgnoredList()

        // Delay load slightly to not block startup
        loadTimer.start()
    }

    Timer {
        id: loadTimer
        interval: 500
        repeat: false
        onTriggered: root.load()
    }
}
