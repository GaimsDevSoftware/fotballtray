import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: card
    default property alias content: innerLayout.data

    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
    radius: Kirigami.Units.gridUnit * 0.5
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
    border.width: 1
    implicitHeight: innerLayout.implicitHeight + Kirigami.Units.largeSpacing * 2
    implicitWidth: parent ? parent.width : 300

    ColumnLayout {
        id: innerLayout
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
    }
}
