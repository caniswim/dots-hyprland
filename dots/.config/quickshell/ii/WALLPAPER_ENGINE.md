# Wallpaper Engine Integration

Este documento descreve como a integração do Wallpaper Engine funciona no Quickshell.

## Visão Geral

O sistema permite usar wallpapers do Steam Workshop (Wallpaper Engine) como wallpapers do sistema, com suporte completo a:
- Wallpapers interativos (scene)
- Wallpapers de vídeo
- Wallpapers web
- Extração automática de cores Material You
- Sincronização de temas (terminal, Qt apps, VSCode)

## Arquitetura

### Componentes Principais

```
ii/
├── services/
│   ├── WallpaperEngine.qml        # Singleton que gerencia wallpapers do WE
│   └── Wallpapers.qml              # Singleton de wallpapers (delega WE para apply)
├── modules/ii/wallpaperSelector/
│   ├── WallpaperSelectorContent.qml    # UI do seletor (botão "Workshop")
│   └── WallpaperDirectoryItem.qml      # Item individual (preview + badge de tipo)
└── scripts/
    ├── colors/
    │   └── switchwall.sh           # Detecta e delega wallpapers WE
    └── wallpaperengine/
        ├── apply-we-wallpaper.sh           # Script principal de aplicação
        ├── detect-we-type.sh               # Detecta tipo e extrai metadados
        ├── index-we-wallpapers.sh          # Indexa todos os wallpapers
        ├── generate-we-thumbnails.sh       # Gera thumbnails
        └── cleanup-we-processes.sh         # Limpa processos antigos
```

## Fluxo de Funcionamento

### 1. Inicialização (Startup)

```qml
// shell.qml linha 52
WallpaperEngine.load()  // Carrega cache de wallpapers
```

**Processo:**
1. `WallpaperEngine.load()` verifica se workshop directory existe
2. Tenta carregar cache (`~/.cache/quickshell/we-wallpapers-index.json`)
3. Se cache não existe, executa `index-we-wallpapers.sh` em background
4. Parse do JSON e população de `weWallpapers` array

### 2. Seleção no UI

```qml
// WallpaperSelectorContent.qml
onClicked: {
    if (quickDirButton.modelData.isWE) {
        root.showingWEWallpapers = true
        WallpaperEngine.load()  // Garante que está carregado
    }
}
```

**UI:**
- Sidebar exibe botão "Workshop" (ícone: `videogame_asset`)
- Ao clicar, GridView muda de `Wallpapers.folderModel` → `WallpaperEngine.weWallpapers`
- Cada item exibe:
  - Thumbnail (`preview.jpg` do wallpaper)
  - Badge com tipo (🎮 scene, 🎬 video, 🌐 web)
  - Título do wallpaper (do `project.json`)

### 3. Aplicação do Wallpaper

```qml
// Wallpapers.qml
function applyWEWallpaper(workshopId, darkMode) {
    weApplyProc.exec([
        Directories.weWallpaperScriptPath,  // apply-we-wallpaper.sh
        "--id", workshopId,
        "--mode", (darkMode ? "dark" : "light")
    ])
}
```

**Script `apply-we-wallpaper.sh` executa:**

```bash
1. Cleanup de processos anteriores
   └─ cleanup-we-processes.sh (pkill mpvpaper, linux-wallpaperengine)

2. Detecção de metadados
   └─ detect-we-type.sh → JSON com {type, title, preview, ...}

3. Aplicação do wallpaper
   └─ linux-wallpaperengine --screen-root DP-1 --screen-root HDMI-A-1 \
        --assets-dir /path/to/assets --fps 30 --silent /path/to/wallpaper/

4. Atualização do config
   └─ config.json: background.wallpaperEngine.isActive = true

5. Geração de cores (se --no-color-gen não foi passado)
   ├─ pre_process()           # GNOME theme (dark/light)
   ├─ matugen image preview.jpg --mode dark --type scheme-tonal-spot
   │  └─ Gera: ~/.local/state/quickshell/user/generated/colors.json
   ├─ generate_colors_material.py --path preview.jpg ...
   │  └─ Gera: material_colors.scss (cores do terminal)
   ├─ applycolor.sh           # Aplica cores ao terminal
   └─ post_process()          # KDE Material You + VSCode colors

6. Script de restauração
   └─ Cria __restore_we_wallpaper.sh (para reboot)
```

### 4. Atualização de Cores no Quickshell

```qml
// MaterialThemeLoader.qml
FileView {
    path: "~/.local/state/quickshell/user/generated/colors.json"
    watchChanges: true  // 👈 Monitora mudanças no arquivo!
    onFileChanged: {
        this.reload()
        delayedFileRead.start()  // Aplica cores após 100ms
    }
}
```

**Quando `matugen` gera o `colors.json`, o Quickshell:**
1. Detecta mudança via `watchChanges`
2. Recarrega o arquivo
3. Parseia o JSON
4. Atualiza `Appearance.m3colors.*`
5. UI atualiza automaticamente (bindings reativos)

## Estrutura de Dados

### Wallpaper Object (QML)

```javascript
{
    workshopId: "1696086154",
    title: "Watching the Universe - Deep Red",
    type: "scene",  // ou "video", "web"
    file: "scene.json",
    preview: "preview.jpg",
    previewPath: "/mnt/Games/.../1696086154/preview.jpg",
    workshopPath: "/mnt/Games/.../1696086154",
    tags: "Relaxing",
    schemeColor: "0 0 0",

    // Computed properties (para compatibilidade com FolderListModel)
    isWallpaperEngine: true,
    filePath: "/mnt/Games/.../1696086154",
    fileName: "Watching the Universe - Deep Red",
    fileIsDir: true
}
```

### Cache Index (`we-wallpapers-index.json`)

```json
{
    "version": "1.0",
    "timestamp": "2024-11-20T21:00:00Z",
    "wallpapers": [
        {
            "workshopId": "1696086154",
            "type": "scene",
            "title": "Watching the Universe - Deep Red",
            "file": "scene.json",
            "preview": "preview.jpg",
            "previewPath": "/mnt/Games/.../preview.jpg",
            "workshopPath": "/mnt/Games/.../1696086154",
            "tags": "Relaxing",
            "schemeColor": "0 0 0"
        }
    ]
}
```

## Detecção de Wallpaper Engine

O sistema detecta wallpapers do WE de duas formas:

### 1. Via Seletor (UI)
Usuário clica em "Workshop" → `showingWEWallpapers = true`

### 2. Via Path (Automático)

```bash
# switchwall.sh
is_we_wallpaper() {
    local path="$1"
    # Formato: WE:1696086154
    [[ "$path" =~ ^WE:[0-9]+$ ]] && return 0
    # Formato: 1696086154 (apenas ID)
    [[ "$path" =~ ^[0-9]{9,10}$ ]] && return 0
    return 1
}
```

Se detectado, delega para `apply-we-wallpaper.sh`.

## Geração de Thumbnails

### Freedesktop Thumbnail Specification

Thumbnails seguem a spec XDG:

```bash
# URI do arquivo
file:///mnt/Games/.../1696086154/preview.jpg

# MD5 do URI
hash=$(echo -n "$uri" | md5sum | cut -d' ' -f1)

# Path do thumbnail
~/.cache/thumbnails/large/${hash}.png
~/.cache/thumbnails/normal/${hash}.png
```

### Script `generate-we-thumbnails.sh`

```bash
for wallpaper in $WORKSHOP_BASE/*/; do
    preview="$wallpaper/preview.jpg"
    uri="file://$(realpath "$preview")"
    hash=$(md5_hash "$uri")

    # Gera thumbnail 256x256
    magick "$preview" -resize 256x256 \
        "$CACHE_DIR/thumbnails/large/${hash}.png"
done
```

## Gerenciamento de Processos

### Problema: Empilhamento
Cada wallpaper inicia um processo `linux-wallpaperengine`. Sem cleanup, processos se acumulam.

### Solução: `cleanup-we-processes.sh`

```bash
# Mata todos os processos antes de aplicar novo wallpaper
pkill -f -9 mpvpaper 2>/dev/null || true
pkill -f -9 linux-wallpaperengine 2>/dev/null || true
sleep 0.3  # Aguarda cleanup
```

## Integração com Sistema Existente

### Paridade com Wallpapers Estáticos

O `apply-we-wallpaper.sh` **segue exatamente o mesmo padrão** do `switchwall.sh`:

| Etapa | switchwall.sh | apply-we-wallpaper.sh |
|-------|---------------|----------------------|
| Pre-process | ✅ GNOME theme | ✅ GNOME theme |
| Matugen | ✅ Gera colors.json | ✅ Gera colors.json |
| Python | ✅ material_colors.scss | ✅ material_colors.scss |
| Apply terminal | ✅ applycolor.sh | ✅ applycolor.sh |
| Post-process | ✅ KDE + VSCode | ✅ KDE + VSCode |

### Diferenças

```bash
# switchwall.sh
hyprctl hyprpaper wallpaper "$monitor,$imgpath"  # Wallpaper estático

# apply-we-wallpaper.sh
linux-wallpaperengine --screen-root $monitor "$WORKSHOP_PATH"  # WE dinâmico
```

## Configuração

### Paths (Directories.qml)

```qml
property string weWallpaperScriptPath:
    FileUtils.trimFileProtocol(`${scriptPath}/wallpaperengine/apply-we-wallpaper.sh`)

property string weWorkshopPath:
    "/mnt/Games/SteamLibrary/steamapps/workshop/content/431960"

property string weThumbnailCache:
    FileUtils.trimFileProtocol(`${cache}/media/we-wallpapers`)
```

### Config.json

```json
{
    "background": {
        "wallpaperEngine": {
            "isActive": true,
            "workshopId": "1696086154",
            "type": "scene"
        },
        "wallpaperPath": "WE:1696086154",
        "thumbnailPath": "/home/user/.cache/quickshell/media/we-wallpapers/1696086154.jpg"
    }
}
```

## Restauração após Reboot

### Script Gerado: `__restore_we_wallpaper.sh`

```bash
#!/bin/bash
# Lê config.json
IS_ACTIVE=$(jq -r '.background.wallpaperEngine.isActive' "$CONFIG_FILE")
WORKSHOP_ID=$(jq -r '.background.wallpaperEngine.workshopId' "$CONFIG_FILE")

# Se WE estava ativo, restaura
if [ "$IS_ACTIVE" = "true" ]; then
    linux-wallpaperengine --screen-root DP-1 --screen-root HDMI-A-1 \
        --assets-dir "$ASSETS_DIR" "$WORKSHOP_PATH" &
fi
```

### Integração com Hyprland

```bash
# hyprland.conf
exec-once = ~/.config/hypr/custom/scripts/__restore_we_wallpaper.sh
```

## Dependências

### Obrigatórias

- **linux-wallpaperengine** - Renderiza wallpapers do WE
  ```bash
  # Arch Linux
  yay -S linux-wallpaperengine
  ```

- **matugen** - Gera paleta Material You
  ```bash
  cargo install matugen
  ```

- **jq** - Parser JSON
  ```bash
  sudo pacman -S jq
  ```

### Opcionais

- **ImageMagick** - Geração de thumbnails
  ```bash
  sudo pacman -S imagemagick
  ```

- **ffmpeg** - Extração de frames (wallpapers de vídeo)
  ```bash
  sudo pacman -S ffmpeg
  ```

## Troubleshooting

### Cores não atualizam

**Problema:** Quickshell não detecta mudanças em `colors.json`

**Solução:**
```bash
# Verificar se matugen está gerando o arquivo
ls -lh ~/.local/state/quickshell/user/generated/colors.json

# Verificar timestamp (deve ser recente)
stat ~/.local/state/quickshell/user/generated/colors.json

# Recarregar Quickshell manualmente
qs -c ii
```

### Wallpaper não aparece

**Problema:** `linux-wallpaperengine` não está rodando

**Solução:**
```bash
# Verificar se processo está ativo
ps aux | grep linux-wallpaperengine

# Verificar logs
journalctl -f | grep wallpaperengine

# Testar manualmente
linux-wallpaperengine --screen-root DP-1 \
    --assets-dir /mnt/Games/.../assets \
    /mnt/Games/.../1696086154
```

### Processos empilhados

**Problema:** Múltiplos processos `linux-wallpaperengine` rodando

**Solução:**
```bash
# Matar todos os processos
pkill -f linux-wallpaperengine

# Verificar cleanup no script
bash -x ~/.config/quickshell/ii/scripts/wallpaperengine/cleanup-we-processes.sh
```

### Workshop directory não encontrado

**Problema:** Path do Steam incorreto

**Solução:**
```bash
# Verificar path do Steam
find ~ -name "431960" 2>/dev/null

# Atualizar em apply-we-wallpaper.sh
WORKSHOP_BASE="/seu/path/steamapps/workshop/content/431960"
```

## Desenvolvimento

### Adicionar novo tipo de wallpaper

1. **Adicionar detecção** em `detect-we-type.sh`:
```bash
elif [ -f "$WORKSHOP_PATH/new_type.json" ]; then
    TYPE="new_type"
    FILE="new_type.json"
```

2. **Adicionar ícone** em `WallpaperEngine.qml`:
```qml
function getTypeIcon(type) {
    switch (type) {
        case "new_type": return "new_icon"
        // ...
    }
}
```

3. **Atualizar aplicação** em `apply-we-wallpaper.sh` se necessário.

### Melhorias Futuras

- [ ] Suporte a múltiplos monitores com wallpapers diferentes
- [ ] Preview animado no seletor (GIF/video)
- [ ] Filtro por tipo (scene/video/web)
- [ ] Busca por tags/título
- [ ] Configuração de FPS por wallpaper
- [ ] Auto-download de wallpapers do Workshop

## Referências

- [Wallpaper Engine Workshop](https://steamcommunity.com/app/431960/workshop/)
- [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine)
- [Material You Color System](https://m3.material.io/styles/color/overview)
- [Freedesktop Thumbnail Spec](https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html)
- [Matugen](https://github.com/InioX/matugen)
