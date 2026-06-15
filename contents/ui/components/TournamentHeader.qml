import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../Theme.js" as Theme

// Slim, STATIC championship strip.
// Research verdict (event-branding-glanceable-widgets-2026): kill the 170px
// animated banner — mascot + orbs + pulsing logo + floating loops violate
// calm-tech and WCAG 2.2.2. The "championship mode" signal is the ACCENT colour
// threaded through the UI, not a big illustration. Here: a ~2.6 gridUnit strip
// with a small emblem, the name, and a year/host subtitle, plus one fade-in.
Item {
    id: header
    property var tournamentObj: ({})
    property bool active: tournamentObj && tournamentObj.themeActive

    implicitHeight: active ? Kirigami.Units.gridUnit * 2.6 : 0
    implicitWidth: parent ? parent.width : 300
    visible: active
    clip: true

    readonly property string logoUrl:        active && tournamentObj.assets ? tournamentObj.assets.logo : ""
    readonly property string tournamentName: active ? (tournamentObj.tournamentName || "") : ""
    readonly property string subtitle: {
        if (!active) return "";
        if (tournamentObj.subtitle) return tournamentObj.subtitle;
        if (tournamentObj.tournamentId === "FIFA.WORLD") return "2026 · Canada / Mexico / USA";
        return "";
    }

    // Calm, desaturated accent derived from the league theme.
    readonly property color accent: active
        ? Theme.softAccent(tournamentObj.tournamentId || "default")
        : Kirigami.Theme.highlightColor

    // One-shot fade-in when the theme activates — no ambient loops.
    opacity: 0
    onActiveChanged: opacity = active ? 1 : 0
    Component.onCompleted: if (active) opacity = 1
    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }

    // Flat, faintly tinted background (no gradient, no border-glow).
    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.smallSpacing
        color: Qt.rgba(header.accent.r, header.accent.g, header.accent.b, 0.10)
    }

    // Thin accent edge on the left — the "championship" tell, understated.
    Rectangle {
        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
        width: 3; radius: 1.5
        color: header.accent
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        // Small static emblem — decode at the physical pixel size (× pixel ratio)
        // and mipmap so it's sharp on 4K / scaled displays.
        Image {
            source: header.logoUrl
            visible: header.logoUrl.length > 0
            sourceSize.width: Math.ceil(Kirigami.Units.gridUnit * 1.8 * Math.max(2, Screen.devicePixelRatio) * 2)
            sourceSize.height: Math.ceil(Kirigami.Units.gridUnit * 1.8 * Math.max(2, Screen.devicePixelRatio) * 2)
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.8
            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.8
            fillMode: Image.PreserveAspectFit
            smooth: true; mipmap: true; asynchronous: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            Kirigami.Heading {
                text: header.tournamentName
                level: 4
                font.weight: Font.Bold
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Kirigami.Heading {
                text: header.subtitle
                visible: header.subtitle.length > 0
                level: 6
                color: Kirigami.Theme.disabledTextColor
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }
}
