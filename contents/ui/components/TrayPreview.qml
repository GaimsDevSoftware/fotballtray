import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

RowLayout {
    id: preview
    property string mode: "flagText"
    spacing: Kirigami.Units.smallSpacing

    Rectangle {
        visible: mode === "flagText" || mode === "flagOnly"
        width: 18; height: 18; radius: 9
        color: "#e30613"
    }

    Kirigami.Heading {
        visible: mode !== "flagOnly" && mode !== "scoreOnly"
        text: "NOR"
        level: 5; font.bold: true
    }

    Kirigami.Heading {
        text: "2-1"
        level: 4; font.bold: true
    }

    Kirigami.Heading {
        visible: mode !== "flagOnly" && mode !== "scoreOnly"
        text: mode === "fullName" ? "Sweden" : "SWE"
        level: 5; font.bold: true
    }

    Rectangle {
        visible: mode === "flagText" || mode === "flagOnly"
        width: 18; height: 18; radius: 9
        color: "#fecb00"
    }
}
