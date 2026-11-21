// Style switcher indicator for the illogical-impulse bar.
//
// Sits in the util-button row: click opens the picker (styles on top,
// wallpapers below), right-click cycles to the next look, middle-click to the
// next wallpaper. State comes from the small JSON file hyprprofile writes on
// every switch, watched rather than polled, so the tooltip updates the instant
// anything changes - keybind, terminal, or this button.
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string statePath: Quickshell.env("HOME") + "/.config/hypr-profiles/state/current.json"
    readonly property string hyprprofile: Quickshell.env("HOME") + "/.local/bin/hyprprofile"

    property string profileName: ""
    property string profileDisplay: "Style"
    property string profileDescription: ""
    property string wallpaperName: ""
    property string lookName: ""

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    CircleUtilButton {
        id: button
        anchors.centerIn: parent

        onClicked: event => {
            if (event.button === Qt.RightButton)
                Quickshell.execDetached([root.hyprprofile, "look", "next"]);
            else if (event.button === Qt.MiddleButton)
                Quickshell.execDetached([root.hyprprofile, "wallpaper", "next"]);
            else
                Quickshell.execDetached([root.hyprprofile, "menu"]);
        }

        MaterialSymbol {
            horizontalAlignment: Qt.AlignHCenter
            fill: 0
            text: "palette"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer2
        }

        StyledToolTip {
            text: {
                let lines = [qsTr("Style: %1").arg(root.profileDisplay)];
                if (root.profileDescription.length > 0)
                    lines.push(root.profileDescription);
                if (root.lookName.length > 0)
                    lines.push(qsTr("Look: %1").arg(root.lookName));
                else if (root.wallpaperName.length > 0)
                    lines.push(qsTr("Wallpaper: %1").arg(root.wallpaperName));
                lines.push(qsTr("click: pick  ·  right: next look  ·  middle: next wallpaper"));
                return lines.join("\n");
            }
        }
    }

    FileView {
        id: stateFile
        path: Qt.resolvedUrl(root.statePath)
        watchChanges: true

        onFileChanged: reload()
        onLoaded: root.parseState(text())
        // A missing file just means no switch has happened yet; the button
        // still works, it simply has no name to show.
        onLoadFailed: root.profileDisplay = qsTr("Style")
    }

    function parseState(raw: string): void {
        try {
            const data = JSON.parse(raw);
            root.profileName = data.name ?? "";
            root.profileDisplay = data.display ?? data.name ?? qsTr("Style");
            root.profileDescription = data.description ?? "";
            root.wallpaperName = data.wallpaperName ?? "";
            root.lookName = data.lookName ?? "";
        } catch (e) {
            console.log("[StyleSwitcher] could not parse state:", e);
        }
    }
}
