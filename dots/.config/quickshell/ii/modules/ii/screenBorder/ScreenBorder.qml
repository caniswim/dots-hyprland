pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common

Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: borderWindow

        required property var modelData

        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        property bool fullscreen: activeWorkspaceWithFullscreen != undefined

        visible: (Config.options.appearance.screenBorder?.enable ?? false) && !fullscreen

        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:screenBorder"
        WlrLayershell.layer: WlrLayer.Top
        color: "transparent"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Empty mask = fully click-through
        mask: Region {}

        // Border config
        property int borderThickness: Config.options.appearance.screenBorder?.thickness ?? 3
        property int borderRounding: Config.options.appearance.screenBorder?.rounding ?? Appearance.rounding.screenRounding
        property color borderColor: Config.options.appearance.screenBorder?.useOutlineColor
            ? Appearance.colors.colOutlineVariant
            : Appearance.m3colors.m3surface

        // Bar awareness
        property bool isHug: Config.options.bar.cornerStyle === 0
        property bool isVerticalBar: Config.options.bar.vertical
        property bool barAtBottom: Config.options.bar.bottom

        property int barSideMargin: isHug
            ? (isVerticalBar ? Appearance.sizes.baseVerticalBarWidth : Appearance.sizes.baseBarHeight)
            : borderThickness

        property int maskTopMargin: (!isVerticalBar && !barAtBottom && isHug) ? barSideMargin : borderThickness
        property int maskBottomMargin: (!isVerticalBar && barAtBottom && isHug) ? barSideMargin : borderThickness
        property int maskLeftMargin: (isVerticalBar && !barAtBottom && isHug) ? barSideMargin : borderThickness
        property int maskRightMargin: (isVerticalBar && barAtBottom && isHug) ? barSideMargin : borderThickness

        property int roundingTopLeft: {
            if (isHug) {
                if (!isVerticalBar && !barAtBottom) return Appearance.rounding.screenRounding
                if (isVerticalBar && !barAtBottom) return Appearance.rounding.screenRounding
            }
            return borderRounding
        }
        property int roundingTopRight: {
            if (isHug) {
                if (!isVerticalBar && !barAtBottom) return Appearance.rounding.screenRounding
                if (isVerticalBar && barAtBottom) return Appearance.rounding.screenRounding
            }
            return borderRounding
        }
        property int roundingBottomLeft: {
            if (isHug) {
                if (!isVerticalBar && barAtBottom) return Appearance.rounding.screenRounding
                if (isVerticalBar && !barAtBottom) return Appearance.rounding.screenRounding
            }
            return borderRounding
        }
        property int roundingBottomRight: {
            if (isHug) {
                if (!isVerticalBar && barAtBottom) return Appearance.rounding.screenRounding
                if (isVerticalBar && barAtBottom) return Appearance.rounding.screenRounding
            }
            return borderRounding
        }

        Rectangle {
            id: borderRect
            anchors.fill: parent
            color: borderWindow.borderColor

            layer.enabled: true
            layer.effect: MultiEffect {
                maskSource: borderMask
                maskEnabled: true
                maskInverted: true
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
        }

        Item {
            id: borderMask
            anchors.fill: parent
            layer.enabled: true
            visible: false

            // Inner hole
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: borderWindow.maskTopMargin
                anchors.bottomMargin: borderWindow.maskBottomMargin
                anchors.leftMargin: borderWindow.maskLeftMargin
                anchors.rightMargin: borderWindow.maskRightMargin
                topLeftRadius: borderWindow.roundingTopLeft
                topRightRadius: borderWindow.roundingTopRight
                bottomLeftRadius: borderWindow.roundingBottomLeft
                bottomRightRadius: borderWindow.roundingBottomRight
            }

            // Bar exclusion: mask out the entire bar area so the border
            // never renders there, regardless of surface z-order
            Rectangle {
                visible: borderWindow.isHug
                x: borderWindow.isVerticalBar && borderWindow.barAtBottom ? parent.width - width : 0
                y: !borderWindow.isVerticalBar && borderWindow.barAtBottom ? parent.height - height : 0
                width: borderWindow.isVerticalBar ? borderWindow.barSideMargin : parent.width
                height: borderWindow.isVerticalBar ? parent.height : borderWindow.barSideMargin
            }
        }
    }
}
