import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml
import QtMultimedia

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

import "Theme.js" as Theme

PlasmoidItem {
    id: root

    clip: true
    preferredRepresentation: compactRepresentation

    property int refreshInterval: Plasmoid.configuration.refreshInterval || 30
    property string followedTeams: Plasmoid.configuration.followedTeams || ""
    property string selectedLeagues: Plasmoid.configuration.selectedLeagues || ""
    property bool playSounds: Plasmoid.configuration.playSounds !== undefined ? Plasmoid.configuration.playSounds : true
    property string notificationSound: Plasmoid.configuration.notificationSound || "pling.wav"
    property string soundOutputDevice: Plasmoid.configuration.soundOutputDevice || ""
    property string trayDisplayMode: Plasmoid.configuration.trayDisplayMode || "flagText"
    property string tickerDisplayMode: Plasmoid.configuration.tickerDisplayMode || "flagText"
    property int tickerMatchCount: Plasmoid.configuration.tickerMatchCount || 3
    property int tickerSpeed: Plasmoid.configuration.tickerSpeed || 5
    property int maxVisibleMatches: Plasmoid.configuration.maxVisibleMatches || 10

    // Style group 1 — RESULT + TIME (score, match minute, live dot, stripe).
    property color liveColor: Plasmoid.configuration.liveColor || Kirigami.Theme.positiveTextColor
    property bool liveOutline: Plasmoid.configuration.liveColorOutline === true
    property bool liveShadow: Plasmoid.configuration.liveColorShadow === true
    // Style group 2 — TEAM NAME (home/away abbreviations), independent setup.
    property color teamColor: Plasmoid.configuration.teamColor || Kirigami.Theme.textColor
    property bool teamOutline: Plasmoid.configuration.teamColorOutline === true
    property bool teamShadow: Plasmoid.configuration.teamColorShadow === true

    // LLM commentator settings — applied to the systemd service when the user
    // presses "Apply" (config changes → these properties change → run helper).
    property bool   commentatorEnabled: Plasmoid.configuration.commentatorEnabled
    property string commentatorModel:   Plasmoid.configuration.commentatorModel || "gemma4:12b"
    // How live commentary is presented: both | sound | text
    property string commentaryMode:     Plasmoid.configuration.commentaryMode || "both"
    readonly property string llmHelper: "$HOME/.local/bin/fotball-llm-ctl.sh"
    readonly property string ttsHelper: "$HOME/.local/bin/fotball-tts.sh"
    property var lastSpokenAi: ({})  // match id → last spoken commentary id

    // Speak new AI commentary aloud (when the mode includes sound). First sighting
    // of a match's commentary is baselined silently so startup doesn't replay it.
    function speakNewCommentary(matches) {
        if (commentaryMode === "text") return;
        for (var i = 0; i < matches.length; i++) {
            var m = matches[i];
            if (m.status !== "in" && m.status !== "ht") continue;
            if (!m.aiCommentary) continue;
            var id = "" + (m.aiCommentaryId || m.summary || "");
            if (!id) continue;
            var prev = lastSpokenAi[m.id];
            lastSpokenAi[m.id] = id;
            if (prev === undefined || prev === id) continue; // baseline / unchanged
            llmCtl.run(ttsHelper + " " + m.id + " " + JSON.stringify(soundOutputDevice || ""));
        }
    }
    onCommentatorEnabledChanged: llmCtl.run(llmHelper + (commentatorEnabled ? " enable" : " disable"))
    onCommentatorModelChanged: if (commentatorModel) llmCtl.run(llmHelper + " set-model " + commentatorModel)

    property string apiUrl: "http://127.0.0.1:9876/matches.json"
    property string tournamentUrl: "http://127.0.0.1:9876/tournament.json"
    property string leaguesUrl: "http://127.0.0.1:9876/leagues.json"
    property var matchData: ({ matches: [], updated: "" })
    // Monotonic counter bumped on every successful matches load. Views reference
    // it so that score bindings re-evaluate even when the match COUNT is unchanged
    // (a live goal changes homeScore but not displayMatches.length → the integer
    // Repeater model never fires; reading dataVersion forces the refresh).
    property int dataVersion: 0
    property var tournamentData: ({})
    property var leaguesData: ({ leagues: {} })
    property bool loading: false
    property bool openTournamentView: false

    // Active league/tournament for theming
    property string activeLeagueId: {
        if (tournamentData && tournamentData.tournamentId) return tournamentData.tournamentId;
        var matches = getDisplayMatches();
        for (var i = 0; i < matches.length; i++) {
            if (matches[i].status === "in" || matches[i].status === "ht") return matches[i].leagueId;
        }
        if (matches.length > 0) return matches[0].leagueId;
        return "";
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.tournamentData && root.tournamentData.tournamentName
                  ? "Open " + root.tournamentData.tournamentName + " 2026"
                  : "Open tournament window"
            icon.name: "trophy"
            onTriggered: {
                root.openTournamentView = true;
                root.expanded = true;
            }
        },
        PlasmaCore.Action {
            text: "Refresh now"
            icon.name: "view-refresh"
            onTriggered: root.loadAllData()
        },
        PlasmaCore.Action {
            // Support page — shared GaimsDev PayPal across all our apps.
            text: "Support FootballTray…"
            icon.name: "emblem-favorite"
            onTriggered: llmCtl.run(llmHelper + " open-url "
                                    + JSON.stringify("https://paypal.me/gaimsdev?country.x=NO&locale.x=no_NO"))
        }
    ]

    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}

    MediaPlayer {
        id: audioPlayer
        audioOutput: AudioOutput {
            id: audioOut
        }
    }

    MediaDevices {
        id: mediaDevices
    }

    // Runs the LLM control helper (enable/disable/set-model) on "Apply".
    // run(cmd, cb) — cb is optional; called with trimmed stdout.
    Plasma5Support.DataSource {
        id: llmCtl
        engine: "executable"
        connectedSources: []
        property int seq: 0
        property var cbs: ({})
        onNewData: function(source, data) {
            var out = (data && data["stdout"] !== undefined) ? ("" + data["stdout"]) : "";
            disconnectSource(source);
            var cb = cbs[source]; if (cb) { delete cbs[source]; cb(out.trim()); }
        }
        function run(cmd, cb) { seq += 1; var src = cmd + " ; : " + seq; if (cb) cbs[src] = cb; connectSource(src); }
    }

    // Active commentator style's accent colour (used only for the live-commentary
    // marker, so it never overrides the user's chosen live/team colours).
    property color commentatorAccent: liveColor
    function refreshCommentatorAccent() {
        llmCtl.run(llmHelper + " status", function(out) {
            try { var s = JSON.parse(out); if (s.accent) commentatorAccent = s.accent; } catch (e) {}
        });
    }
    onExpandedChanged: if (expanded) refreshCommentatorAccent()

    onSoundOutputDeviceChanged: updateAudioDevice()

    function updateAudioDevice() {
        if (!soundOutputDevice) {
            audioOut.device = mediaDevices.defaultAudioOutput;
            return;
        }
        for (var i = 0; i < mediaDevices.audioOutputs.length; i++) {
            var dev = mediaDevices.audioOutputs[i];
            // dev.id is a QByteArray — strict === against the saved JS string
            // never matches, so coerce both sides with String() (that bug made
            // every selection silently fall back to the default device).
            if (String(dev.id) === String(soundOutputDevice)
                    || String(dev.description) === String(soundOutputDevice)) {
                audioOut.device = dev;
                return;
            }
        }
        audioOut.device = mediaDevices.defaultAudioOutput;
    }

    readonly property string playHelper: "$HOME/.local/bin/fotball-play.sh"

    function playSoundFile(file) {
        if (!file) return;
        // Route through paplay --device (reliable on PipeWire); QtMultimedia's
        // AudioOutput.device switching did not actually move the output.
        llmCtl.run(playHelper + " " + file + " " + JSON.stringify(soundOutputDevice || ""));
    }

    // Goal sound — uses the configured sound for followed vs other teams
    // (previously this was hardcoded to pling.wav, ignoring the settings).
    function playGoalSound(isFollowed) {
        if (!Plasmoid.configuration.playSounds) return;
        playSoundFile(isFollowed ? (Plasmoid.configuration.soundFollowed || "cheer.wav")
                                 : (Plasmoid.configuration.soundOther || "whistle.wav"));
    }

    // Sound for a serious match event (red card, …).
    function playEventSound(file) {
        if (!Plasmoid.configuration.playEventSounds) return;
        playSoundFile(file || "whistle.wav");
    }

    function isFollowedMatch(m) {
        var teamsStr = (followedTeams || "").toLowerCase();
        if (!teamsStr) return false;
        var teams = teamsStr.split(",").map(function(s){return s.trim()}).filter(function(s){return s.length>0});
        var h = (m.homeTeam || "").toLowerCase();
        var a = (m.awayTeam || "").toLowerCase();
        var ha = (m.homeAbbrev || "").toLowerCase();
        var aa = (m.awayAbbrev || "").toLowerCase();
        for (var i = 0; i < teams.length; i++) {
            var t = teams[i];
            if (h.indexOf(t) >= 0 || a.indexOf(t) >= 0 || ha === t || aa === t) return true;
        }
        return false;
    }

    Timer {
        id: refreshTimer
        interval: Math.max(refreshInterval, 5) * 1000
        running: true
        repeat: true
        onTriggered: loadAllData()
    }

    Component.onCompleted: {
        loadAllData();
        refreshCommentatorAccent();
    }

    property var lastGoalCounts: ({})
    property bool showingGoalBanner: false
    property string goalBannerText: ""
    property int goalBannerTimer: 0

    function checkForNewGoals(matchesList) {
        var newCounts = {};
        var newlyScored = [];

        for (var i=0; i<matchesList.length; i++) {
            var m = matchesList[i];
            if (m.status !== "in") continue;

            var matchId = m.id;
            var currentGoals = m.homeScore + m.awayScore;
            newCounts[matchId] = currentGoals;

            if (lastGoalCounts[matchId] !== undefined && currentGoals > lastGoalCounts[matchId]) {
                newlyScored.push(m);
            }
        }

        if (newlyScored.length > 0) {
            var m = newlyScored[0];
            var h = m.homeAbbrev || m.homeTeam.substring(0,3).toUpperCase();
            var a = m.awayAbbrev || m.awayTeam.substring(0,3).toUpperCase();
            goalBannerText = "⚽ GOOOAL! " + h + " " + m.homeScore + " - " + m.awayScore + " " + a + " !!!";
            showingGoalBanner = true;
            goalBannerTimer = 2; playGoalSound(isFollowedMatch(m));
        } else if (goalBannerTimer > 0) {
            goalBannerTimer--;
            if (goalBannerTimer <= 0) showingGoalBanner = false;
        }

        lastGoalCounts = newCounts;
    }

    property var lastRedCardCounts: ({})

    function countRedCards(m) {
        if (!m || !m.keyEvents) return 0;
        var c = 0;
        for (var i = 0; i < m.keyEvents.length; i++) {
            var t = ("" + (m.keyEvents[i].type || "")).toLowerCase();
            var txt = ("" + (m.keyEvents[i].text || "")).toLowerCase();
            if (t === "redcard" || /red card|rødt kort/.test(txt)) c++;
        }
        return c;
    }

    function checkForNewRedCards(matchesList) {
        var newCounts = {};
        var triggered = false;
        for (var i = 0; i < matchesList.length; i++) {
            var m = matchesList[i];
            if (m.status !== "in" && m.status !== "ht") continue;
            var rc = countRedCards(m);
            newCounts[m.id] = rc;
            if (lastRedCardCounts[m.id] !== undefined && rc > lastRedCardCounts[m.id]) triggered = true;
        }
        if (triggered) playEventSound(Plasmoid.configuration.soundRedCard || "whistle.wav");
        lastRedCardCounts = newCounts;
    }

    function loadAllData() {
        loadJson(apiUrl, function(data) {
            if (data && data.matches) {
                matchData = data;
                dataVersion++;
                checkForNewGoals(data.matches);
                checkForNewRedCards(data.matches);
                speakNewCommentary(data.matches);
            }
        });
        loadJson(tournamentUrl, function(data) {
            tournamentData = data || {};
        });
        loadJson(leaguesUrl, function(data) {
            leaguesData = data || { leagues: {} };
        });
    }

    function loadJson(url, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        callback(JSON.parse(xhr.responseText));
                    } catch(e) {
                        console.warn("FotballTray: JSON parse error", e);
                    }
                }
            }
        };
        xhr.send();
    }

    function themeFor(leagueId) {
        return Theme.themeFor(leagueId || activeLeagueId);
    }

    function primaryColor() { return Theme.primaryColor(activeLeagueId); }
    function secondaryColor() { return Theme.secondaryColor(activeLeagueId); }
    function accentColor() { return Theme.accentColor(activeLeagueId); }

    function shouldShowMatch(m) {
        var teamsStr = (followedTeams || "").toLowerCase();
        var leaguesStr = (selectedLeagues || "").toLowerCase();

        var teams = teamsStr ? teamsStr.split(",").map(function(s){return s.trim()}).filter(function(s){return s.length>0}) : [];
        var leagues = leaguesStr ? leaguesStr.split(",").map(function(s){return s.trim()}).filter(function(s){return s.length>0}) : [];

        if (teams.length === 0 && leagues.length === 0) return true;

        for (var i=0; i<leagues.length; i++) {
            if (m.leagueId.toLowerCase() === leagues[i] || m.league.toLowerCase().indexOf(leagues[i]) >= 0) return true;
        }

        var h = (m.homeTeam || "").toLowerCase();
        var a = (m.awayTeam || "").toLowerCase();
        var ha = (m.homeAbbrev || "").toLowerCase();
        var aa = (m.awayAbbrev || "").toLowerCase();

        for (var j=0; j<teams.length; j++) {
            var t = teams[j];
            if (h.indexOf(t) >= 0 || a.indexOf(t) >= 0 || ha === t || aa === t) return true;
        }

        return false;
    }

    function getLiveCount() {
        var count = 0
        if (matchData && matchData.matches) {
            for (var i = 0; i < matchData.matches.length; i++) {
                if (matchData.matches[i].status === "in" || matchData.matches[i].status === "ht")
                    count++
            }
        }
        return count
    }

    function getDisplayMatches() {
        if (!matchData || !matchData.matches) return [];
        var teamsStr = (followedTeams || "").trim();
        var leaguesStr = (selectedLeagues || "").trim();
        var all = matchData.matches;
        if (teamsStr === "" && leaguesStr === "") return all.slice(0, maxVisibleMatches * 2);
        return all.filter(shouldShowMatch).slice(0, maxVisibleMatches * 2);
    }

    function formatKickoffTime(isoString) {
        if (!isoString) return "";
        var d = new Date(isoString);
        if (isNaN(d.getTime())) return "";
        var now = new Date();
        if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "HH:mm");
        return Qt.formatDate(d, "d. MMM") + " " + Qt.formatTime(d, "HH:mm");
    }
}
