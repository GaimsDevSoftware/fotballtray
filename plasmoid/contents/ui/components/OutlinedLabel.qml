import QtQuick
import org.kde.kirigami as Kirigami

// A heading with an optional CRISP outline for legibility on the panel.
//
// Qt's built-in `Text.Outline` style draws a soft, antialiased stroke that
// looks blurry/imprecise on fractional-scaled (here ~1.45×) panels. Instead we
// build the outline from several fully-opaque copies of the glyphs, each nudged
// by a whole pixel in a different direction. Every copy is a sharply rendered
// NativeRendering glyph, so their union forms a clean, solid contour with no
// blur. The coloured fill is drawn last, on top.
Item {
    id: ol
    property string text: ""
    property color color: Kirigami.Theme.textColor
    property int level: 4
    property int weight: Font.ExtraBold
    property bool bold: true
    property bool outlined: false
    property color innerColor: "black"     // outline colour
    property color outerColor: "white"     // kept for API compatibility
    property int outlineWidth: 1           // outline thickness, in px

    // Optional drop shadow, drawn behind everything.
    property bool shadow: false
    property color shadowColor: Qt.rgba(0, 0, 0, 0.72)
    property real shadowOffsetX: 1
    property real shadowOffsetY: 1

    implicitWidth: front.implicitWidth + (outlined ? 2 * outlineWidth : 0)
    implicitHeight: front.implicitHeight + (outlined ? 2 * outlineWidth : 0)

    // 8 whole-pixel offsets (4 axis + 4 diagonal) → a uniform solid contour.
    readonly property var _offsets: [
        Qt.point(-1, 0), Qt.point(1, 0), Qt.point(0, -1), Qt.point(0, 1),
        Qt.point(-1, -1), Qt.point(1, -1), Qt.point(-1, 1), Qt.point(1, 1)
    ]

    // Drop shadow: an offset copy of the glyphs, behind the outline + fill.
    Kirigami.Heading {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: ol.shadowOffsetX
        anchors.verticalCenterOffset: ol.shadowOffsetY
        visible: ol.shadow
        text: ol.text; level: ol.level
        font.bold: true; font.weight: ol.weight
        color: ol.shadowColor
        renderType: Text.NativeRendering
    }

    Repeater {
        model: ol.outlined ? ol._offsets : []
        Kirigami.Heading {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: modelData.x * ol.outlineWidth
            anchors.verticalCenterOffset: modelData.y * ol.outlineWidth
            text: ol.text; level: ol.level
            font.bold: true; font.weight: ol.weight
            color: ol.innerColor
            renderType: Text.NativeRendering
        }
    }

    // Coloured fill on top of the outline.
    Kirigami.Heading {
        id: front
        anchors.centerIn: parent
        text: ol.text; level: ol.level
        font.bold: true; font.weight: ol.weight
        color: ol.color
        renderType: Text.NativeRendering   // crisp glyphs on fractional scaling
    }
}
