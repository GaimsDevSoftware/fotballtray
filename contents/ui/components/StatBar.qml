import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Modern, unified stat row: [homeVal]  [home ▸◂ away split track]  [awayVal]
// One track split proportionally — home fills from the left, away from the
// right. Colours are a single accent (home) vs a calm neutral (away) so every
// row looks consistent regardless of the teams' kit colours; the leading side
// is emphasised (full opacity + bold coloured value).
Item {
    id: statBar
    property string label: ""
    property real homeValue: 0
    property real awayValue: 0
    property bool isPercentage: false
    property color homeColor: Kirigami.Theme.highlightColor
    property color awayColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.4)

    implicitHeight: 26
    implicitWidth: parent ? parent.width : 200

    readonly property real valueW: Kirigami.Units.gridUnit * 1.8
    readonly property real labelW: Kirigami.Units.gridUnit * 6
    readonly property real barSpan: Math.max(8, statBar.width - valueW * 2 - labelW - 24)

    function totalValue() { return Math.max(homeValue + awayValue, 1) }
    function homeFrac() { return homeValue / totalValue() }
    function awayFrac() { return awayValue / totalValue() }
    readonly property bool homeLeads: homeValue > awayValue
    readonly property bool awayLeads: awayValue > homeValue

    function fmt(v) { return isPercentage ? Math.round(v) + "%" : Math.round(v) }

    RowLayout {
        anchors.fill: parent
        spacing: 6

        Kirigami.Heading {
            text: fmt(homeValue)
            level: 6; font.pixelSize: 12
            font.weight: statBar.homeLeads ? Font.Bold : Font.Normal
            color: statBar.homeLeads ? statBar.homeColor : Kirigami.Theme.textColor
            Layout.preferredWidth: statBar.valueW
            horizontalAlignment: Text.AlignRight
        }

        // Split track
        Item {
            Layout.preferredWidth: statBar.barSpan
            Layout.preferredHeight: 8
            Layout.alignment: Qt.AlignVCenter

            // faint full-width groove
            Rectangle {
                anchors.fill: parent
                radius: 4
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)
            }
            // home portion (left), 3px gap before centre split
            Rectangle {
                anchors.left: parent.left
                height: 8; radius: 4
                width: Math.max(3, (parent.width - 3) * statBar.homeFrac())
                color: statBar.homeColor
                opacity: statBar.homeLeads ? 1.0 : 0.5
                Behavior on width { NumberAnimation { duration: Kirigami.Units.veryLongDuration; easing.type: Easing.OutCubic } }
            }
            // away portion (right)
            Rectangle {
                anchors.right: parent.right
                height: 8; radius: 4
                width: Math.max(3, (parent.width - 3) * statBar.awayFrac())
                color: statBar.awayColor
                opacity: statBar.awayLeads ? 1.0 : 0.7
                Behavior on width { NumberAnimation { duration: Kirigami.Units.veryLongDuration; easing.type: Easing.OutCubic } }
            }
        }

        Kirigami.Heading {
            text: label; level: 6
            font.pixelSize: 11; color: Kirigami.Theme.disabledTextColor
            Layout.preferredWidth: statBar.labelW
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Kirigami.Heading {
            text: fmt(awayValue)
            level: 6; font.pixelSize: 12
            font.weight: statBar.awayLeads ? Font.Bold : Font.Normal
            color: statBar.awayLeads ? statBar.awayColor : Kirigami.Theme.textColor
            Layout.preferredWidth: statBar.valueW
            horizontalAlignment: Text.AlignLeft
        }
    }
}
