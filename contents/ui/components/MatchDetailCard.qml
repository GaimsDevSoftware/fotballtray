import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "."

// Flat match ROW (research: football-livescore-app-visual-design-2026).
// 3-zone layout [status | teams stacked | score], tabular bold score, one
// tasteful live dot (1.6s soft halo, honours reduced-motion), hairline/spacing
// instead of bordered cards. Click toggles the expandable stats/lineup/events.
Item {
    id: detailCard
    property var matchObj: ({})
    property bool expanded: false
    property int currentTab: 0

    // User-configurable colour for live/result accents (score, minute, dot, tint).
    property color liveColor: Kirigami.Theme.positiveTextColor
    // Active commentator style's accent - applied ONLY to the live-commentary
    // marker, never to scores/teams (those keep the user's chosen colours).
    property color accentColor: liveColor

    // When the user disables animations system-wide, Kirigami durations collapse
    // to ~1 - use that as a reduced-motion proxy (no direct QML media query).
    readonly property bool reduceMotion: Kirigami.Units.longDuration <= 1

    implicitHeight: mainColumn.implicitHeight + Kirigami.Units.smallSpacing * 2
    implicitWidth: parent ? parent.width : 300

    // ── helpers ──────────────────────────────────────────────────────────

    function kickoffText(m) {
        if (!m) return "";
        var s = m.status || "pre";
        if (s === "in")  return m.clock || m.display || "LIVE";
        if (s === "ht")  return "HT";
        if (s === "pre") {
            if (m.matchTime) {
                var d = new Date(m.matchTime);
                if (!isNaN(d.getTime())) {
                    var now = new Date();
                    return (d.toDateString() === now.toDateString())
                        ? Qt.formatTime(d, "HH:mm")
                        : Qt.formatDate(d, "d. MMM");
                }
            }
            return m.display || "";
        }
        if (s === "post" || s === "ft") return "Full-time";
        return m.display || "";
    }

    // Second line under the kickoff time for not-today matches (the clock).
    function kickoffSub(m) {
        if (!m || (m.status || "pre") !== "pre" || !m.matchTime) return "";
        var d = new Date(m.matchTime);
        if (isNaN(d.getTime())) return "";
        var now = new Date();
        return (d.toDateString() === now.toDateString()) ? "" : Qt.formatTime(d, "HH:mm");
    }

    function statusColor(m) {
        if (!m) return Kirigami.Theme.disabledTextColor;
        var s = m.status || "pre";
        if (s === "in")  return detailCard.liveColor;
        if (s === "ht")  return Kirigami.Theme.neutralTextColor;
        if (s === "pre") return Kirigami.Theme.textColor;
        return Kirigami.Theme.disabledTextColor;
    }

    function isLive(m) { return m && m.status === "in"; }
    function isHT(m)   { return m && m.status === "ht"; }
    function hasScore(m) {
        if (!m) return false;
        var s = m.status || "pre";
        return s === "in" || s === "ht" || s === "post" || s === "ft";
    }
    function homeWinning(m) { return hasScore(m) && Number(m.homeScore) > Number(m.awayScore); }
    function awayWinning(m) { return hasScore(m) && Number(m.awayScore) > Number(m.homeScore); }

    function scoreColor(m, isHome) {
        if (isLive(m)) return detailCard.liveColor;
        var winning = isHome ? homeWinning(m) : awayWinning(m);
        return winning ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor;
    }

    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    // Desaturated team colour for the left edge stripe.
    readonly property color homeStripe: {
        var raw = matchObj && matchObj.homeColor ? ("#" + matchObj.homeColor) : Kirigami.Theme.highlightColor;
        var col = Qt.darker(raw, 1.0); // coerce string → color
        return Qt.hsla(col.hslHue, col.hslSaturation * 0.5,
                       Math.min(Math.max(col.hslLightness, 0.5), 0.72), 1.0);
    }

    // ── flat row background (no border; subtle tint on live/hover) ─────────
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: isLive(matchObj)
            ? tint(detailCard.liveColor, 0.06)
            : (rowMouse.containsMouse ? tint(Kirigami.Theme.textColor, 0.04) : "transparent")
        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
    }

    // Thin team-colour edge stripe (the only accent on the row)
    Rectangle {
        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
        anchors.topMargin: 4; anchors.bottomMargin: 4
        width: 3; radius: 1.5
        color: detailCard.homeStripe
        opacity: 0.9
    }

    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        anchors.topMargin: Kirigami.Units.smallSpacing
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        spacing: 2

        // Tiny competition label
        Kirigami.Heading {
            text: matchObj ? (matchObj.league || "") : ""
            visible: text.length > 0
            level: 6; font.pixelSize: 10
            color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true; elide: Text.ElideRight
        }

        // ── main row: [status | teams stacked w/ inline score] ─────────────
        MouseArea {
            id: rowMouse
            Layout.fillWidth: true
            implicitHeight: rowContent.implicitHeight
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: expanded = !expanded

            RowLayout {
                id: rowContent
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                // Status column
                ColumnLayout {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    // Live: dot + minute
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 4
                        visible: isLive(matchObj)

                        // Live dot with soft halo
                        Item {
                            implicitWidth: 9; implicitHeight: 9
                            Layout.alignment: Qt.AlignVCenter
                            Rectangle {
                                id: halo
                                anchors.centerIn: parent
                                width: 9; height: 9; radius: 4.5
                                color: detailCard.liveColor
                                ParallelAnimation {
                                    running: isLive(matchObj) && !detailCard.reduceMotion
                                    loops: Animation.Infinite
                                    NumberAnimation { target: halo; property: "scale"; from: 1.0; to: 3.0; duration: 1600; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: halo; property: "opacity"; from: 0.55; to: 0.0; duration: 1600; easing.type: Easing.OutCubic }
                                }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8; height: 8; radius: 4
                                color: detailCard.liveColor
                            }
                        }

                        Kirigami.Heading {
                            text: matchObj ? (matchObj.clock || matchObj.display || "") : ""
                            level: 6; font.bold: true; font.pixelSize: 12
                            color: detailCard.liveColor
                        }
                    }

                    // Non-live: status text (+ optional clock line)
                    Kirigami.Heading {
                        visible: !isLive(matchObj)
                        text: kickoffText(matchObj)
                        level: 6; font.pixelSize: 12
                        font.bold: isHT(matchObj)
                        color: statusColor(matchObj)
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Kirigami.Heading {
                        visible: !isLive(matchObj) && kickoffSub(matchObj).length > 0
                        text: kickoffSub(matchObj)
                        level: 6; font.pixelSize: 10
                        color: Kirigami.Theme.disabledTextColor
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Hairline divider
                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    color: detailCard.tint(Kirigami.Theme.textColor, 0.08)
                }

                // Teams stacked, each with inline score
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // Home
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        TeamBadge { matchObj: detailCard.matchObj; isHome: true; size: 22 }
                        Kirigami.Heading {
                            text: matchObj ? (matchObj.homeTeam || "") : ""
                            level: 5
                            font.weight: homeWinning(matchObj) ? Font.Bold : Font.Medium
                            color: Kirigami.Theme.textColor
                            Layout.fillWidth: true; elide: Text.ElideRight
                        }
                        Text {
                            id: homeScoreText
                            visible: hasScore(matchObj)
                            text: matchObj ? ("" + matchObj.homeScore) : ""
                            font.pixelSize: Kirigami.Units.gridUnit * 1.15
                            font.weight: Font.Bold
                            font.features: ({ "tnum": 1 })
                            color: scoreColor(matchObj, true)
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.3
                            property bool primed: false
                            Component.onCompleted: primed = true
                            onTextChanged: if (primed && !detailCard.reduceMotion) homeFlash.restart()
                            SequentialAnimation {
                                id: homeFlash
                                NumberAnimation { target: homeScoreText; property: "scale"; from: 1.0; to: 1.35; duration: 140; easing.type: Easing.OutQuad }
                                NumberAnimation { target: homeScoreText; property: "scale"; to: 1.0; duration: 420; easing.type: Easing.OutBounce }
                            }
                        }
                    }

                    // Away
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        TeamBadge { matchObj: detailCard.matchObj; isHome: false; size: 22 }
                        Kirigami.Heading {
                            text: matchObj ? (matchObj.awayTeam || "") : ""
                            level: 5
                            font.weight: awayWinning(matchObj) ? Font.Bold : Font.Medium
                            color: Kirigami.Theme.textColor
                            Layout.fillWidth: true; elide: Text.ElideRight
                        }
                        Text {
                            id: awayScoreText
                            visible: hasScore(matchObj)
                            text: matchObj ? ("" + matchObj.awayScore) : ""
                            font.pixelSize: Kirigami.Units.gridUnit * 1.15
                            font.weight: Font.Bold
                            font.features: ({ "tnum": 1 })
                            color: scoreColor(matchObj, false)
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.3
                            property bool primed: false
                            Component.onCompleted: primed = true
                            onTextChanged: if (primed && !detailCard.reduceMotion) awayFlash.restart()
                            SequentialAnimation {
                                id: awayFlash
                                NumberAnimation { target: awayScoreText; property: "scale"; from: 1.0; to: 1.35; duration: 140; easing.type: Easing.OutQuad }
                                NumberAnimation { target: awayScoreText; property: "scale"; to: 1.0; duration: 420; easing.type: Easing.OutBounce }
                            }
                        }
                    }
                }
            }
        }

        // Match narrative + goal scorers - styled callout
        Rectangle {
            visible: summaryNarrative().length > 0
            Layout.fillWidth: true
            Layout.topMargin: 2
            implicitHeight: summaryCol.implicitHeight + Kirigami.Units.smallSpacing * 2
            radius: 8
            color: detailCard.tint(Kirigami.Theme.textColor, 0.04)

            Rectangle {
                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                anchors.topMargin: 6; anchors.bottomMargin: 6
                width: 3; radius: 1.5
                // AI commentary → the style's accent; factual summary → liveColor.
                color: detailCard.tint((matchObj && matchObj.aiCommentary === true)
                                       ? detailCard.accentColor : detailCard.liveColor, 0.9)
            }

            ColumnLayout {
                id: summaryCol
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                // Tag live LLM commentary so it's distinct from the factual summary
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: matchObj && matchObj.aiCommentary === true
                    Text { text: "🎙"; font.pixelSize: 11 }
                    Kirigami.Heading {
                        text: "Live commentary"
                        level: 6; font.pixelSize: 9; font.bold: true
                        color: detailCard.accentColor
                    }
                }

                Kirigami.Heading {
                    text: summaryNarrative()
                    level: 6; color: Kirigami.Theme.textColor
                    font.italic: matchObj && matchObj.aiCommentary === true
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }

                // Goal scorers as small ⚽ chips
                Flow {
                    Layout.fillWidth: true
                    visible: summaryGoalList().length > 0
                    spacing: Kirigami.Units.smallSpacing
                    Repeater {
                        model: summaryGoalList()
                        delegate: Rectangle {
                            height: chipRow.implicitHeight + 4
                            width: chipRow.implicitWidth + 12
                            radius: height / 2
                            color: detailCard.tint(Kirigami.Theme.textColor, 0.06)
                            RowLayout {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 3
                                Text { text: "⚽"; font.pixelSize: 11 }
                                Kirigami.Heading {
                                    text: modelData; level: 6; font.pixelSize: 11
                                    color: Kirigami.Theme.textColor
                                }
                            }
                        }
                    }
                }
            }
        }

        // Venue (not shown during live)
        Kirigami.Heading {
            visible: matchObj && matchObj.venue && matchObj.venue.length > 0 && !isLive(matchObj)
            text: matchObj && matchObj.venue ? "📍 " + matchObj.venue : ""
            level: 6; font.pixelSize: 10; color: Kirigami.Theme.disabledTextColor
            Layout.fillWidth: true
        }

        // ── Expandable panel ─────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: expanded ? expandCol.implicitHeight : 0
            visible: expanded; clip: true
            Behavior on implicitHeight { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }

            ColumnLayout {
                id: expandCol; width: parent.width; spacing: 8

                // Sub-tabs (pill style, smaller)
                Rectangle {
                    Layout.fillWidth: true
                    height: 28; radius: 14
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent; anchors.margins: 2; spacing: 2
                        Repeater {
                            model: ["📊 Stats", "🏟️ Tactics", "⏱️ Events"]
                            Rectangle {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                radius: height / 2
                                color: currentTab === index ? Kirigami.Theme.highlightColor : "transparent"
                                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: currentTab = index }
                                Kirigami.Heading {
                                    anchors.centerIn: parent; text: modelData; level: 6; font.pixelSize: 10
                                    font.bold: currentTab === index
                                    color: currentTab === index ? "white" : Kirigami.Theme.textColor
                                    Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                                }
                            }
                        }
                    }
                }

                StackLayout {
                    Layout.fillWidth: true; currentIndex: currentTab
                    Layout.preferredHeight: currentIndex === 0 ? statsContent.implicitHeight
                                          : currentIndex === 1 ? tacticsCol.implicitHeight
                                          : eventsContent.implicitHeight

                    // === STATS ===
                    ColumnLayout {
                        id: statsContent; width: parent.width; spacing: 4
                        Kirigami.Heading {
                            visible: getStatsList().length === 0 || getStatsList()[0].label === "No data yet"
                            text: "No stats available yet."
                            level: 6; color: Kirigami.Theme.disabledTextColor; Layout.alignment: Qt.AlignHCenter
                        }
                        Repeater {
                            model: getStatsList()
                            StatBar {
                                Layout.fillWidth: true; label: modelData.label
                                homeValue: (expanded && currentTab === 0) ? modelData.home : 0
                                awayValue: (expanded && currentTab === 0) ? modelData.away : 0
                                isPercentage: modelData.percentage || false
                                // Unified palette: accent (= user's live colour) vs calm neutral.
                                homeColor: detailCard.liveColor
                                awayColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)
                                Behavior on homeValue { NumberAnimation { duration: Kirigami.Units.veryLongDuration; easing.type: Easing.OutCubic } }
                                Behavior on awayValue { NumberAnimation { duration: Kirigami.Units.veryLongDuration; easing.type: Easing.OutCubic } }
                            }
                        }
                    }

                    // === TAKTIKK (formation pitch) ===
                    // Players placed where they line up on a fictional pitch, each
                    // with a rating badge underneath (FotMob/Sofascore style). Home
                    // fills the bottom half, away the (mirrored) top half. Positions
                    // are derived from the formation string + starter order, since
                    // the data has no per-player coordinates.
                    ColumnLayout {
                        id: tacticsCol; width: parent.width
                        spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        id: lineupContent; Layout.fillWidth: true
                        implicitHeight: Kirigami.Units.gridUnit * 30
                        radius: 8
                        clip: true
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#1f3d2a" }
                            GradientStop { position: 1.0; color: "#15281c" }
                        }

                        // Pitch markings: halfway line + centre circle + faint stripes
                        Rectangle {  // halfway line (horizontal, home/away split)
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 1; color: Qt.rgba(1, 1, 1, 0.10)
                        }
                        Rectangle {  // centre circle
                            anchors.centerIn: parent
                            width: 58; height: 58; radius: 29
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.10); border.width: 1
                        }
                        Rectangle {  // home penalty box (bottom)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: parent.width * 0.42; height: parent.height * 0.16
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.07); border.width: 1
                        }
                        Rectangle {  // away penalty box (top)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            width: parent.width * 0.42; height: parent.height * 0.16
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.07); border.width: 1
                        }

                        // Formation labels in the corners
                        Kirigami.Heading {
                            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 6
                            visible: matchObj && matchObj.formations && matchObj.formations.home
                            text: matchObj && matchObj.formations ? (matchObj.formations.home || "") : ""
                            level: 6; font.pixelSize: 11; font.bold: true
                            color: Qt.rgba(1, 1, 1, 0.55)
                        }
                        Kirigami.Heading {
                            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 6
                            visible: matchObj && matchObj.formations && matchObj.formations.away
                            text: matchObj && matchObj.formations ? (matchObj.formations.away || "") : ""
                            level: 6; font.pixelSize: 11; font.bold: true
                            color: Qt.rgba(1, 1, 1, 0.55)
                        }

                        Kirigami.Heading {
                            anchors.centerIn: parent
                            visible: getHomeStarters().length === 0 && getAwayStarters().length === 0
                            text: "Line-up not ready yet"; level: 6; color: "white"
                        }

                        // Positioned player nodes (home + away)
                        Repeater {
                            model: (expanded && currentTab === 1) ? pitchNodes() : []
                            delegate: Item {
                                width: 78; height: 50
                                x: lineupContent.width  * modelData.xFrac - width / 2
                                y: lineupContent.height * modelData.yFrac - height / 2

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 1

                                    // Jersey disc
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 22; height: 22; radius: 11
                                        color: modelData.home ? "#ffffff" : "#0d1f14"
                                        border.color: modelData.home ? Qt.rgba(0,0,0,0.15) : Qt.rgba(1,1,1,0.55)
                                        border.width: 1.5
                                        Kirigami.Heading {
                                            anchors.centerIn: parent
                                            text: modelData.jersey || "?"
                                            font.pixelSize: 10; font.bold: true
                                            color: modelData.home ? "#1B5E20" : "white"
                                        }
                                    }

                                    // Surname only - clean and avoids overlap
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 78
                                        text: modelData.short || modelData.name || ""
                                        font.pixelSize: 10; font.bold: true
                                        color: "white"
                                        style: Text.Outline; styleColor: Qt.rgba(0,0,0,0.75)
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }

                                    // Rating badge underneath
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        visible: modelData.hasRating
                                        width: 22; height: 13; radius: 3
                                        color: ratingColor(modelData.rating)
                                        Kirigami.Heading {
                                            anchors.centerIn: parent
                                            text: Number(modelData.rating || 6.0).toFixed(1)
                                            font.pixelSize: 9; font.bold: true; color: "white"
                                        }
                                    }
                                }
                            }
                        }
                    }

                        // ── Reserves / bench under the pitch ──────────────────
                        Kirigami.Heading {
                            visible: getHomeSubs().length > 0 || getAwaySubs().length > 0
                            text: "Substitutes"; level: 6; font.pixelSize: 10; font.bold: true
                            color: Kirigami.Theme.disabledTextColor; Layout.topMargin: 2
                        }
                        Repeater {
                            model: [
                                { label: (matchObj && matchObj.homeAbbrev) ? matchObj.homeAbbrev : "Home", subs: getHomeSubs() },
                                { label: (matchObj && matchObj.awayAbbrev) ? matchObj.awayAbbrev : "Away", subs: getAwaySubs() }
                            ]
                            delegate: RowLayout {
                                id: benchTeamRow
                                property var teamData: modelData
                                Layout.fillWidth: true
                                visible: benchTeamRow.teamData.subs.length > 0
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Heading {
                                    text: benchTeamRow.teamData.label; level: 6; font.pixelSize: 9; font.bold: true
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 2; Layout.alignment: Qt.AlignTop
                                }
                                Flow {
                                    Layout.fillWidth: true; spacing: 4
                                    Repeater {
                                        model: benchTeamRow.teamData.subs
                                        delegate: Rectangle {
                                            height: benchRow.implicitHeight + 4
                                            width: benchRow.implicitWidth + 10
                                            radius: 5
                                            color: detailCard.tint(Kirigami.Theme.textColor, 0.05)
                                            RowLayout {
                                                id: benchRow
                                                anchors.centerIn: parent; spacing: 4
                                                Kirigami.Heading { text: modelData.jersey || ""; level: 6; font.pixelSize: 9; color: Kirigami.Theme.disabledTextColor }
                                                Kirigami.Heading { text: shortName(modelData.name || ""); level: 6; font.pixelSize: 10; color: Kirigami.Theme.textColor }
                                                Rectangle {
                                                    visible: modelData.rating !== undefined && modelData.rating !== null
                                                    width: 20; height: 12; radius: 3; color: ratingColor(modelData.rating)
                                                    Kirigami.Heading { anchors.centerIn: parent; text: Number(modelData.rating || 6.0).toFixed(1); font.pixelSize: 8; font.bold: true; color: "white" }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // === EVENTS ===
                    ColumnLayout {
                        id: eventsContent; width: parent.width; spacing: 1
                        Kirigami.Heading {
                            visible: cleanedEvents().length === 0
                            text: "Waiting for kick-off..."; level: 6; color: Kirigami.Theme.disabledTextColor; Layout.alignment: Qt.AlignHCenter
                        }
                        Repeater {
                            model: cleanedEvents()
                            delegate: Item {
                                id: evDelegate
                                Layout.fillWidth: true
                                readonly property bool isGoal: modelData.kind === "goal" || modelData.kind === "owngoal"
                                implicitHeight: (modelData.kind === "period")
                                    ? periodLabel.implicitHeight + 10
                                    : Math.max(26, evRow.implicitHeight + 8)

                                // Goal-row highlight (behind content)
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.leftMargin: -4; anchors.rightMargin: 2
                                    anchors.topMargin: 1; anchors.bottomMargin: 1
                                    visible: isGoal
                                    radius: 6
                                    color: detailCard.tint(detailCard.liveColor, 0.10)
                                }

                                // Period marker (centred, dim)
                                Kirigami.Heading {
                                    id: periodLabel
                                    visible: modelData.kind === "period"
                                    width: parent.width
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.minute ? (modelData.minute + "  ·  " + modelData.text) : modelData.text
                                    level: 6; font.pixelSize: 10; font.italic: true
                                    color: Kirigami.Theme.disabledTextColor
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }

                                // Normal event row: minute · icon · text
                                RowLayout {
                                    id: evRow
                                    visible: modelData.kind !== "period"
                                    width: parent.width
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    Kirigami.Heading {
                                        text: modelData.minute
                                        level: 6; font.pixelSize: 11
                                        font.bold: isGoal
                                        font.features: ({ "tnum": 1 })
                                        color: isGoal ? detailCard.liveColor : Kirigami.Theme.disabledTextColor
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 2.4
                                        horizontalAlignment: Text.AlignRight
                                    }

                                    // Icon slot
                                    Item {
                                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                                        Layout.alignment: Qt.AlignVCenter

                                        // Goal - ball
                                        Text {
                                            anchors.centerIn: parent
                                            visible: evDelegate.isGoal
                                            text: "⚽"
                                            font.pixelSize: 16
                                        }
                                        // Yellow card
                                        Rectangle {
                                            anchors.centerIn: parent
                                            visible: modelData.kind === "yellow"
                                            width: 12; height: 16; radius: 2.5
                                            color: "#f1c40f"; rotation: -8
                                            border.color: Qt.rgba(0, 0, 0, 0.28); border.width: 1
                                        }
                                        // Red card
                                        Rectangle {
                                            anchors.centerIn: parent
                                            visible: modelData.kind === "red"
                                            width: 12; height: 16; radius: 2.5
                                            color: "#e74c3c"; rotation: -8
                                            border.color: Qt.rgba(0, 0, 0, 0.28); border.width: 1
                                        }
                                        // Substitution - in/out arrows
                                        RowLayout {
                                            anchors.centerIn: parent
                                            visible: modelData.kind === "sub"
                                            spacing: 0
                                            Kirigami.Heading { text: "▲"; level: 6; font.pixelSize: 10; color: "#2ecc71" }
                                            Kirigami.Heading { text: "▼"; level: 6; font.pixelSize: 10; color: "#e74c3c" }
                                        }
                                        // Penalty miss / other - neutral dot
                                        Rectangle {
                                            anchors.centerIn: parent
                                            visible: modelData.kind === "other" || modelData.kind === "penmiss"
                                            width: 6; height: 6; radius: 3
                                            color: modelData.kind === "penmiss" ? "#e74c3c" : Kirigami.Theme.disabledTextColor
                                        }
                                    }

                                    Kirigami.Heading {
                                        text: modelData.text
                                        level: 6; font.pixelSize: 11
                                        font.bold: evDelegate.isGoal
                                        color: Kirigami.Theme.textColor
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function getHomeStarters() {
        if (!matchObj || !matchObj.lineups || !matchObj.lineups.home) return [];
        return matchObj.lineups.home.filter(function(p){return p.starter});
    }
    function getAwayStarters() {
        if (!matchObj || !matchObj.lineups || !matchObj.lineups.away) return [];
        return matchObj.lineups.away.filter(function(p){return p.starter});
    }
    function getHomeSubs() {
        if (!matchObj || !matchObj.lineups || !matchObj.lineups.home) return [];
        return matchObj.lineups.home.filter(function(p){return !p.starter});
    }
    function getAwaySubs() {
        if (!matchObj || !matchObj.lineups || !matchObj.lineups.away) return [];
        return matchObj.lineups.away.filter(function(p){return !p.starter});
    }

    // "4-3-3" → [4,3,3] (outfield lines, GK excluded).
    function formationRows(f) {
        if (!f) return [];
        var parts = ("" + f).split("-");
        var rows = [];
        for (var i = 0; i < parts.length; i++) {
            var n = parseInt(parts[i], 10);
            if (!isNaN(n) && n > 0) rows.push(n);
        }
        return rows;
    }

    // Lay one side's starters out on the pitch. Home → bottom half (GK at the
    // very bottom), away → top half mirrored. Returns [{name,jersey,rating,
    // hasRating,xFrac,yFrac,home}].
    function pitchNodesFor(starters, formationStr, isHome) {
        if (!starters || starters.length === 0) return [];
        var outfield = formationRows(formationStr);
        var rows = outfield.length > 0 ? [1].concat(outfield) : [1, 4, 3, 3];
        var nodes = [];
        var idx = 0;
        var numRows = rows.length;
        for (var r = 0; r < numRows && idx < starters.length; r++) {
            var count = rows[r];
            // Last line absorbs any leftover if the formation under-counts.
            if (r === numRows - 1) count = Math.max(count, starters.length - idx);
            var rowPlayers = [];
            for (var c = 0; c < count && idx < starters.length; c++) {
                rowPlayers.push(starters[idx]); idx++;
            }
            var t = (numRows === 1) ? 0 : r / (numRows - 1); // 0 = GK line, 1 = attack
            // Keep each half within [0.05..0.58] / [0.42..0.95] so the two
            // attacking lines never collide on the halfway line.
            var yFrac = isHome ? (0.95 - t * 0.37) : (0.05 + t * 0.37);
            var n = rowPlayers.length;
            for (var k = 0; k < n; k++) {
                var p = rowPlayers[k];
                var xFrac = (k + 1) / (n + 1);
                if (!isHome) xFrac = 1 - xFrac; // mirror so both attack the centre
                var hasR = p.rating !== undefined && p.rating !== null;
                nodes.push({ name: p.name || "", short: shortName(p.name || ""),
                             jersey: p.jersey || "",
                             rating: p.rating, hasRating: hasR,
                             xFrac: xFrac, yFrac: yFrac, home: isHome });
            }
        }
        return nodes;
    }

    // Surname only, for a clean pitch (FotMob/Sofascore style). Keeps a short
    // nobiliary particle attached (van Dijk, de Jong) so it stays recognisable.
    function shortName(full) {
        var parts = ("" + full).trim().split(/\s+/);
        if (parts.length <= 1) return full;
        var last = parts[parts.length - 1];
        var prev = parts[parts.length - 2].toLowerCase();
        if (["van","von","de","da","di","del","der","den","dos","el","al","bin"].indexOf(prev) >= 0)
            return parts[parts.length - 2] + " " + last;
        return last;
    }

    function pitchNodes() {
        var fH = matchObj && matchObj.formations ? matchObj.formations.home : "";
        var fA = matchObj && matchObj.formations ? matchObj.formations.away : "";
        return pitchNodesFor(getHomeStarters(), fH, true)
              .concat(pitchNodesFor(getAwayStarters(), fA, false));
    }
    function getStatsList() {
        if (!matchObj || !matchObj.stats) return [{label:"No data yet",home:0,away:0,percentage:false}];
        var map = {
            "possessionPct":  {label:"Possession %",percentage:true},
            "totalShots":     {label:"Shots",percentage:false},
            "shotsOnTarget":  {label:"Shots on target",percentage:false},
            "corners":        {label:"Corners",percentage:false},
            "yellowCards":    {label:"Yellow cards",percentage:false},
            "redCards":       {label:"Red cards",percentage:false},
            "foulsCommitted": {label:"Fouls",percentage:false},
            "offsides":       {label:"Offsides",percentage:false},
            "totalPasses":    {label:"Passes",percentage:false},
            "tackles":        {label:"Tackles",percentage:false},
            "expectedGoals":  {label:"xG",percentage:false},
        };
        var result = [];
        for (var key in matchObj.stats) {
            if (map[key]) {
                var hv = matchObj.stats[key].homeValue !== undefined ? matchObj.stats[key].homeValue : 0;
                var av = matchObj.stats[key].awayValue !== undefined ? matchObj.stats[key].awayValue : 0;
                if (hv !== 0 || av !== 0) result.push({label:map[key].label,home:hv,away:av,percentage:map[key].percentage});
            }
        }
        if (result.length === 0) return [{label:"No data yet",home:0,away:0,percentage:false}];
        return result;
    }
    function ratingColor(r) {
        var v = r || 6.0;
        if (v >= 8.0) return "#4CAF50";
        if (v >= 6.5) return "#8BC34A";
        if (v >= 5.5) return "#FFC107";
        if (v >= 4.0) return "#FF9800";
        return "#F44336";
    }

    // Classify a key event for its visual icon. Prefer the normalised `type`
    // field (FotMob), fall back to text matching (ESPN's verbose sentences).
    function eventKind(e) {
        var ty = (e && e.type ? ("" + e.type).toLowerCase() : "");
        if (ty === "owngoal") return "owngoal";
        if (ty === "goal") return "goal";
        if (ty === "redcard") return "red";
        if (ty === "yellowcard") return "yellow";
        if (ty === "substitution") return "sub";
        if (ty === "half" || ty === "addedtime" || ty === "halftime" || ty === "fulltime") return "period";
        if (ty === "var") return "minor";

        var t = (e && e.text ? e.text : "").toLowerCase();
        if (/own goal|owngoal|selvmål/.test(t)) return "owngoal";
        if (/goal|\bmål\b/.test(t)) return "goal";
        if (/second yellow|red card|rødt kort/.test(t)) return "red";
        if (/yellow card|gult kort/.test(t)) return "yellow";
        if (/substitut|subbed|\breplaced\b|comes on|bytte/.test(t)) return "sub";
        if (/penalty (missed|saved)|misses the penalty|straffe.*(brent|reddet)/.test(t)) return "penmiss";
        if (/half ends|half begins|half[- ]?time|full[- ]?time|match ends|kick-?off|second half|first half|end of|begins|extra time|avspark|omgang|pause|slutt/.test(t)) return "period";
        if (/delay|drinks break|cooling break|\bvar\b|review|avbrudd/.test(t)) return "minor";
        return "other";
    }

    // Cleaned, display-ready event list: drop empty + noise (delays/VAR) events.
    function cleanedEvents() {
        if (!matchObj || !matchObj.keyEvents) return [];
        var out = [];
        for (var i = 0; i < matchObj.keyEvents.length; i++) {
            var e = matchObj.keyEvents[i];
            // Coerce to String: FotMob's clock/text can arrive as numbers, and
            // (number).trim() throws "trim is not a function", which cascades and
            // breaks the whole popup render.
            var txt = String(e.text || "").trim();
            if (!txt) continue;
            var kind = eventKind(e);
            if (kind === "minor") continue;
            out.push({ minute: String(e.clock || "").trim(), text: txt, kind: kind });
        }
        return out;
    }

    // Split the generated summary into a narrative line + a goal-scorer list.
    function summaryNarrative() {
        var s = matchObj && matchObj.summary ? matchObj.summary : "";
        var i = s.indexOf("Goals:");
        return (i >= 0 ? s.substring(0, i) : s).trim();
    }
    function summaryGoalList() {
        var s = matchObj && matchObj.summary ? matchObj.summary : "";
        var marker = "Goals:";
        var i = s.indexOf(marker);
        if (i < 0) return [];
        var g = s.substring(i + marker.length).replace(/\.\s*$/, "").trim();
        if (!g) return [];
        var parts = g.split(",");
        var out = [];
        for (var j = 0; j < parts.length; j++) {
            var p = parts[j].trim();
            if (p) out.push(p);
        }
        return out;
    }
}
