import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

ColumnLayout {
    id: selector
    property var allTeams: []
    // NB: do NOT also declare `signal selectedTeamsChanged(...)` — the property
    // above auto-generates that signal; a manual declaration is a duplicate and
    // makes the whole type fail to compile ("Type TeamSelector unavailable").
    property string selectedTeams: ""

    spacing: Kirigami.Units.smallSpacing

    function getSelectedList() {
        return (selectedTeams || "").split(",").map(function(s){return s.trim();}).filter(function(s){return s.length>0;});
    }

    function addTeam(name) {
        var list = getSelectedList();
        if (list.indexOf(name) < 0) {
            list.push(name);
            selectedTeams = list.join(", ");
            // assigning selectedTeams above auto-emits selectedTeamsChanged
        }
    }

    function removeTeam(name) {
        var list = getSelectedList().filter(function(t){return t !== name;});
        selectedTeams = list.join(", ");
    }

    // Search field
    PlasmaComponents3.TextField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: "Search for teams..."
    }

    // Search results
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(resultCol.implicitHeight, Kirigami.Units.gridUnit * 8)
        color: Kirigami.Theme.backgroundColor
        radius: Kirigami.Units.smallSpacing
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
        border.width: 1
        visible: searchField.text.length > 0
        clip: true

        ScrollView {
            anchors.fill: parent
            ColumnLayout {
                id: resultCol
                width: parent.width
                spacing: 0

                Repeater {
                    model: {
                        if (!searchField.text || searchField.text.length < 1) return [];
                        var q = searchField.text.toLowerCase();
                        var results = [];
                        for (var i=0; i<allTeams.length && results.length < 8; i++) {
                            var t = allTeams[i];
                            var name = (typeof t === "string") ? t : (t.name || t);
                            if (name.toLowerCase().indexOf(q) >= 0) results.push(name);
                        }
                        return results;
                    }
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.8
                        color: mouseArea2.containsMouse
                            ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.1)
                            : "transparent"

                        MouseArea {
                            id: mouseArea2
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                selector.addTeam(modelData);
                                searchField.text = "";
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Kirigami.Units.smallSpacing
                            anchors.rightMargin: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Heading {
                                text: "+"
                                level: 6; color: Kirigami.Theme.disabledTextColor
                                Layout.preferredWidth: 16
                            }
                            Kirigami.Heading {
                                text: modelData
                                level: 6
                                Layout.fillWidth: true; elide: Text.ElideRight
                            }
                        }
                    }
                }

                Kirigami.Heading {
                    visible: resultCol.children.length <= 1 && searchField.text.length > 0
                    text: "No teams found"
                    level: 6; color: Kirigami.Theme.disabledTextColor
                    Layout.alignment: Qt.AlignHCenter
                    padding: Kirigami.Units.smallSpacing
                }
            }
        }
    }

    // Selected teams chips
    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: selector.getSelectedList()
            delegate: Rectangle {
                height: chipRow.height + Kirigami.Units.smallSpacing * 2
                width: chipRow.width + Kirigami.Units.smallSpacing * 3
                radius: height / 2
                color: Kirigami.Theme.highlightColor

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing / 2

                    Kirigami.Heading {
                        text: modelData
                        level: 6; color: "white"; font.bold: true
                    }

                    Rectangle {
                        width: 16; height: 16; radius: 8
                        color: Qt.rgba(0, 0, 0, 0.2)
                        Kirigami.Heading {
                            anchors.centerIn: parent
                            text: "✕"; font.pixelSize: 9; color: "white"
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: selector.removeTeam(modelData)
                        }
                    }
                }
            }
        }

        Kirigami.Heading {
            visible: selector.getSelectedList().length === 0
            text: "No favourite teams selected"
            level: 6; color: Kirigami.Theme.disabledTextColor
        }
    }
}
