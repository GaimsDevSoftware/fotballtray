import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

ColumnLayout {
    id: knockoutView
    property var matches: []
    property var projected: []          // R32 bracket projected from current standings
    property bool showProjection: false // toggled by the button below
    property var theme: ({ primary: "#ffd700", secondary: "#1a237e" })

    spacing: Kirigami.Units.smallSpacing

    // ── Live projection toggle ─────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        visible: projected && projected.length > 0
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            Layout.preferredHeight: 30
            Layout.preferredWidth: projBtnRow.implicitWidth + Kirigami.Units.largeSpacing * 2
            radius: 15
            color: knockoutView.showProjection
                ? (theme.primary || Kirigami.Theme.highlightColor)
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)
            border.color: theme.primary || Kirigami.Theme.highlightColor
            border.width: 1
            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: knockoutView.showProjection = !knockoutView.showProjection
            }
            RowLayout {
                id: projBtnRow
                anchors.centerIn: parent
                spacing: 5
                Text { text: "🔮"; font.pixelSize: 13 }
                Kirigami.Heading {
                    text: knockoutView.showProjection ? "Live projection: ON" : "Show live projection"
                    level: 6; font.bold: true
                    color: knockoutView.showProjection ? "white" : Kirigami.Theme.textColor
                }
            }
        }
        Kirigami.Heading {
            visible: knockoutView.showProjection
            text: "Round of 32 if the groups froze right now"
            level: 6; font.pixelSize: 10; font.italic: true
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true; elide: Text.ElideRight
        }
    }

    // ── Empty state (real bracket only) ────────────────────────────────────
    Kirigami.Heading {
        visible: !showProjection && matches.length === 0
        text: "No knockout matches available yet"
        level: 6; color: Kirigami.Theme.disabledTextColor
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.largeSpacing
    }

    // ── Projected Round of 32 - clean two-column bracket of stacked cards ───
    GridLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: showProjection
        columns: 2
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.smallSpacing

        Repeater {
            model: showProjection ? projected : []
            delegate: Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: cardCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.backgroundColor
                radius: 8
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                border.width: 1

                // Bracket accent stripe
                Rectangle {
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: 3; radius: 8
                    color: theme.primary || Kirigami.Theme.highlightColor
                    opacity: 0.8
                }

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing + 4
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    anchors.topMargin: Kirigami.Units.smallSpacing
                    anchors.bottomMargin: Kirigami.Units.smallSpacing
                    spacing: 3

                    Kirigami.Heading {
                        text: "Match " + modelData.match
                        level: 6; font.pixelSize: 8; font.bold: true
                        color: theme.primary || Kirigami.Theme.highlightColor
                    }

                    // Home line
                    RowLayout {
                        Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                        FlagImage { source: modelData.homeFlag || ""; size: Kirigami.Units.gridUnit * 1.1; visible: !!modelData.homeFlag }
                        Kirigami.Heading {
                            text: modelData.home || "?"; level: 6; font.bold: true; font.pixelSize: 12
                            Layout.fillWidth: true; elide: Text.ElideRight
                        }
                        Kirigami.Heading {
                            text: modelData.homeLabel || ""; level: 6; font.pixelSize: 8
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 1
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                    }

                    // Away line
                    RowLayout {
                        Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                        FlagImage { source: modelData.awayFlag || ""; size: Kirigami.Units.gridUnit * 1.1; visible: !!modelData.awayFlag }
                        Kirigami.Heading {
                            text: modelData.away || "?"; level: 6; font.bold: true; font.pixelSize: 12
                            Layout.fillWidth: true; elide: Text.ElideRight
                        }
                        Kirigami.Heading {
                            text: modelData.awayLabel || ""; level: 6; font.pixelSize: 8
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }
                }
            }
        }
    }

    // ── Real knockout bracket (when not projecting) ────────────────────────
    Repeater {
        model: showProjection ? [] : groupedMatches()
        delegate: ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            Kirigami.Heading {
                text: modelData.round
                level: 6; font.bold: true
                color: theme.primary || Kirigami.Theme.highlightColor
                leftPadding: 2
                visible: modelData.round && modelData.round.length > 0
            }

            Repeater {
                model: modelData.matches
                delegate: Rectangle {
                    Layout.fillWidth: true
                    height: innerRow.implicitHeight + Kirigami.Units.largeSpacing
                    color: Kirigami.Theme.backgroundColor
                    radius: 10
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
                    border.width: 1

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: 3; radius: 10
                        color: theme.primary || Kirigami.Theme.highlightColor
                        opacity: 0.75
                    }

                    RowLayout {
                        id: innerRow
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 10
                        anchors.topMargin: Kirigami.Units.smallSpacing; anchors.bottomMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.largeSpacing

                        Kirigami.Heading {
                            text: modelData.homeTeam || "?"
                            level: 5; font.bold: true
                            Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                        TeamBadge { matchObj: modelData; isHome: true; size: Kirigami.Units.gridUnit * 1.4 }

                        Rectangle {
                            implicitWidth: scoreLabel.implicitWidth + 16
                            implicitHeight: scoreLabel.implicitHeight + 6
                            radius: 8
                            color: Qt.rgba(
                                Qt.color(theme.primary || "#ffd700").r,
                                Qt.color(theme.primary || "#ffd700").g,
                                Qt.color(theme.primary || "#ffd700").b, 0.12)
                            border.color: theme.primary || Kirigami.Theme.highlightColor
                            border.width: 1

                            Kirigami.Heading {
                                id: scoreLabel; anchors.centerIn: parent
                                text: (modelData.homeScore !== undefined ? modelData.homeScore : "?") + " – " + (modelData.awayScore !== undefined ? modelData.awayScore : "?")
                                level: 3; font.bold: true
                                font.features: ({ "tnum": 1 })
                                color: theme.primary || Kirigami.Theme.highlightColor
                            }
                        }

                        TeamBadge { matchObj: modelData; isHome: false; size: Kirigami.Units.gridUnit * 1.4 }
                        Kirigami.Heading {
                            text: modelData.awayTeam || "?"
                            level: 5; font.bold: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    Kirigami.Heading {
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.margins: 4
                        text: modelData.display || ""
                        level: 6; font.pixelSize: 9
                        color: Kirigami.Theme.disabledTextColor
                        visible: (modelData.display || "").length > 0
                    }
                }
            }
        }
    }

    function groupedMatches() {
        if (!matches || matches.length === 0) return [];
        var groups = [];
        var seen = {};
        for (var i = 0; i < matches.length; i++) {
            var m = matches[i];
            var round = m.round || m.roundName || "";
            if (!seen[round]) {
                seen[round] = true;
                groups.push({ round: round, matches: [] });
            }
            groups[groups.length - 1].matches.push(m);
        }
        return groups;
    }
}
