import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "components"

Item {
    id: compactRep

    Layout.minimumWidth: rowLayout.implicitWidth + Kirigami.Units.largeSpacing
    Layout.preferredWidth: Layout.minimumWidth
    implicitWidth: Layout.minimumWidth
    implicitHeight: Kirigami.Units.iconSizes.smallMedium

    // Reference dataVersion so the tray re-reads scores on every load even when
    // the match count is unchanged (live goal → new homeScore, same length).
    readonly property var matches: { root.dataVersion; return root.getDisplayMatches(); }
    readonly property var theme: root.themeFor(root.activeLeagueId)
    readonly property string displayMode: root.trayDisplayMode

    property var activeMatch: {
        if (!matches || matches.length === 0) return null;
        for (var i = 0; i < matches.length; i++) {
            if (matches[i].status === "in" || matches[i].status === "ht") return matches[i];
        }
        return matches[0];
    }

    MouseArea {
        anchors.fill: parent
        id: mouseArea
        onClicked: root.expanded = !root.expanded
        hoverEnabled: true
    }

    // Hover highlight
    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.highlightColor
        opacity: mouseArea.containsMouse ? 0.15 : 0.0
        radius: 4
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        // Live indicator dot
        Rectangle {
            width: 7; height: 7; radius: 4
            color: root.liveColor
            border.color: "black"
            border.width: root.liveOutline ? 1 : 0
            visible: activeMatch && activeMatch.status === "in"
            SequentialAnimation on opacity {
                running: activeMatch && activeMatch.status === "in"
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.15; duration: Kirigami.Units.veryLongDuration * 2 }
                NumberAnimation { from: 0.15; to: 1.0; duration: Kirigami.Units.veryLongDuration * 2 }
            }
        }

        TeamBadge {
            matchObj: activeMatch; isHome: true
            size: Kirigami.Units.iconSizes.roundedIconSize(Kirigami.Units.iconSizes.smallMedium)
            visible: activeMatch !== null && displayMode !== "text"
            Layout.alignment: Qt.AlignVCenter
        }

        // Team abbreviation - its own colour + outline (style group "Lagnavn").
        OutlinedLabel {
            text: activeMatch ? (activeMatch.homeAbbrev || activeMatch.homeTeam.substring(0,3).toUpperCase()) : ""
            level: 4; weight: Font.ExtraBold
            color: root.teamColor
            outlined: root.teamOutline
            shadow: root.teamShadow
            Layout.alignment: Qt.AlignVCenter
            visible: displayMode !== "flagOnly"
        }

        // Score box
        Rectangle {
            color: hasResult(activeMatch)
                ? Qt.rgba(root.liveColor.r, root.liveColor.g, root.liveColor.b, 0.12)
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
            radius: 5
            Layout.preferredWidth: scoreTxt.implicitWidth + 10
            Layout.preferredHeight: scoreTxt.implicitHeight + 6
            Layout.alignment: Qt.AlignVCenter
            Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }

            OutlinedLabel {
                id: scoreTxt; anchors.centerIn: parent
                text: activeMatch ? (activeMatch.homeScore + " – " + activeMatch.awayScore) : "-"
                level: 4; weight: Font.ExtraBold
                // Result/time style group: own colour + own outline.
                color: root.liveColor
                outlined: root.liveOutline
                shadow: root.liveShadow
            }
        }

        // Away team abbreviation - same "Lagnavn" style group as the home one.
        OutlinedLabel {
            text: activeMatch ? (activeMatch.awayAbbrev || activeMatch.awayTeam.substring(0,3).toUpperCase()) : ""
            level: 4; weight: Font.ExtraBold
            color: root.teamColor
            outlined: root.teamOutline
            shadow: root.teamShadow
            Layout.alignment: Qt.AlignVCenter
            visible: displayMode !== "flagOnly"
        }

        TeamBadge {
            matchObj: activeMatch; isHome: false
            size: Kirigami.Units.iconSizes.roundedIconSize(Kirigami.Units.iconSizes.smallMedium)
            visible: activeMatch !== null && displayMode !== "text"
            Layout.alignment: Qt.AlignVCenter
        }

        // Status / time - part of the result/time style group.
        OutlinedLabel {
            text: activeMatch ? trayStatus(activeMatch) : ""
            level: 5; bold: false
            color: root.liveColor
            outlined: root.liveOutline
            shadow: root.liveShadow
            Layout.alignment: Qt.AlignVCenter
            visible: activeMatch !== null
        }
    }

    // A match has a meaningful score to colour (live, half-time or finished).
    // Pre-match keeps the neutral text colour (no "result" yet).
    function hasResult(m) {
        if (!m) return false;
        var s = m.status || "pre";
        return s === "in" || s === "ht" || s === "post" || s === "ft";
    }

    function trayStatus(m) {
        if (!m) return "";
        if (m.status === "in") return m.clock || m.display || "LIVE";
        if (m.status === "ht") return "HT";
        if (m.status === "pre" && m.matchTime) {
            var d = new Date(m.matchTime);
            if (!isNaN(d.getTime())) return Qt.formatTime(d, "HH:mm");
        }
        if (m.status === "post" || m.status === "ft") return "Full-time";
        return m.display || "";
    }

    // ── Goal banner ticker ─────────────────────────────────────────────
    property var goalMatch: {
        if (!matches) return null;
        for (var i = 0; i < matches.length; i++) {
            if (matches[i].recentGoal) return matches[i];
        }
        return null;
    }

    Rectangle {
        id: goalBanner
        anchors.fill: parent
        color: theme.primary || Kirigami.Theme.positiveTextColor
        radius: 4
        visible: goalMatch !== null
        clip: true; z: 100

        Kirigami.Heading {
            id: scrollText
            text: {
                if (!goalMatch) return "";
                var mode = root.tickerDisplayMode;
                var h = (mode === "fullName") ? goalMatch.homeTeam : (goalMatch.homeAbbrev || goalMatch.homeTeam.substring(0,3).toUpperCase());
                var a = (mode === "fullName") ? goalMatch.awayTeam : (goalMatch.awayAbbrev || goalMatch.awayTeam.substring(0,3).toUpperCase());
                var score = goalMatch.homeScore + "–" + goalMatch.awayScore;
                if (mode === "scoreOnly" || mode === "flagOnly") return "⚽ GOOOAL! " + score + " !!!";
                return "⚽ GOOOAL! " + h + " " + score + " " + a + " !!!";
            }
            color: "white"
            font.bold: true; font.weight: Font.Black
            anchors.verticalCenter: parent.verticalCenter

            XAnimator on x {
                from: goalBanner.width
                to: -scrollText.implicitWidth - 20
                duration: (11 - root.tickerSpeed) * 500
                loops: Animation.Infinite
                running: goalMatch !== null
            }
        }
    }
}
