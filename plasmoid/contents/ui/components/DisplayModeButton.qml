import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: btn
    property string text: ""
    property string subText: ""
    property string iconText: ""
    property bool checked: false
    signal clicked()

    implicitWidth: col.implicitWidth + Kirigami.Units.largeSpacing * 2.5
    implicitHeight: col.implicitHeight + Kirigami.Units.largeSpacing * 2
    radius: 10

    color: checked
        ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
    border.color: checked
        ? Kirigami.Theme.highlightColor
        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
    border.width: checked ? 2 : 1

    Behavior on color  { ColorAnimation { duration: Kirigami.Units.shortDuration } }
    Behavior on border.color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        spacing: 4

        // Icon preview area
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: Kirigami.Units.gridUnit * 3
            height: Kirigami.Units.gridUnit * 1.6
            radius: 6
            color: checked
                ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.12)
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)

            Kirigami.Heading {
                anchors.centerIn: parent
                text: btn.iconText
                level: 5; font.bold: true
                color: checked ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
            }
        }

        Kirigami.Heading {
            text: btn.text
            level: 6; font.bold: checked
            Layout.alignment: Qt.AlignHCenter
            color: checked ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
        }

        Kirigami.Heading {
            text: btn.subText
            level: 6; font.pixelSize: 9
            Layout.alignment: Qt.AlignHCenter
            color: Kirigami.Theme.disabledTextColor
            visible: btn.subText.length > 0
        }
    }
}
