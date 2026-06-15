import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Animated first-run onboarding shown over the popup. Walks through what the
// app does and how to set it up, with slide/fade step transitions, a floating
// icon, progress dots and Skip / Back / Next navigation.
//
//   signal finished()       — user finished or skipped; caller persists the flag
//   signal openSettings()   — user asked to open the configuration dialog
Item {
    id: ob
    anchors.fill: parent
    z: 9999

    property color accent: Kirigami.Theme.highlightColor
    signal finished()
    signal openSettings()

    property int step: 0
    readonly property var steps: [
        { icon: "⚽", title: "Welcome to FootballTray",
          body: "Live football scores, right in your system tray. Here's a quick 30-second tour." },
        { icon: "👀", title: "At a glance",
          body: "Your panel shows the score, the two teams and the match clock — with a softly blinking live dot while a match is being played." },
        { icon: "📊", title: "The full picture",
          body: "Click the tray icon to open live & finished matches, group tables, knockout brackets, and a detailed match card with line-ups and player ratings." },
        { icon: "🎙️", title: "Live AI commentary — optional",
          body: "British-TV-style commentary on goals and red cards, optionally read aloud. Run it locally on your GPU (Ollama), or use a free cloud provider (OpenRouter / Groq / Gemini) — no GPU needed." },
        { icon: "🚀", title: "Set it up",
          body: "1.  Open Settings → add your favourite teams & leagues.\n2.  (Optional) switch on Live commentary.\n\nThat's it — enjoy the football!" }
    ]
    readonly property bool isLast: step === steps.length - 1

    function go(delta) {
        var n = step + delta;
        if (n < 0 || n >= steps.length) return;
        slideOut.dir = delta;
        slideOut.toStep = n;
        slideOut.start();
    }

    // Dim scrim that also swallows clicks to the popup behind.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; hoverEnabled: true /* eat events */ }
        opacity: 0
        Component.onCompleted: scrimIn.start()
        NumberAnimation on opacity { id: scrimIn; running: false; to: 1; duration: 220 }
    }

    // Centred card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 30)
        height: Math.min(parent.height - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 26)
        radius: Kirigami.Units.gridUnit
        color: Kirigami.Theme.backgroundColor
        border.color: Qt.rgba(ob.accent.r, ob.accent.g, ob.accent.b, 0.5)
        border.width: 1

        // Pop-in
        scale: 0.92; opacity: 0
        Component.onCompleted: { cardScale.start(); cardFade.start(); }
        NumberAnimation { id: cardScale; target: card; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutBack }
        NumberAnimation { id: cardFade;  target: card; property: "opacity"; to: 1.0; duration: 220 }

        // Accent header bar
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: Kirigami.Units.gridUnit * 0.5
            radius: card.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: ob.accent }
                GradientStop { position: 1.0; color: Qt.rgba(ob.accent.r, ob.accent.g, ob.accent.b, 0.4) }
            }
            // square off the bottom corners of the rounded bar
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.height/2; color: parent.color }
        }

        // Skip (top-right)
        Text {
            id: skipBtn
            anchors { top: parent.top; right: parent.right; topMargin: Kirigami.Units.largeSpacing + 4; rightMargin: Kirigami.Units.largeSpacing }
            text: "Skip ✕"
            color: Kirigami.Theme.disabledTextColor
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            MouseArea {
                anchors.fill: parent; anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: ob.finished()
                onEntered: skipBtn.color = Kirigami.Theme.textColor
                onExited: skipBtn.color = Kirigami.Theme.disabledTextColor
                hoverEnabled: true
            }
        }

        // ── Animated content (fades/slides on step change) ─────────────────
        ColumnLayout {
            id: content
            anchors {
                left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                leftMargin: Kirigami.Units.gridUnit * 2; rightMargin: Kirigami.Units.gridUnit * 2
            }
            spacing: Kirigami.Units.largeSpacing

            // Floating icon
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                Layout.preferredHeight: Kirigami.Units.gridUnit * 5

                Rectangle {   // soft accent disc behind the icon
                    anchors.centerIn: parent
                    width: Kirigami.Units.gridUnit * 4.4; height: width; radius: width / 2
                    color: Qt.rgba(ob.accent.r, ob.accent.g, ob.accent.b, 0.12)
                }
                Text {
                    id: iconText
                    anchors.centerIn: parent
                    text: ob.steps[ob.step].icon
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 3.2
                    // gentle float
                    SequentialAnimation on anchors.verticalCenterOffset {
                        loops: Animation.Infinite; running: true
                        NumberAnimation { from: 0;  to: -7; duration: 1100; easing.type: Easing.InOutSine }
                        NumberAnimation { from: -7; to: 0;  duration: 1100; easing.type: Easing.InOutSine }
                    }
                }
                // Pulsing live dot — only on the "at a glance" step
                Rectangle {
                    visible: ob.step === 1
                    anchors { right: parent.right; top: parent.top; rightMargin: Kirigami.Units.gridUnit; topMargin: Kirigami.Units.gridUnit }
                    width: 12; height: 12; radius: 6
                    color: ob.accent; border.color: "black"; border.width: 1
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite; running: ob.step === 1
                        NumberAnimation { from: 1.0; to: 0.2; duration: 700 }
                        NumberAnimation { from: 0.2; to: 1.0; duration: 700 }
                    }
                }
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                text: ob.steps[ob.step].title
                level: 2; horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 6
                text: ob.steps[ob.step].body
                color: Kirigami.Theme.textColor
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignTop
                lineHeight: 1.15
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
            }

            // "Open Settings" CTA on the last step
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                visible: ob.isLast
                radius: height / 2
                color: ob.accent
                implicitWidth: openLbl.implicitWidth + Kirigami.Units.gridUnit * 2.5
                implicitHeight: openLbl.implicitHeight + Kirigami.Units.largeSpacing
                Text {
                    id: openLbl; anchors.centerIn: parent
                    text: "⚙  Open Settings"; color: "white"; font.bold: true
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: ob.openSettings()
                }
            }
        }

        // ── Bottom bar: Back · dots · Next ─────────────────────────────────
        Item {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                      margins: Kirigami.Units.largeSpacing * 1.5 }
            height: Kirigami.Units.gridUnit * 2

            // Back
            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                text: "‹ Back"
                visible: ob.step > 0
                color: Kirigami.Theme.textColor
                MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: ob.go(-1) }
            }

            // Progress dots
            Row {
                anchors.centerIn: parent
                spacing: 6
                Repeater {
                    model: ob.steps.length
                    Rectangle {
                        width: index === ob.step ? 18 : 8
                        height: 8; radius: 4
                        color: index === ob.step ? ob.accent
                              : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                        Behavior on width { NumberAnimation { duration: 180 } }
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                }
            }

            // Next / Get started
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                radius: height / 2
                color: ob.accent
                implicitWidth: nextLbl.implicitWidth + Kirigami.Units.gridUnit * 1.8
                implicitHeight: nextLbl.implicitHeight + Kirigami.Units.smallSpacing * 2
                Text {
                    id: nextLbl; anchors.centerIn: parent
                    text: ob.isLast ? "Get started  ✓" : "Next  ›"
                    color: "white"; font.bold: true
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: ob.isLast ? ob.finished() : ob.go(1)
                }
            }
        }

        // Step transition: fade+slide content out, swap, slide+fade in.
        SequentialAnimation {
            id: slideOut
            property int dir: 1
            property int toStep: 0
            ParallelAnimation {
                NumberAnimation { target: content; property: "opacity"; to: 0; duration: 110 }
                NumberAnimation { target: content; property: "anchors.horizontalCenterOffset"; to: slideOut.dir * -28; duration: 110; easing.type: Easing.InQuad }
            }
            ScriptAction { script: { ob.step = slideOut.toStep; content.anchors.horizontalCenterOffset = slideOut.dir * 28; } }
            ParallelAnimation {
                NumberAnimation { target: content; property: "opacity"; to: 1; duration: 160 }
                NumberAnimation { target: content; property: "anchors.horizontalCenterOffset"; to: 0; duration: 200; easing.type: Easing.OutQuad }
            }
        }
    }

    // Keyboard: Esc skips, arrows navigate, Enter advances.
    focus: true
    Keys.onEscapePressed: ob.finished()
    Keys.onRightPressed: ob.go(1)
    Keys.onLeftPressed: ob.go(-1)
    Keys.onReturnPressed: ob.isLast ? ob.finished() : ob.go(1)
}
