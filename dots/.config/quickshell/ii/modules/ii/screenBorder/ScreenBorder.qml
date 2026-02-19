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
        // For horizontal bar: bar.bottom means bar is at bottom, otherwise top
        // For vertical bar: bar.bottom means bar is at right, otherwise left
        property bool barAtBottom: Config.options.bar.bottom

        // Margins: on the bar's hug side, extend the margin to match the bar size
        // so the border's inner curve aligns with the bar's RoundCorner
        property int barSideMargin: isHug
            ? (isVerticalBar ? Appearance.sizes.baseVerticalBarWidth : Appearance.sizes.baseBarHeight)
            : borderThickness

        property int maskTopMargin: (!isVerticalBar && !barAtBottom && isHug) ? barSideMargin : borderThickness
        property int maskBottomMargin: (!isVerticalBar && barAtBottom && isHug) ? barSideMargin : borderThickness
        property int maskLeftMargin: (isVerticalBar && !barAtBottom && isHug) ? barSideMargin : borderThickness
        property int maskRightMargin: (isVerticalBar && barAtBottom && isHug) ? barSideMargin : borderThickness

        // Per-corner rounding: on the bar's hug side, match screenRounding;
        // on the other side, use the configured borderRounding
        property int barSideRounding: isHug ? Appearance.rounding.screenRounding : borderRounding

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

        // Colored rectangle filling the entire window, masked to show only the border frame
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

        // Invisible mask: defines the "hole" (everything inside the border)
        Item {
            id: borderMask
            anchors.fill: parent
            layer.enabled: true
            visible: false

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
        }
    }
}
