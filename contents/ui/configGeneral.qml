import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support
import "components"

KCM.SimpleKCM {
    id: root

    property alias cfg_onboardingDone: onboardingDoneCheck.checked
    property alias cfg_refreshInterval: refreshSpin.value
    property alias cfg_followedTeams: teamSelector.selectedTeams
    property alias cfg_selectedLeagues: leagueValue.text
    property alias cfg_playSounds: soundsCheck.checked
    property alias cfg_soundFollowed: soundFollowedCombo.currentValue
    property alias cfg_soundOther: soundOtherCombo.currentValue
    property alias cfg_soundRedCard: soundRedCardCombo.currentValue
    property alias cfg_playEventSounds: eventSoundsCheck.checked
    property alias cfg_soundOutputDevice: deviceCombo.currentValue
    property alias cfg_trayDisplayMode: trayModeGroup.checkedMode
    property alias cfg_tickerDisplayMode: tickerModeGroup.checkedMode
    property alias cfg_tickerMatchCount: tickerCountSpin.value
    property alias cfg_tickerSpeed: tickerSpeedSpin.value
    property alias cfg_maxVisibleMatches: maxMatchesSpin.value
    property alias cfg_liveColor: liveColorButton.color
    property alias cfg_liveColorOutline: outlineCheck.checked
    property alias cfg_liveColorShadow: liveShadowCheck.checked
    property alias cfg_teamColor: teamColorButton.color
    property alias cfg_teamColorOutline: teamOutlineCheck.checked
    property alias cfg_teamColorShadow: teamShadowCheck.checked
    property alias cfg_commentatorEnabled: commentatorEnabledCheck.checked
    property alias cfg_commentatorModel: llmModelCombo.editText
    property alias cfg_commentaryMode: commentaryModeCombo.currentValue

    property var availableTeams: []
    property var availableLeagues: []

    // ── LLM commentator management (via fotball-llm-ctl.sh) ────────────────────
    property string llmHelper: "$HOME/.local/bin/fotball-llm-ctl.sh"
    property bool   llmOllamaInstalled: false
    property bool   llmOllamaRunning:   false
    property bool   llmModelInstalled:  false
    property bool   llmServiceActive:   false
    property bool   llmServiceEnabled:  false
    property string llmModel:  "gemma4:12b"
    property var    llmModels: []
    property string llmBusy:   ""   // non-empty while an action runs
    property string llmOutput: ""
    // Cloud backend (OpenAI-compatible). backend is "ollama" or "cloud".
    property string llmBackend:   "ollama"
    property string llmCloudBase:  ""
    property string llmCloudModel: ""
    // Commentator style profiles (plugin system).
    property var    llmStyles: []
    property string llmStyle:  "british"

    Plasma5Support.DataSource {
        id: llmExec
        engine: "executable"
        connectedSources: []
        property int seq: 0
        property var cbs: ({})
        onNewData: function(source, data) {
            var out = (data && data["stdout"] !== undefined) ? ("" + data["stdout"]) : "";
            disconnectSource(source);
            var cb = cbs[source];
            if (cb) { delete cbs[source]; cb(out.trim()); }
        }
        function exec(cmd, cb) {
            seq += 1;
            var src = cmd + " ; : " + seq;   // unique source so repeats re-run
            if (cb) cbs[src] = cb;
            connectSource(src);
        }
    }

    function llmRefresh() {
        llmExec.exec(llmHelper + " status", function(out) {
            try {
                var s = JSON.parse(out);
                llmOllamaInstalled = !!s.ollamaInstalled;
                llmOllamaRunning   = !!s.ollamaRunning;
                llmModelInstalled  = !!s.modelInstalled;
                llmServiceActive   = !!s.serviceActive;
                llmServiceEnabled  = !!s.serviceEnabled;
                if (s.model) llmModel = s.model;
                llmModels = ("" + (s.models || "")).split(",").filter(function(x){ return x.length > 0; });
                llmBackend   = s.backend || "ollama";
                llmCloudBase  = s.cloudBase  || "";
                llmCloudModel = s.cloudModel || "";
                llmStyle      = s.style || "british";
            } catch (e) {
                llmOutput = "Could not read LLM status (is the helper installed?)";
            }
        });
    }

    // Load the installed commentator style profiles.
    function loadStyles() {
        llmExec.exec(llmHelper + " list-styles", function(out) {
            try { llmStyles = JSON.parse(out) || []; } catch (e) { llmStyles = []; }
        });
    }

    // Switch the active commentator style (applies immediately).
    function setStyle(id) {
        if (!id || id === llmStyle) return;
        llmAction("set-style " + id, "Switching commentator style…");
    }

    // Open a provider's free-key signup page in the browser. Routed through the
    // helper's `open-key` (xdg-open) because Qt.openUrlExternally is unreliable
    // inside the Plasma config dialog.
    function llmOpenKeyPage(provider) {
        llmOutput = "Opening the sign-up page…";
        llmExec.exec(llmHelper + " open-key " + provider, function(out) {
            if (out && out.indexOf("http") === 0) {
                llmOutput = "Opened " + out + " in your browser.";
            } else {
                llmOutput = "Could not open a browser automatically — visit the provider's key page manually.";
            }
        });
    }

    // Test, then (on success) switch the commentator to the cloud backend.
    function llmApplyCloud(provider, key, model) {
        if (!key) { llmOutput = "Paste your free API key first."; return; }
        var q = function(s){ return JSON.stringify(s); };
        var mdl = model && model.length ? model : "auto";
        llmBusy = "Testing cloud key…"; llmOutput = "";
        llmExec.exec(llmHelper + " test-cloud " + q(provider) + " " + q(key) + " " + q(mdl), function(out) {
            llmOutput = out;
            if (out.indexOf("DONE:") >= 0) {
                llmBusy = "Saving cloud backend…";
                llmExec.exec(llmHelper + " set-cloud " + q(provider) + " " + q(key) + " " + q(mdl), function(o2) {
                    llmBusy = ""; llmOutput = out.split("\n")[0] + "  ✓ saved"; llmRefresh();
                });
            } else {
                llmBusy = "";   // test failed; keep the failure message
            }
        });
    }

    function llmAction(args, label) {
        llmBusy = label;
        llmOutput = "";
        llmExec.exec(llmHelper + " " + args, function(out) {
            llmBusy = "";
            llmOutput = out;
            llmRefresh();
        });
    }

    MediaDevices { id: mediaDevices }

    // Preview player for the "test sound" buttons.
    MediaPlayer {
        id: testPlayer
        audioOutput: AudioOutput { id: testAudioOut }
    }
    function resolveTestDevice() {
        var sel = deviceCombo.currentValue;
        if (!sel) return mediaDevices.defaultAudioOutput;
        for (var i = 0; i < mediaDevices.audioOutputs.length; i++) {
            var dev = mediaDevices.audioOutputs[i];
            if (String(dev.id) === String(sel) || String(dev.description) === String(sel))
                return dev;
        }
        return mediaDevices.defaultAudioOutput;
    }

    function playTest(file) {
        if (!file) return;
        // Route through paplay --device (reliable) so Test plays on the selected
        // device — matches how the widget plays sounds at runtime.
        llmExec.exec("$HOME/.local/bin/fotball-play.sh " + file + " "
                     + JSON.stringify(deviceCombo.currentValue || ""));
    }

    Component.onCompleted: {
        loadTeams();
        loadLeagues();
        llmRefresh();
        loadStyles();
    }

    function loadTeams() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "http://127.0.0.1:9876/teams.json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    if (data && data.teams) root.availableTeams = data.teams;
                } catch (e) {}
            }
        };
        xhr.send();
    }

    function loadLeagues() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "http://127.0.0.1:9876/leagues.json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    if (data && data.leagues) {
                        var list = [];
                        for (var lid in data.leagues) list.push({ id: lid, name: data.leagues[lid].name });
                        list.sort(function(a, b) { return a.name.localeCompare(b.name); });
                        root.availableLeagues = list;
                    }
                } catch (e) {}
            }
        };
        xhr.send();
    }

    function isLeagueSelected(lid) {
        var s = cfg_selectedLeagues || "";
        var parts = s.split(",").map(function(x){return x.trim();}).filter(function(x){return x.length>0;});
        return parts.indexOf(lid) >= 0;
    }

    function toggleLeague(lid) {
        var parts = (cfg_selectedLeagues || "").split(",").map(function(x){return x.trim();}).filter(function(x){return x.length>0;});
        var idx = parts.indexOf(lid);
        if (idx >= 0) parts.splice(idx, 1); else parts.push(lid);
        cfg_selectedLeagues = parts.join(", ");
    }

    ColumnLayout {
        width: parent.width
        spacing: Kirigami.Units.largeSpacing

        // ── Category tabs (Tactics Board) ──────────────────────────────────
        TabBar {
            id: catTabs
            Layout.fillWidth: true
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            TabButton { text: "Follow";     icon.name: "favorite" }
            TabButton { text: "Appearance"; icon.name: "color-management" }
            TabButton { text: "Sound";      icon.name: "audio-volume-high" }
            TabButton { text: "Commentary"; icon.name: "text-speak" }
            TabButton { text: "General";    icon.name: "configure" }
        }

        StackLayout {
            Layout.fillWidth: true
            // Tab order (Follow, Appearance, Sound, Commentary, General) maps to
            // the FormLayouts below, whose source order is General-first; remap so
            // "Follow" (the last FormLayout) shows first.
            currentIndex: [4, 1, 2, 3, 0][catTabs.currentIndex]

            // ===== FormLayout 0: General =====
            Kirigami.FormLayout {
                Layout.fillWidth: true

        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            text: "General"
            level: 3
        }

        // Hidden control backing cfg_onboardingDone (the welcome-tour flag).
        PlasmaComponents3.CheckBox { id: onboardingDoneCheck; visible: false }

        // Replay the first-run welcome tour.
        RowLayout {
            Kirigami.FormData.label: "Welcome tour:"
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.Button {
                text: "Replay welcome tour"
                icon.name: "help-hint"
                enabled: onboardingDoneCheck.checked
                onClicked: onboardingDoneCheck.checked = false
            }
            PlasmaComponents3.Label {
                text: onboardingDoneCheck.checked
                    ? "Shows next time you open the popup (after Apply)."
                    : "Will show next time you open the popup."
                color: Kirigami.Theme.disabledTextColor
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Refresh every:"
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.SpinBox {
                id: refreshSpin
                from: 5; to: 120; stepSize: 5
            }
            Kirigami.Heading {
                text: "seconds"
                level: 6; color: Kirigami.Theme.disabledTextColor
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Max visible matches:"
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.SpinBox {
                id: maxMatchesSpin
                from: 1; to: 50
            }
        }

            } // ===== end FormLayout 0 (General) =====

            // ===== FormLayout 1: Appearance + System tray =====
            Kirigami.FormLayout {
                Layout.fillWidth: true

        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            text: "Appearance"
            level: 3
        }

        // ── Style group 1: RESULT + TIME ──────────────────────────────────
        RowLayout {
            Kirigami.FormData.label: "Result/time colour:"
            spacing: Kirigami.Units.smallSpacing

            // Canonical Plasma colour control — backs cfg_liveColor and saves
            // reliably (alias to a custom property did NOT persist).
            KQuickControls.ColorButton {
                id: liveColorButton
                dialogTitle: "Choose result/time colour"
                showAlphaChannel: false
            }

            // Quick presets
            Repeater {
                model: ["#2ecc71", "#3498db", "#e74c3c", "#f39c12", "#9b59b6", "#1abc9c", "#ffffff"]
                Rectangle {
                    width: Kirigami.Units.gridUnit * 1.3
                    height: Kirigami.Units.gridUnit * 1.3
                    radius: width / 2
                    color: modelData
                    border.color: (Qt.colorEqual(liveColorButton.color, modelData))
                        ? Kirigami.Theme.textColor
                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                    border.width: (Qt.colorEqual(liveColorButton.color, modelData)) ? 2 : 1
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cfg_liveColor = modelData
                    }
                }
            }

            PlasmaComponents3.Button {
                text: "Reset"
                icon.name: "edit-undo"
                onClicked: cfg_liveColor = "#2ecc71"
            }
        }

        PlasmaComponents3.CheckBox {
            id: outlineCheck
            Kirigami.FormData.label: "Outline around result/time:"
            text: "Thin outline around result and time (better contrast on the panel)"
        }

        PlasmaComponents3.CheckBox {
            id: liveShadowCheck
            Kirigami.FormData.label: "Shadow behind result/time:"
            text: "Soft drop shadow behind the result and time (adds depth)"
        }

        // ── Style group 2: TEAM NAME ──────────────────────────────────────
        RowLayout {
            Kirigami.FormData.label: "Team name colour:"
            spacing: Kirigami.Units.smallSpacing

            KQuickControls.ColorButton {
                id: teamColorButton
                dialogTitle: "Choose team name colour"
                showAlphaChannel: false
            }

            Repeater {
                model: ["#ffffff", "#000000", "#2ecc71", "#3498db", "#e74c3c", "#f39c12", "#f1c40f"]
                Rectangle {
                    width: Kirigami.Units.gridUnit * 1.3
                    height: Kirigami.Units.gridUnit * 1.3
                    radius: width / 2
                    color: modelData
                    border.color: (Qt.colorEqual(teamColorButton.color, modelData))
                        ? Kirigami.Theme.textColor
                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                    border.width: (Qt.colorEqual(teamColorButton.color, modelData)) ? 2 : 1
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cfg_teamColor = modelData
                    }
                }
            }

            PlasmaComponents3.Button {
                text: "Reset"
                icon.name: "edit-undo"
                onClicked: cfg_teamColor = "#ffffff"
            }
        }

        PlasmaComponents3.CheckBox {
            id: teamOutlineCheck
            Kirigami.FormData.label: "Outline around team name:"
            text: "Thin outline around the team name (better contrast on the panel)"
        }

        PlasmaComponents3.CheckBox {
            id: teamShadowCheck
            Kirigami.FormData.label: "Shadow behind team name:"
            text: "Soft drop shadow behind the team name (adds depth)"
        }

        // Live preview on a panel-like background so the outlines are visible.
        // Mirrors the real tray: team name | score | time, each in its own group.
        RowLayout {
            Kirigami.FormData.label: "Preview:"
            Rectangle {
                radius: 6
                color: "#7ec8e3"   // sky-blue, like the user's panel
                implicitWidth: prevRow.implicitWidth + 20
                implicitHeight: prevRow.implicitHeight + 10
                RowLayout {
                    id: prevRow
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: liveColorButton.color
                        border.color: "black"
                        border.width: outlineCheck.checked ? 1 : 0
                        Layout.alignment: Qt.AlignVCenter
                    }
                    OutlinedLabel {  // team name — group 2
                        text: "NOR"
                        level: 4
                        color: teamColorButton.color
                        outlined: teamOutlineCheck.checked
                        shadow: teamShadowCheck.checked
                    }
                    OutlinedLabel {  // score + time — group 1
                        text: "2 – 1   67′"
                        level: 4
                        color: liveColorButton.color
                        outlined: outlineCheck.checked
                        shadow: liveShadowCheck.checked
                    }
                }
            }
        }

        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            text: "System tray"
            level: 3
        }

        SettingCard {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true

            ColumnLayout {
                width: parent.width
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    text: "Tray display mode"
                    level: 4; font.bold: true
                }
                Kirigami.Heading {
                    text: "Choose how the match looks in the system tray."
                    level: 6; color: Kirigami.Theme.disabledTextColor; wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                QtObject { id: trayModeGroup; property string checkedMode: "flagText" }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    DisplayModeButton {
                        text: "Text only"
                        subText: "NOR 2-1 SWE"
                        iconText: "Aa"
                        checked: cfg_trayDisplayMode === "text"
                        onClicked: cfg_trayDisplayMode = "text"
                    }
                    DisplayModeButton {
                        text: "Flag + text"
                        subText: "NOR 2-1 SWE"
                        iconText: "🇳🇴"
                        checked: cfg_trayDisplayMode === "flagText"
                        onClicked: cfg_trayDisplayMode = "flagText"
                    }
                    DisplayModeButton {
                        text: "Flag only"
                        subText: "2-1"
                        iconText: "🇳🇴"
                        checked: cfg_trayDisplayMode === "flagOnly"
                        onClicked: cfg_trayDisplayMode = "flagOnly"
                    }
                }

                TrayPreview {
                    mode: cfg_trayDisplayMode
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        SettingCard {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true

            ColumnLayout {
                width: parent.width
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    text: "Ticker / banner scroll"
                    level: 4; font.bold: true
                }

                QtObject { id: tickerModeGroup; property string checkedMode: "flagText" }

                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    DisplayModeButton {
                        text: "Score only"
                        subText: "2-1"
                        iconText: "0-0"
                        checked: cfg_tickerDisplayMode === "scoreOnly"
                        onClicked: cfg_tickerDisplayMode = "scoreOnly"
                    }
                    DisplayModeButton {
                        text: "Text only"
                        subText: "NOR 2-1 SWE"
                        iconText: "NOR"
                        checked: cfg_tickerDisplayMode === "text"
                        onClicked: cfg_tickerDisplayMode = "text"
                    }
                    DisplayModeButton {
                        text: "Flag + text"
                        subText: "NOR 2-1 SWE"
                        iconText: "🇳🇴"
                        checked: cfg_tickerDisplayMode === "flagText"
                        onClicked: cfg_tickerDisplayMode = "flagText"
                    }
                    DisplayModeButton {
                        text: "Full name"
                        subText: "Norway 2-1 Sweden"
                        iconText: "Nor"
                        checked: cfg_tickerDisplayMode === "fullName"
                        onClicked: cfg_tickerDisplayMode = "fullName"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    // NB: FormData.label only works on direct FormLayout children,
                    // so use explicit labels for these nested controls.
                    ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing / 2
                        PlasmaComponents3.Label { text: "Match count:" }
                        PlasmaComponents3.SpinBox {
                            id: tickerCountSpin
                            from: 1; to: 10
                        }
                    }
                    ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing / 2
                        PlasmaComponents3.Label { text: "Speed:" }
                        PlasmaComponents3.Slider {
                            id: tickerSpeedSpin
                            from: 1; to: 10
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                        }
                    }
                }
            }
        }

            } // ===== end FormLayout 1 (Appearance + System tray) =====

            // ===== FormLayout 2: Sound =====
            Kirigami.FormLayout {
                Layout.fillWidth: true

        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            text: "Sound alerts"
            level: 3
        }

        PlasmaComponents3.CheckBox {
            id: soundsCheck
            text: "Play a sound on goals"
        }

        RowLayout {
            Kirigami.FormData.label: "Sound for your teams:"
            spacing: Kirigami.Units.smallSpacing
            enabled: soundsCheck.checked
            PlasmaComponents3.ComboBox {
                id: soundFollowedCombo
                model: [
                    { text: "Crowd cheer", value: "cheer.wav" },
                    { text: "Tippekampen bong", value: "bong.wav" },
                    { text: "Goal whistle", value: "whistle.wav" },
                    { text: "Referee whistle", value: "whistle_match.wav" },
                    { text: "Soft ping", value: "pling.wav" }
                ]
                textRole: "text"; valueRole: "value"
                // currentValue is read-only; restore saved selection via index
                Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_soundFollowed))
            }
            PlasmaComponents3.Button {
                icon.name: "media-playback-start"
                text: "Test"
                onClicked: playTest(soundFollowedCombo.currentValue)
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Sound for other teams:"
            spacing: Kirigami.Units.smallSpacing
            enabled: soundsCheck.checked
            PlasmaComponents3.ComboBox {
                id: soundOtherCombo
                model: [
                    { text: "Soft ping", value: "pling.wav" },
                    { text: "Tippekampen bong", value: "bong.wav" },
                    { text: "Crowd cheer", value: "cheer.wav" },
                    { text: "Goal whistle", value: "whistle.wav" },
                    { text: "Referee whistle", value: "whistle_match.wav" }
                ]
                textRole: "text"; valueRole: "value"
                Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_soundOther))
            }
            PlasmaComponents3.Button {
                icon.name: "media-playback-start"
                text: "Test"
                onClicked: playTest(soundOtherCombo.currentValue)
            }
        }

        // ── Sound for serious events ───────────────────────────────────────
        PlasmaComponents3.CheckBox {
            id: eventSoundsCheck
            text: "Play a sound on serious events (red card)"
        }

        RowLayout {
            Kirigami.FormData.label: "Sound on red card:"
            spacing: Kirigami.Units.smallSpacing
            enabled: eventSoundsCheck.checked
            PlasmaComponents3.ComboBox {
                id: soundRedCardCombo
                model: [
                    { text: "Referee whistle", value: "whistle_match.wav" },
                    { text: "Goal whistle", value: "whistle.wav" },
                    { text: "Tippekampen bong", value: "bong.wav" },
                    { text: "Soft ping", value: "pling.wav" }
                ]
                textRole: "text"; valueRole: "value"
                Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_soundRedCard))
            }
            PlasmaComponents3.Button {
                icon.name: "media-playback-start"
                text: "Test"
                onClicked: playTest(soundRedCardCombo.currentValue)
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Audio device:"
            PlasmaComponents3.ComboBox {
                id: deviceCombo
                property bool restored: false
                model: {
                    var list = [{ text: "Default", value: "" }];
                    for (var i = 0; i < mediaDevices.audioOutputs.length; i++) {
                        var dev = mediaDevices.audioOutputs[i];
                        // Store as an explicit String: dev.id is a QByteArray, and
                        // a QByteArray value breaks both indexOfValue() restore and
                        // the device match in main.qml (type mismatch).
                        list.push({ text: dev.description,
                                    value: String(dev.id || dev.description) });
                    }
                    return list;
                }
                textRole: "text"; valueRole: "value"
                // Audio device model is async — restore once it's populated
                onCountChanged: {
                    if (!restored && count > 1) {
                        currentIndex = Math.max(0, indexOfValue(cfg_soundOutputDevice));
                        restored = true;
                    }
                }
            }
        }

            } // ===== end FormLayout 2 (Sound) =====

            // ===== FormLayout 3: Commentary =====
            Kirigami.FormLayout {
                Layout.fillWidth: true

        // ── Live commentary (AI / LLM) ─────────────────────────────────────
        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            text: "Live commentary (AI)"
            level: 3
        }

        Kirigami.Heading {
            Kirigami.FormData.label: ""
            text: "An LLM writes British-TV-style commentary on goals, cards and the run of play; an optional British voice reads it aloud. Run it locally on your own GPU (Ollama, default gemma4:12b), or — if you have no GPU — use a free cloud provider below (e.g. OpenRouter). No data leaves your machine in local mode."
            level: 6; color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap; Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }

        // ── Commentator style (plugin profiles) ────────────────────────────
        RowLayout {
            Kirigami.FormData.label: "Style:"
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.ComboBox {
                id: styleCombo
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                model: root.llmStyles
                textRole: "name"; valueRole: "id"
                // Keep selection synced with the active style from status.
                function syncIndex() { currentIndex = Math.max(0, indexOfValue(root.llmStyle)); }
                onModelChanged: syncIndex()
                Connections { target: root; function onLlmStyleChanged() { styleCombo.syncIndex() } }
                onActivated: root.setStyle(currentValue)
            }
            PlasmaComponents3.Label {
                visible: styleCombo.currentIndex >= 0 && root.llmStyles.length > 0
                text: (root.llmStyles[styleCombo.currentIndex] || {}).language || ""
                color: Kirigami.Theme.disabledTextColor
            }
        }

        // Status indicators
        RowLayout {
            Kirigami.FormData.label: "Status:"
            spacing: Kirigami.Units.largeSpacing
            Repeater {
                model: root.llmBackend === "cloud"
                    ? [ { l: "Cloud", ok: root.llmCloudBase !== "" },
                        { l: "Running", ok: root.llmServiceActive } ]
                    : [ { l: "Ollama",  ok: root.llmOllamaInstalled && root.llmOllamaRunning },
                        { l: "Model",   ok: root.llmModelInstalled },
                        { l: "Running", ok: root.llmServiceActive } ]
                RowLayout {
                    spacing: 3
                    Kirigami.Icon {
                        width: 16; height: 16
                        source: modelData.ok ? "dialog-ok-apply" : "dialog-cancel"
                        color: modelData.ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    }
                    PlasmaComponents3.Label { text: modelData.l }
                }
            }
            PlasmaComponents3.Label {
                visible: root.llmBackend === "cloud" && root.llmCloudModel !== ""
                text: "· " + root.llmCloudModel
                color: Kirigami.Theme.disabledTextColor
            }
            PlasmaComponents3.Button {
                icon.name: "view-refresh"
                text: "Refresh"; onClicked: root.llmRefresh()
            }
        }

        // ── Backend chooser: local GPU (Ollama) vs free cloud ──────────────────
        RowLayout {
            Kirigami.FormData.label: "Engine:"
            ButtonGroup { id: backendGroup }
            PlasmaComponents3.RadioButton {
                id: backendLocal
                text: "Local GPU (Ollama)"
                ButtonGroup.group: backendGroup
                checked: root.llmBackend !== "cloud"
            }
            PlasmaComponents3.RadioButton {
                id: backendCloud
                text: "Free cloud (no GPU)"
                ButtonGroup.group: backendGroup
                checked: root.llmBackend === "cloud"
            }
        }

        // ── Cloud setup (visible only when "Free cloud" is selected) ───────────
        ColumnLayout {
            Kirigami.FormData.label: "Cloud provider:"
            visible: backendCloud.checked
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.ComboBox {
                    id: cloudProviderCombo
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                    textRole: "text"; valueRole: "value"
                    model: [
                        { text: "OpenRouter (free)", value: "openrouter" },
                        { text: "Groq (free)",       value: "groq" },
                        { text: "Google Gemini (free)", value: "gemini" },
                        { text: "OpenCode Zen",      value: "zen" }
                    ]
                }
                PlasmaComponents3.Button {
                    text: "Get free key ↗"
                    icon.name: "globe"
                    onClicked: root.llmOpenKeyPage(cloudProviderCombo.currentValue)
                }
            }

            PlasmaComponents3.Label {
                text: "1) Click \"Get free key\", sign up (no card for OpenRouter/Groq/Gemini), copy your key.\n2) Paste it below and click \"Set up cloud\" — it tests the key, picks a free model, and switches over."
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.WordWrap; Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.TextField {
                    id: cloudKeyField
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                    placeholderText: "Paste API key (e.g. sk-or-…)"
                    echoMode: TextInput.Password
                }
                PlasmaComponents3.ComboBox {
                    id: cloudModelField
                    editable: true
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                    model: ["auto"]
                    Component.onCompleted: editText = (root.llmCloudModel || "auto")
                }
            }

            // Confirmation that a working key is already saved (small green italic).
            PlasmaComponents3.Label {
                visible: root.llmBackend === "cloud" && root.llmCloudBase !== ""
                text: {
                    var host = root.llmCloudBase.replace(/^https?:\/\//, "").split("/")[0];
                    return "✓ A working key is saved — " + host
                         + (root.llmCloudModel ? " · " + root.llmCloudModel : "")
                         + ". Paste a new key only to replace it.";
                }
                color: Kirigami.Theme.positiveTextColor
                font.italic: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                wrapMode: Text.WordWrap; Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.Button {
                    text: "Set up cloud"
                    icon.name: "cloud-upload"
                    enabled: root.llmBusy === "" && cloudKeyField.text.length > 0
                    onClicked: root.llmApplyCloud(cloudProviderCombo.currentValue,
                                                  cloudKeyField.text, cloudModelField.editText)
                }
                PlasmaComponents3.Button {
                    text: "Back to local"
                    icon.name: "computer"
                    visible: root.llmBackend === "cloud"
                    enabled: root.llmBusy === ""
                    onClicked: root.llmAction("use-local", "Switching to local…")
                }
            }
        }

        // Enable toggle — saved on "Apply" (the plasmoid then enables/disables
        // the systemd service to match).
        PlasmaComponents3.CheckBox {
            id: commentatorEnabledCheck
            Kirigami.FormData.label: "Live commentary:"
            text: "Enabled — comment on goals and red cards"
        }

        // Output mode: voice reads it aloud (British TTS voice), text, or both.
        RowLayout {
            Kirigami.FormData.label: "Output:"
            PlasmaComponents3.ComboBox {
                id: commentaryModeCombo
                model: [
                    { text: "Voice + text", value: "both" },
                    { text: "Text only",    value: "text" },
                    { text: "Voice only",   value: "sound" }
                ]
                textRole: "text"; valueRole: "value"
                Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_commentaryMode))
            }
            // Voice-only test (fixed line) — fast check of the sound + device.
            PlasmaComponents3.Button {
                text: "Test voice"
                icon.name: "audio-volume-high"
                enabled: root.llmBusy === ""
                onClicked: root.llmAction("test-voice " + JSON.stringify(deviceCombo.currentValue || ""),
                                          "Speaking a test line…")
            }
            // Full test — GENERATE via the active backend (cloud/Ollama) AND speak it.
            PlasmaComponents3.Button {
                text: "Test commentary"
                icon.name: "text-speak"
                enabled: root.llmBusy === ""
                onClicked: root.llmAction("test " + JSON.stringify(deviceCombo.currentValue || ""),
                                          "Generating + speaking…")
            }
        }

        // Model — also saved on "Apply". Pick an installed one or type a new
        // name and use "Download / install model" first.
        RowLayout {
            Kirigami.FormData.label: "Model:"
            spacing: Kirigami.Units.smallSpacing
            visible: !backendCloud.checked
            PlasmaComponents3.ComboBox {
                id: llmModelCombo
                editable: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                model: root.llmModels
            }
        }

        // Install / download buttons
        RowLayout {
            Kirigami.FormData.label: ""
            spacing: Kirigami.Units.smallSpacing
            visible: !backendCloud.checked
            PlasmaComponents3.Button {
                text: "Install Ollama"
                icon.name: "install"
                visible: !root.llmOllamaInstalled
                enabled: root.llmBusy === ""
                onClicked: root.llmAction("install-ollama", "Installing Ollama…")
            }
            PlasmaComponents3.Button {
                text: "Download / install model"
                icon.name: "cloud-download"
                enabled: root.llmBusy === "" && root.llmOllamaInstalled
                onClicked: root.llmAction("pull-model " + llmModelCombo.editText, "Downloading model…")
            }
            // (The commentary test now lives on the Output row as "Test commentary",
            //  available in both local and cloud mode.)
        }

        // Busy / last-result line
        PlasmaComponents3.Label {
            Kirigami.FormData.label: ""
            visible: root.llmBusy !== "" || root.llmOutput !== ""
            text: root.llmBusy !== "" ? (root.llmBusy + " please wait…") : root.llmOutput
            color: root.llmBusy !== "" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
            font.italic: root.llmBusy !== ""
            wrapMode: Text.WordWrap; Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }

            } // ===== end FormLayout 3 (Commentary) =====

            // ===== FormLayout 4: Follow (teams + leagues) =====
            Kirigami.FormLayout {
                Layout.fillWidth: true

        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            text: "Favourite teams"
            level: 3
        }

        SettingCard {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true
            ColumnLayout {
                width: parent.width
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Heading {
                    text: "Search for teams and click to add them."
                    level: 6; color: Kirigami.Theme.disabledTextColor; wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                TeamSelector {
                    id: teamSelector
                    Layout.fillWidth: true
                    allTeams: root.availableTeams
                }
            }
        }

        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            text: "Tournaments and leagues"
            level: 3
        }

        SettingCard {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true
            ColumnLayout {
                width: parent.width
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Heading {
                    text: "Follow ALL matches in these tournaments."
                    level: 6; color: Kirigami.Theme.disabledTextColor; wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Repeater {
                        model: root.availableLeagues
                        delegate: Rectangle {
                            height: chipContent.height + Kirigami.Units.smallSpacing * 2
                            width: chipContent.width + Kirigami.Units.smallSpacing * 3
                            radius: height / 2
                            color: root.isLeagueSelected(modelData.id) ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)
                            border.color: root.isLeagueSelected(modelData.id) ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                            border.width: 1
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.toggleLeague(modelData.id)
                                cursorShape: Qt.PointingHandCursor
                                RowLayout {
                                    id: chipContent
                                    anchors.centerIn: parent
                                    spacing: Kirigami.Units.smallSpacing
                                    Text {
                                        text: root.isLeagueSelected(modelData.id) ? "✓" : "+"
                                        font.pixelSize: Kirigami.Theme.defaultFont.pointSize
                                        font.bold: true
                                        color: root.isLeagueSelected(modelData.id) ? "white" : Kirigami.Theme.disabledTextColor
                                    }
                                    Kirigami.Heading {
                                        text: modelData.name
                                        level: 6
                                        color: root.isLeagueSelected(modelData.id) ? "white" : Kirigami.Theme.textColor
                                        font.bold: root.isLeagueSelected(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
                PlasmaComponents3.Label {
                    text: "Selected: " + (cfg_selectedLeagues || "None")
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Kirigami.Theme.disabledTextColor
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }

        // Hidden holder so the alias has something to bind to for saving.
        // NB: no `text:` binding — the alias IS leagueValue.text, so binding it
        // to cfg_selectedLeagues would be self-referential.
        PlasmaComponents3.Label {
            id: leagueValue
            visible: false
        }

            } // ===== end FormLayout 4 (Follow) =====
        } // ===== end StackLayout =====
    } // ===== end ColumnLayout =====
}
