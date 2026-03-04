pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects

Item {
    id: root

    required property string source
    required property int imageWidth
    required property int imageHeight

    clip: true

    readonly property int cols: Math.ceil(width / imageWidth)
    readonly property int rows: Math.ceil(height / imageHeight)

    // Warhol Pop Art hue values (0.0-1.0 = 0-360 degrees)
    readonly property var hues: [0.833, 0.472, 0.111, 0.750]         // Magenta, Cyan, Amber, Violet
    readonly property var lightnesses: [-0.15, -0.05, 0.0, -0.2]     // Varied depth per palette

    Grid {
        columns: root.cols

        Repeater {
            model: root.cols * root.rows

            Item {
                required property int index

                width: root.imageWidth
                height: root.imageHeight

                readonly property int col: index % root.cols
                readonly property int row: Math.floor(index / root.cols)
                readonly property int effectIndex: (col + row) % 4

                Image {
                    id: tileSource
                    anchors.fill: parent
                    source: root.source
                    visible: false
                    cache: true
                    asynchronous: true
                }

                BrightnessContrast {
                    id: posterized
                    anchors.fill: parent
                    source: tileSource
                    brightness: -0.15
                    contrast: 0.35
                    visible: false
                }

                Colorize {
                    anchors.fill: parent
                    source: posterized
                    hue: root.hues[effectIndex]
                    saturation: 1.0
                    lightness: root.lightnesses[effectIndex]
                }
            }
        }
    }
}
