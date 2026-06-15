import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "components"

Item {
    id: fullRep
    // Wide popup so 12 groups (A-L) show 2 columns AND long names + flags + stat
    // rows fit without truncation.
    implicitWidth: Kirigami.Units.gridUnit * 72
    implicitHeight: Kirigami.Units.gridUnit * 62
    Layout.preferredWidth: Kirigami.Units.gridUnit * 72
    Layout.preferredHeight: Kirigami.Units.gridUnit * 62

    readonly property var displayMatches: { root.dataVersion; return root.getDisplayMatches(); }
    readonly property var theme: root.themeFor(root.activeLeagueId)
    property int currentTab: 0

    Connections {
        target: root
        function onExpandedChanged() {
            if (root.expanded && root.openTournamentView) {
                fullRep.currentTab = 1;
                root.openTournamentView = false;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    // Tournament theme accent stripe at the very top
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: theme.special ? 3 : 0
        visible: theme.special
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: theme.primary || Kirigami.Theme.highlightColor }
            GradientStop { position: 0.5; color: theme.accent || Qt.rgba(1,1,1,0.0) }
            GradientStop { position: 1.0; color: theme.primary || Kirigami.Theme.highlightColor }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        // Tournament branding header
        TournamentHeader {
            Layout.fillWidth: true
            tournamentObj: root.tournamentData
        }

        // ── Pill-style top-level tabs ──────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 38
            radius: 19
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 3

                Repeater {
                    model: [{ label: "⚽  Matches", idx: 0 }, { label: "🏆  Tournament", idx: 1 }]

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: height / 2
                        color: fullRep.currentTab === modelData.idx
                            ? Kirigami.Theme.highlightColor
                            : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Kirigami.Units.shortDuration }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: fullRep.currentTab = modelData.idx
                        }

                        Kirigami.Heading {
                            anchors.centerIn: parent
                            text: modelData.label
                            level: 5
                            font.bold: fullRep.currentTab === modelData.idx
                            color: fullRep.currentTab === modelData.idx
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

        // ── Matches tab ────────────────────────────────────────────────────
        ScrollView {
            id: matchesScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: fullRep.currentTab === 0
            clip: true

            ColumnLayout {
                // Bind to availableWidth — parent.width is circular inside a
                // ScrollView and collapses fillWidth children to 0.
                width: matchesScroll.availableWidth
                spacing: Kirigami.Units.smallSpacing

                // Empty state
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: emptyCol.implicitHeight + Kirigami.Units.gridUnit * 2
                    visible: displayMatches.length === 0

                    ColumnLayout {
                        id: emptyCol
                        anchors.centerIn: parent
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Heading {
                            text: "No matches to show"
                            level: 4; color: Kirigami.Theme.disabledTextColor
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Kirigami.Heading {
                            text: "Check the settings for teams and leagues"
                            level: 6; color: Kirigami.Theme.disabledTextColor
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }

                Repeater {
                    // Integer model keeps delegates (and their expanded state)
                    // stable across refreshes; matchObj re-reads the fresh array
                    // on every dataVersion bump so live scores update in place.
                    model: displayMatches.length
                    delegate: MatchDetailCard {
                        Layout.fillWidth: true
                        matchObj: { root.dataVersion; return fullRep.displayMatches[index]; }
                        liveColor: root.liveColor
                    }
                }
            }
        }

        // ── Tournament tab ─────────────────────────────────────────────────
        TournamentView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: fullRep.currentTab === 1
            tournamentObj: root.tournamentData
            theme: fullRep.theme
        }
    }

    // ── First-run animated onboarding ──────────────────────────────────────
    Loader {
        anchors.fill: parent
        active: !Plasmoid.configuration.onboardingDone
        sourceComponent: OnboardingOverlay {
            accent: root.liveColor
            onFinished: Plasmoid.configuration.onboardingDone = true
            onOpenSettings: {
                Plasmoid.configuration.onboardingDone = true;
                var a = Plasmoid.internalAction("configure");
                if (a) a.trigger();
            }
        }
    }
}
