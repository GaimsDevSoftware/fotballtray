import QtQuick
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami

Item {
    id: flagContainer
    property string source: ""
    property string countryCode: ""
    property real size: Kirigami.Units.gridUnit * 2
    width: size; height: size

    // --- Off-screen sources for MultiEffect ---

    // Off-screen layer resolution. MUST scale with the display's pixel ratio:
    // on a 4K screen with fractional scaling the masked layer is resampled, and
    // a fixed logical size left it soft. Oversample generously so the downscale
    // to the (possibly fractional) on-screen size stays crisp.
    readonly property int _tex: Math.ceil(size * Math.max(2, Screen.devicePixelRatio) * 2)

    Image {
        id: flagImg
        anchors.fill: parent
        source: flagContainer.source
        sourceSize.width: flagContainer._tex
        sourceSize.height: flagContainer._tex
        fillMode: Image.PreserveAspectCrop
        smooth: true
        mipmap: true
        asynchronous: true
        visible: false
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(flagContainer._tex, flagContainer._tex)
    }

    Rectangle {
        id: circleMask
        width: size; height: size
        radius: size / 2
        visible: false
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(flagContainer._tex, flagContainer._tex)
    }

    // --- Fallback when image is not ready ---
    Rectangle {
        anchors.fill: parent
        radius: size / 2
        color: Qt.rgba(
            Kirigami.Theme.highlightColor.r,
            Kirigami.Theme.highlightColor.g,
            Kirigami.Theme.highlightColor.b, 0.85)
        border.color: Qt.rgba(1, 1, 1, 0.5)
        border.width: 1
        visible: flagImg.status !== Image.Ready

        Kirigami.Heading {
            anchors.centerIn: parent
            text: countryCode ? countryCode.substring(0, 2) : "?"
            level: 4; font.bold: true; color: "white"
        }
    }

    // --- Crisply clipped circular flag (OpacityMask is sharper than MultiEffect
    //     on fractional scaling — it just multiplies alpha, no soft alpha ramp). ---
    OpacityMask {
        id: maskedFlag
        source: flagImg
        maskSource: circleMask
        anchors.fill: parent
        antialiasing: true
        visible: flagImg.status === Image.Ready
    }

    // --- Glossy highlight (top-left bright, fades to transparent) ---
    Item {
        anchors.fill: parent
        visible: flagImg.status === Image.Ready

        Rectangle {
            id: glossSource
            width: size; height: size
            visible: false
            layer.enabled: true
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.32) }
                    GradientStop { position: 0.42; color: Qt.rgba(1, 1, 1, 0.0) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.18) }
                }
            }
        }

        OpacityMask {
            source: glossSource
            maskSource: circleMask
            anchors.fill: parent
            antialiasing: true
        }
    }

}
