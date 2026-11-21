// Style switcher indicator for the illogical-impulse bar.
//
// Sits in the util-button row: shows the active style, click opens the
// picker, right-click cycles to the next one. State comes from the small
// JSON file hyprprofile writes on every switch, watched rather than polled,
// so the label updates the instant a switch happens from anywhere -
// keybind, terminal, or this button.
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

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    CircleUtilButton {
        id: button
        anchors.centerIn: parent

        onClicked: event => {
            if (event.button === Qt.RightButton)
                Quickshell.execDetached([root.hyprprofile, "next"]);
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
            text: root.profileDescription.length > 0
                ? qsTr("Style: %1\n%2").arg(root.profileDisplay).arg(root.profileDescription)
                : qsTr("Style: %1").arg(root.profileDisplay)
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
        } catch (e) {
            console.log("[StyleSwitcher] could not parse state:", e);
        }
    }
}
