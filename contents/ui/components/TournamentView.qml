import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "."

Item {
    id: tournamentView
    property var tournamentObj: ({})
    property var theme: ({ primary: "#ffd700", secondary: "#1a237e" })
    property int currentTab: 0

    implicitHeight: mainColumn.implicitHeight + 20

    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // ── Pill-style sub-tabs ────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 32
            radius: 16
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 2
                spacing: 2

                Repeater {
                    model: [
                        { label: "📊 Groups", idx: 0 },
                        { label: "🏆 Knockout", idx: 1 },
                        { label: "⚽ Top scorers", idx: 2 }
                    ]

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: height / 2
                        color: tournamentView.currentTab === modelData.idx
                            ? Kirigami.Theme.highlightColor
                            : "transparent"
                        Behavior on color {
                            ColorAnimation { duration: Kirigami.Units.shortDuration }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tournamentView.currentTab = modelData.idx
                        }

                        Kirigami.Heading {
                            anchors.centerIn: parent
                            text: modelData.label
                            level: 6
                            font.bold: tournamentView.currentTab === modelData.idx
                            color: tournamentView.currentTab === modelData.idx
                                ? "white"
                                : Kirigami.Theme.textColor
                            Behavior on color {
                                ColorAnimation { duration: Kirigami.Units.shortDuration }
                            }
                        }
                    }
                }
            }
        }

        // ── Groups tab ─────────────────────────────────────────────────────
        ScrollView {
            id: groupsScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tournamentView.currentTab === 0
            clip: true

            GridLayout {
                // NB: bind to the ScrollView's availableWidth, NOT parent.width.
                // parent.width is circular inside a ScrollView (content width ←
                // content implicit width ≈ 0 for fillWidth-only children) → the
                // whole table collapses to width 0 and all columns overlap at x=0.
                width: groupsScroll.availableWidth
                // Always 2 columns — popup is now wide enough for this
                columns: 2
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: {
                        var g = tournamentObj && tournamentObj.groups ? tournamentObj.groups : {};
                        return Object.keys(g);
                    }
                    GroupTable {
                        Layout.fillWidth: true
                        groupName: modelData
                        teams: tournamentObj.groups[modelData]
                        theme: tournamentView.theme
                        qualColor: root.liveColor
                    }
                }
            }
        }

        // ── Knockout tab ───────────────────────────────────────────────────
        ScrollView {
            id: knockoutScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tournamentView.currentTab === 1
            clip: true

            KnockoutView {
                width: knockoutScroll.availableWidth
                matches: tournamentObj && tournamentObj.knockoutMatches ? tournamentObj.knockoutMatches : []
                projected: tournamentObj && tournamentObj.projectedKnockout ? tournamentObj.projectedKnockout : []
                theme: tournamentView.theme
            }
        }

        // ── Top scorers tab ────────────────────────────────────────────────
        ScrollView {
            id: scorersScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tournamentView.currentTab === 2
            clip: true

            RowLayout {
                width: scorersScroll.availableWidth
                spacing: Kirigami.Units.largeSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: (scorersScroll.availableWidth - Kirigami.Units.largeSpacing) / 2
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        text: "Top scorers"
                        level: 5; font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Repeater {
                        model: tournamentObj && tournamentObj.topScorers ? tournamentObj.topScorers : []
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                            radius: Kirigami.Units.smallSpacing

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Heading { text: index + 1; level: 6; color: Kirigami.Theme.disabledTextColor; Layout.preferredWidth: 18; horizontalAlignment: Text.AlignHCenter }
                                FlagImage {
                                    visible: !!modelData.flag
                                    Layout.preferredWidth: modelData.flag ? Kirigami.Units.gridUnit : 0
                                    size: Kirigami.Units.gridUnit
                                    source: modelData.flag || ""
                                    countryCode: modelData.countryCode || ""
                                }
                                Kirigami.Heading { text: modelData.name; level: 6; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                                Kirigami.Heading { text: modelData.team || ""; visible: !!modelData.team; level: 6; color: Kirigami.Theme.disabledTextColor; Layout.preferredWidth: modelData.team ? 72 : 0; elide: Text.ElideRight }
                                Rectangle {
                                    width: 26; height: 18; radius: 4
                                    color: theme.primary || Kirigami.Theme.highlightColor
                                    Kirigami.Heading { anchors.centerIn: parent; text: modelData.goals; level: 6; color: "white"; font.bold: true }
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: (scorersScroll.availableWidth - Kirigami.Units.largeSpacing) / 2
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        text: "Assists"
                        level: 5; font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Repeater {
                        model: tournamentObj && tournamentObj.topAssists ? tournamentObj.topAssists : []
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                            radius: Kirigami.Units.smallSpacing

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Heading { text: index + 1; level: 6; color: Kirigami.Theme.disabledTextColor; Layout.preferredWidth: 18; horizontalAlignment: Text.AlignHCenter }
                                FlagImage {
                                    visible: !!modelData.flag
                                    Layout.preferredWidth: modelData.flag ? Kirigami.Units.gridUnit : 0
                                    size: Kirigami.Units.gridUnit
                                    source: modelData.flag || ""
                                    countryCode: modelData.countryCode || ""
                                }
                                Kirigami.Heading { text: modelData.name; level: 6; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                                Kirigami.Heading { text: modelData.team || ""; visible: !!modelData.team; level: 6; color: Kirigami.Theme.disabledTextColor; Layout.preferredWidth: modelData.team ? 72 : 0; elide: Text.ElideRight }
                                Rectangle {
                                    width: 26; height: 18; radius: 4
                                    color: theme.secondary || Kirigami.Theme.highlightColor
                                    Kirigami.Heading { anchors.centerIn: parent; text: modelData.assists; level: 6; color: "white"; font.bold: true }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
