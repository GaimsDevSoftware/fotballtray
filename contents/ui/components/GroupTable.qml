import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "."

// Lean standings table (research: football-livescore-app-visual-design-2026 §6).
// Columns: Pos | flag+name | P | GD | Pts(bold). Thin qualification zone bar on
// the left for the top 2. Flat surface, hairlines, desaturated accent — no boxes.
Rectangle {
    id: groupCard

    property string groupName: "A"
    property var teams: []
    property var theme: ({ primary: "#4CAF50", secondary: "#1a237e" })

    readonly property int rowHeight: Kirigami.Units.gridUnit * 1.7
    readonly property int headerHeight: Kirigami.Units.gridUnit * 1.5

    // Fixed numeric column widths (kept tight so the name gets the most room).
    readonly property int wPos:  Kirigami.Units.gridUnit * 1.3
    readonly property int wFlag: Kirigami.Units.gridUnit * 1.5
    readonly property int wP:    Kirigami.Units.gridUnit * 1.5
    readonly property int wGD:   Kirigami.Units.gridUnit * 1.8
    readonly property int wPts:  Kirigami.Units.gridUnit * 1.7

    // Qualification colour (top-2 advance) — follows the user's live/result colour.
    property color qualColor: Kirigami.Theme.positiveTextColor

    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03)
    radius: Kirigami.Units.smallSpacing
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
    border.width: 1

    Layout.fillWidth: true
    Layout.preferredHeight: headerHeight + rowHeight * (teams.length + 1) + Kirigami.Units.smallSpacing * 2

    function gdText(t) {
        var v = (t && t.gd !== undefined) ? Number(t.gd) : (Number(t.gf||0) - Number(t.ga||0));
        return (v > 0 ? "+" : "") + v;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: 0

        // Group label
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: headerHeight
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                width: 3; height: headerHeight * 0.55; radius: 1.5
                color: groupCard.qualColor
                Layout.alignment: Qt.AlignVCenter
            }
            Kirigami.Heading {
                text: "Group " + groupName
                level: 5; font.bold: true
                color: Kirigami.Theme.textColor
                Layout.fillWidth: true
            }
        }

        // Column header
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: rowHeight * 0.8
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                text: "#"; font.pixelSize: 10
                color: Kirigami.Theme.disabledTextColor
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: groupCard.wPos
            }
            Item { Layout.preferredWidth: groupCard.wFlag }  // flag column spacer
            PlasmaComponents3.Label {
                text: "Team"; font.pixelSize: 10
                color: Kirigami.Theme.disabledTextColor
                Layout.fillWidth: true
            }
            PlasmaComponents3.Label {
                text: "P"; font.pixelSize: 10
                color: Kirigami.Theme.disabledTextColor
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: groupCard.wP
            }
            PlasmaComponents3.Label {
                text: "+/-"; font.pixelSize: 10
                color: Kirigami.Theme.disabledTextColor
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: groupCard.wGD
            }
            PlasmaComponents3.Label {
                text: "Pts"; font.pixelSize: 10
                color: Kirigami.Theme.disabledTextColor
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: groupCard.wPts
            }
        }

        // Hairline
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
        }

        // Rows
        Repeater {
            model: teams
            delegate: Item {
                Layout.fillWidth: true
                Layout.preferredHeight: groupCard.rowHeight

                readonly property bool qualifies: index < 2

                // Thin qualification zone bar (left)
                Rectangle {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: 3; height: parent.height * 0.6; radius: 1.5
                    color: groupCard.qualColor
                    visible: qualifies
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        text: modelData.rank || (index + 1)
                        font.bold: qualifies
                        color: qualifies ? groupCard.qualColor : Kirigami.Theme.disabledTextColor
                        horizontalAlignment: Text.AlignHCenter
                        Layout.preferredWidth: groupCard.wPos
                    }
                    // Round flag
                    FlagImage {
                        Layout.preferredWidth: groupCard.wFlag
                        Layout.alignment: Qt.AlignVCenter
                        size: Kirigami.Units.gridUnit * 1.2
                        source: modelData.flag || ""
                        countryCode: modelData.countryCode || ""
                    }
                    PlasmaComponents3.Label {
                        text: modelData.team || ""
                        elide: Text.ElideRight
                        font.weight: qualifies ? Font.Medium : Font.Normal
                        color: Kirigami.Theme.textColor
                        Layout.fillWidth: true
                    }
                    PlasmaComponents3.Label {
                        text: modelData.played !== undefined ? modelData.played : "0"
                        color: Kirigami.Theme.disabledTextColor
                        horizontalAlignment: Text.AlignHCenter
                        Layout.preferredWidth: groupCard.wP
                    }
                    PlasmaComponents3.Label {
                        text: groupCard.gdText(modelData)
                        color: Kirigami.Theme.disabledTextColor
                        horizontalAlignment: Text.AlignHCenter
                        Layout.preferredWidth: groupCard.wGD
                    }
                    PlasmaComponents3.Label {
                        text: modelData.points !== undefined ? modelData.points : "0"
                        font.bold: true
                        color: Kirigami.Theme.textColor
                        horizontalAlignment: Text.AlignHCenter
                        Layout.preferredWidth: groupCard.wPts
                    }
                }
            }
        }
    }
}
