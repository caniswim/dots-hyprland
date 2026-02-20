import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas

Item {
    id: root
    focus: true
    readonly property bool usePasswordChars: !PolkitService.flow?.responseVisible ?? true

    Keys.onPressed: (event) => { // Esc to close
        if (event.key === Qt.Key_Escape) {
            GlobalStates.overlayOpen = false;
        }
    }

    property real initScale: Config.options.overlay.openingZoomAnimation ? 1.08 : 1.000001
    scale: initScale
    Component.onCompleted: {
        scale = 1
    }
    Behavior on scale {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Appearance.colors.colScrim
        visible: Config.options.overlay.darkenScreen && opacity > 0
        opacity: (GlobalStates.overlayOpen && root.scale !== initScale) ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    WidgetCanvas {
        property int _borderInset: (Config.options.appearance.screenBorder?.enable ?? false) ? (Config.options.appearance.screenBorder?.thickness ?? 3) : 0
        property int _barSize: Config.options.bar.vertical ? Appearance.sizes.baseVerticalBarWidth : Appearance.sizes.baseBarHeight

        anchors.fill: parent
        anchors.topMargin: ((!Config.options.bar.vertical && !Config.options.bar.bottom) ? _barSize : _borderInset) + _borderInset
        anchors.bottomMargin: ((!Config.options.bar.vertical && Config.options.bar.bottom) ? _barSize : _borderInset) + _borderInset
        anchors.leftMargin: ((Config.options.bar.vertical && !Config.options.bar.bottom) ? _barSize : _borderInset) + _borderInset
        anchors.rightMargin: ((Config.options.bar.vertical && Config.options.bar.bottom) ? _barSize : _borderInset) + _borderInset
        onClicked: GlobalStates.overlayOpen = false

        OverlayTaskbar {
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
                topMargin: 50
            }
        }

        Repeater {
            model: ScriptModel {
                values: Persistent.states.overlay.open.map(identifier => {
                    return OverlayContext.availableWidgets.find(w => w.identifier === identifier);
                })
                objectProp: "identifier"
            }
            delegate: OverlayWidgetDelegateChooser {
                
            }
        }
    }
}
