import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

Item {
    id: compactCard
    property var matchObj: ({})
    implicitHeight: Kirigami.Units.gridUnit * 2.5
    implicitWidth: parent ? parent.width : 300

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        radius: 6
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
        border.width: 1
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        TeamBadge { matchObj: compactCard.matchObj; isHome: true; size: Kirigami.Units.iconSizes.small }

        Kirigami.Heading {
            text: matchObj ? (matchObj.homeAbbrev || (matchObj.homeTeam || "").substring(0,3).toUpperCase()) : ""
            level: 5; font.bold: true; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
        }

        Kirigami.Heading {
            text: matchObj ? (matchObj.homeScore + " - " + matchObj.awayScore) : "0-0"
            level: 4; font.bold: true
            color: matchObj && matchObj.status === "in" ? "#4CAF50" : Kirigami.Theme.textColor
        }

        Kirigami.Heading {
            text: matchObj ? (matchObj.awayAbbrev || (matchObj.awayTeam || "").substring(0,3).toUpperCase()) : ""
            level: 5; font.bold: true; Layout.fillWidth: true
        }

        TeamBadge { matchObj: compactCard.matchObj; isHome: false; size: Kirigami.Units.iconSizes.small }
    }
}
