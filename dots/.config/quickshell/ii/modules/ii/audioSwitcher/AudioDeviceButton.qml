import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button

    property string deviceIcon
    property string deviceName
    property bool isActive: false
    property bool hasEq: false
    property bool keyboardDown: false
    property real size: 120

    buttonRadius: (button.focus || button.down || button.isActive) ? size / 2 : Appearance.rounding.verylarge
    colBackground: button.isActive ? Appearance.colors.colPrimary :
        button.keyboardDown ? Appearance.colors.colSecondaryContainerActive :
        button.focus ? Appearance.colors.colSecondaryContainerActive :
        Appearance.colors.colSecondaryContainer
    colBackgroundHover: button.isActive ? Appearance.colors.colPrimaryActive : Appearance.colors.colPrimary
    colRipple: Appearance.colors.colPrimaryActive
    property color colText: (button.isActive || button.down || button.keyboardDown || button.focus || button.hovered) ?
        Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0

    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
    background.implicitHeight: size
    background.implicitWidth: size

    Behavior on buttonRadius {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            keyboardDown = true;
            button.clicked();
            event.accepted = true;
        }
    }
    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            keyboardDown = false;
            event.accepted = true;
        }
    }

    contentItem: Item {
        anchors.fill: parent

        MaterialSymbol {
            anchors.centerIn: parent
            color: button.colText
            horizontalAlignment: Text.AlignHCenter
            iconSize: 45
            text: button.deviceIcon
        }

        // EQ indicator
        MaterialSymbol {
            visible: button.hasEq
            anchors {
                right: parent.right
                bottom: parent.bottom
                rightMargin: 12
                bottomMargin: 12
            }
            color: button.colText
            horizontalAlignment: Text.AlignHCenter
            iconSize: 16
            text: "graphic_eq"
            opacity: 0.8
        }
    }

    StyledToolTip {
        text: button.deviceName
    }
}
