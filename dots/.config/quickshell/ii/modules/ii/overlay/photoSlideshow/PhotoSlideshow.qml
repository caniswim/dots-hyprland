pragma ComponentBehavior: Bound
import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.overlay

Item {
    id: root

    // Dados do modelo (requerido pelo delegate chooser)
    required property var modelData
    readonly property string identifier: modelData.identifier

    // Estado persistente
    readonly property var persistentState: Persistent.states.overlay.photoSlideshow
    readonly property bool isPinned: persistentState.pinned

    // Configurações
    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/quickshell/icloud-photos"
    readonly property int intervalMs: Config.options.overlay.photoSlideshow.intervalSeconds * 1000
    readonly property int transitionMs: Config.options.overlay.photoSlideshow.transitionDurationMs
    readonly property real widgetOpacity: Config.options.overlay.photoSlideshow.opacity

    // Estado do slideshow
    property var imageFiles: []
    property int imageCount: 0  // Propriedade reativa para o contador
    property int currentIndex: 0
    property bool showA: true
    property string sourceA: ""  // Source fixa para imagem A
    property string sourceB: ""  // Source fixa para imagem B
    property var recentHistory: []  // Histórico de índices recentes (evita repetição)
    property int historySize: 0     // Tamanho do histórico (50% das fotos)

    // Metadados das fotos (data, cidade)
    property var photoMetadata: ({})
    property string currentPhotoDate: ""
    property string currentPhotoCity: ""

    // Atualiza metadados quando muda a foto
    onCurrentIndexChanged: updateCurrentMetadata()
    onImageFilesChanged: updateCurrentMetadata()

    function updateCurrentMetadata() {
        if (imageFiles.length === 0) {
            currentPhotoDate = ""
            currentPhotoCity = ""
            return
        }
        const filepath = imageFiles[currentIndex]
        const filename = filepath.split('/').pop()
        const meta = photoMetadata[filename] || {}
        currentPhotoDate = meta.date_formatted || ""
        currentPhotoCity = meta.city || ""
    }

    // Registra/desregistra o widget pinned
    onIsPinnedChanged: {
        OverlayContext.pin(identifier, isPinned)
    }
    Component.onCompleted: {
        scanFolder()
        loadMetadata()
        if (isPinned) OverlayContext.pin(identifier, true)
    }
    Component.onDestruction: {
        OverlayContext.pin(identifier, false)
    }

    // Timer para re-escanear pasta
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.scanFolder()
    }

    // Timer para limpeza periódica de memória (a cada 10 minutos)
    Timer {
        interval: 600000
        running: true
        repeat: true
        onTriggered: {
            // Força garbage collection para liberar memória não utilizada
            gc()
        }
    }

    // Timer para trocar imagens
    Timer {
        id: slideshowTimer
        interval: root.intervalMs
        running: root.imageCount > 1
        repeat: true
        onTriggered: root.randomImage()
    }

    // Process para listar arquivos
    Process {
        id: fileScanner
        property var buffer: []

        command: ["bash", "-c",
            `find "${root.cacheDir}" -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.heic" \\) 2>/dev/null`
        ]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                if (trimmed.length > 0) {
                    fileScanner.buffer.push(trimmed)
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            let files = fileScanner.buffer
            fileScanner.buffer = []

            if (files.length > 0) {
                const isFirstLoad = root.imageCount === 0

                if (isFirstLoad) {
                    // Primeiro carregamento: embaralha e começa em posição aleatória
                    if (Config.options.overlay.photoSlideshow.shuffle) {
                        files = root.shuffleArray(files)
                    }
                    root.imageFiles = files
                    root.imageCount = files.length
                    root.historySize = Math.floor(files.length * 0.5)  // Histórico = 50% das fotos
                    root.currentIndex = Math.floor(Math.random() * files.length)
                    root.recentHistory = [root.currentIndex]
                    root.initializeFirstImage()
                    console.log("PhotoSlideshow: Carregadas", files.length, "fotos, histórico:", root.historySize)
                } else {
                    // Rescan: apenas atualiza lista se houver novas fotos
                    if (files.length !== root.imageCount) {
                        // Mantém ordem atual, adiciona novas no final
                        const currentFile = root.imageFiles[root.currentIndex]
                        root.imageFiles = files
                        root.imageCount = files.length
                        root.historySize = Math.floor(files.length * 0.5)
                        // Tenta manter a foto atual
                        const newIdx = files.indexOf(currentFile)
                        if (newIdx >= 0) root.currentIndex = newIdx
                        console.log("PhotoSlideshow: Atualizado para", files.length, "fotos")
                    }
                }
            }
        }
    }

    // Process para carregar metadados
    Process {
        id: metadataLoader
        property string buffer: ""

        command: ["cat", root.cacheDir + "/metadata.json"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                metadataLoader.buffer += data + "\n"
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && metadataLoader.buffer.length > 0) {
                try {
                    root.photoMetadata = JSON.parse(metadataLoader.buffer)
                    root.updateCurrentMetadata()
                    console.log("PhotoSlideshow: Metadados carregados")
                } catch (e) {
                    console.log("Erro ao carregar metadata.json:", e)
                }
            }
            metadataLoader.buffer = ""
        }
    }

    function scanFolder() {
        fileScanner.running = true
    }

    function loadMetadata() {
        metadataLoader.running = true
    }

    function shuffleArray(array) {
        const arr = [...array]
        for (let i = arr.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [arr[i], arr[j]] = [arr[j], arr[i]];
        }
        return arr;
    }

    function nextImage() {
        if (imageCount === 0) return
        goToImage((currentIndex + 1) % imageCount)
    }

    function randomImage() {
        if (imageCount <= 1) return

        // Encontra índice que não está no histórico recente
        let attempts = 0
        let newIndex
        do {
            newIndex = Math.floor(Math.random() * imageCount)
            attempts++
        } while (recentHistory.includes(newIndex) && attempts < 20)

        goToImage(newIndex)
    }

    // Timer para limpar imagem oculta após transição (libera memória)
    Timer {
        id: cleanupTimer
        interval: root.transitionMs + 100  // Aguarda transição completar
        running: false
        repeat: false
        onTriggered: {
            // Limpa a source da imagem que ficou oculta
            if (root.showA) {
                root.sourceB = ""  // B está oculta, limpa
            } else {
                root.sourceA = ""  // A está oculta, limpa
            }
            // Força garbage collection
            gc()
        }
    }

    function goToImage(index: int) {
        if (imageCount === 0) return

        currentIndex = index
        const newSource = "file://" + imageFiles[index]

        // Define o source na imagem OCULTA antes de fazer a transição
        if (showA) {
            sourceB = newSource  // B está oculta, prepara ela
        } else {
            sourceA = newSource  // A está oculta, prepara ela
        }

        // Inicia a transição
        showA = !showA

        // Agenda limpeza da imagem oculta após transição
        cleanupTimer.restart()

        // Adiciona ao histórico
        recentHistory.push(index)
        while (recentHistory.length > historySize) {
            recentHistory.shift()
        }
    }

    function initializeFirstImage() {
        if (imageCount === 0) return
        sourceA = "file://" + imageFiles[currentIndex]
        sourceB = sourceA  // Inicialmente ambas com a mesma imagem
    }

    function getImageSource(offset: int): string {
        if (imageFiles.length === 0) return ""
        const idx = (currentIndex + offset) % imageFiles.length
        return "file://" + imageFiles[idx]
    }

    function togglePinned() {
        persistentState.pinned = !persistentState.pinned
    }

    function close() {
        Persistent.states.overlay.open = Persistent.states.overlay.open.filter(type => type !== root.identifier)
    }

    function openInViewer() {
        if (imageFiles.length === 0) return
        const filepath = imageFiles[currentIndex]
        imageViewerProcess.command = ["xdg-open", filepath]
        imageViewerProcess.running = true
    }

    // Process para abrir imagem no visualizador do sistema
    Process {
        id: imageViewerProcess
        running: false
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
        opacity: root.widgetOpacity
        title: "Photo Slideshow"

        contentItem: SlideshowContent {
            imageCount: root.imageCount
            currentIndex: root.currentIndex
            showA: root.showA
            transitionMs: root.transitionMs
            // Só carrega imagens quando overlay está visível (economiza memória)
            sourceA: GlobalStates.overlayOpen ? root.sourceA : ""
            sourceB: GlobalStates.overlayOpen ? root.sourceB : ""
            showCounter: true
            photoDate: root.currentPhotoDate
            photoCity: root.currentPhotoCity
        }
    }

    // ==========================================
    // JANELA BACKGROUND (quando pinned e overlay fechado)
    // ==========================================
    PanelWindow {
        id: backgroundWindow
        visible: root.isPinned && !GlobalStates.overlayOpen
        color: "transparent"

        // Layer Bottom = acima do wallpaper engine, abaixo das janelas
        WlrLayershell.namespace: "quickshell:slideshow"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        // Posição e tamanho do estado persistente
        anchors {
            top: true
            left: true
        }

        width: Math.max(400, root.persistentState.width + 20)
        height: Math.max(300, root.persistentState.height + 20)

        // Margem para posicionar
        margins {
            top: root.persistentState.y
            left: root.persistentState.x
        }

        // Conteúdo do slideshow
        Item {
            anchors.fill: parent
            anchors.margins: 10

            SlideshowContent {
                anchors.fill: parent
                imageCount: root.imageCount
                currentIndex: root.currentIndex
                showA: root.showA
                transitionMs: root.transitionMs
                // Só carrega imagens quando background window está visível
                sourceA: backgroundWindow.visible ? root.sourceA : ""
                sourceB: backgroundWindow.visible ? root.sourceB : ""
                showCounter: false
                radius: Appearance.rounding.windowRounding
                photoDate: root.currentPhotoDate
                photoCity: root.currentPhotoCity
            }

            // Clique para trocar foto (escolhe aleatória não-recente)
            // Clique direito abre a foto no visualizador do sistema
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        root.openInViewer()
                    } else {
                        root.randomImage()
                    }
                }
                cursorShape: Qt.PointingHandCursor
            }
        }
    }

    // ==========================================
    // COMPONENTE DE CONTEÚDO REUTILIZÁVEL
    // ==========================================
    component SlideshowContent: Item {
        id: content
        property int imageCount: 0
        property int currentIndex: 0
        property bool showA: true
        property int transitionMs: 800
        property string sourceA: ""
        property string sourceB: ""
        property bool showCounter: false
        property real radius: Appearance.rounding.windowRounding - 6
        property string photoDate: ""
        property string photoCity: ""

        Rectangle {
            id: bg
            anchors.fill: parent
            color: "#1a1a1a"
            radius: content.radius
            clip: true

            // Layer só ativo quando visível (economiza memória GPU)
            layer.enabled: content.visible && content.imageCount > 0
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: bg.width
                    height: bg.height
                    radius: bg.radius
                }
            }

            // Placeholder
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colSurfaceContainer
                visible: content.imageCount === 0
                radius: bg.radius

                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    MaterialSymbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "cloud_sync"
                        iconSize: 48
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Sincronizando fotos..."
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }

            // Imagem A (source fixa, não muda durante transição)
            Image {
                id: imageA
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                source: content.sourceA
                opacity: content.showA ? 1 : 0
                visible: content.imageCount > 0
                // Limita tamanho da textura na memória (previne leak)
                sourceSize.width: parent.width * 2
                sourceSize.height: parent.height * 2

                Behavior on opacity {
                    NumberAnimation {
                        duration: content.transitionMs
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            // Imagem B (source fixa, não muda durante transição)
            Image {
                id: imageB
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                source: content.sourceB
                opacity: content.showA ? 0 : 1
                visible: content.imageCount > 0
                // Limita tamanho da textura na memória (previne leak)
                sourceSize.width: parent.width * 2
                sourceSize.height: parent.height * 2

                Behavior on opacity {
                    NumberAnimation {
                        duration: content.transitionMs
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            // Gradiente inferior (estilo Apple)
            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: 100
                visible: content.imageCount > 0 && (content.photoDate.length > 0 || content.photoCity.length > 0)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.4; color: Qt.rgba(0, 0, 0, 0.15) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.65) }
                }
            }

            // Container de informações (estilo Apple)
            Column {
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                    leftMargin: 16
                    bottomMargin: 12
                }
                spacing: 2
                visible: content.imageCount > 0 && (content.photoDate.length > 0 || content.photoCity.length > 0)

                // Data
                Text {
                    text: content.photoDate
                    color: "white"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.5)
                    visible: content.photoDate.length > 0

                    Behavior on text {
                        SequentialAnimation {
                            NumberAnimation { target: parent; property: "opacity"; to: 0; duration: content.transitionMs / 2 }
                            PropertyAction { }
                            NumberAnimation { target: parent; property: "opacity"; to: 1; duration: content.transitionMs / 2 }
                        }
                    }
                }

                // Cidade
                Text {
                    text: content.photoCity
                    color: Qt.rgba(1, 1, 1, 0.8)
                    font.pixelSize: 14
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.5)
                    visible: content.photoCity.length > 0

                    Behavior on text {
                        SequentialAnimation {
                            NumberAnimation { target: parent; property: "opacity"; to: 0; duration: content.transitionMs / 2 }
                            PropertyAction { }
                            NumberAnimation { target: parent; property: "opacity"; to: 1; duration: content.transitionMs / 2 }
                        }
                    }
                }
            }

            // Contador
            Rectangle {
                anchors {
                    bottom: parent.bottom
                    right: parent.right
                    margins: 8
                }
                width: counterText.implicitWidth + 16
                height: counterText.implicitHeight + 8
                radius: height / 2
                color: ColorUtils.transparentize(Appearance.colors.colScrim, 0.3)
                visible: content.imageCount > 0 && content.showCounter

                StyledText {
                    id: counterText
                    anchors.centerIn: parent
                    text: `${content.currentIndex + 1}/${content.imageCount}`
                    font.pixelSize: 12
                    color: "white"
                }
            }
        }
    }
}
