import QtQuick
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami

Item {
    id: badge
    property var matchObj: ({})
    property bool isHome: true
    property real size: Kirigami.Units.iconSizes.smallMedium
    width: size; height: size

    readonly property bool showFlag: isHome ? (matchObj.homeImageIsFlag || false) : (matchObj.awayImageIsFlag || false)
    readonly property string imageUrl: isHome ? (matchObj.homeImageUrl || "") : (matchObj.awayImageUrl || "")
    readonly property string countryCode: isHome ? (matchObj.homeCountryCode || "") : (matchObj.awayCountryCode || "")
    readonly property string teamName: isHome ? (matchObj.homeTeam || "") : (matchObj.awayTeam || "")

    // Soft drop shadow behind the badge silhouette - always on, replaces the
    // old ring outline. Declared first → renders behind the content.
    DropShadow {
        anchors.fill: content
        source: content
        horizontalOffset: 1
        verticalOffset: 1
        radius: Math.max(3, badge.size * 0.16)
        samples: 17
        color: Qt.rgba(0, 0, 0, 0.6)
        cached: true
    }

    Item {
        id: content
        anchors.fill: parent

    // National team: round glossy flag
    FlagImage {
        anchors.fill: parent
        source: badge.imageUrl
        countryCode: badge.countryCode
        size: badge.size
        visible: badge.showFlag || badge.imageUrl === ""
    }

    // Club team: rounded-rect logo with glossy treatment
    Item {
        anchors.fill: parent
        visible: !badge.showFlag && badge.imageUrl !== ""

        // Off-screen layer resolution, scaled by the display pixel ratio so the
        // masked logo stays crisp on 4K / fractional-scaled screens.
        readonly property int _tex: Math.ceil(size * Math.max(2, Screen.devicePixelRatio) * 2)

        // Logo image (off-screen source for MultiEffect)
        Image {
            id: clubLogo
            anchors.fill: parent
            source: badge.imageUrl
            sourceSize.width: parent._tex; sourceSize.height: parent._tex
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            asynchronous: true
            visible: false
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(parent._tex, parent._tex)
        }

        // Rounded-rect mask
        Rectangle {
            id: clubMask
            width: size; height: size
            radius: size * 0.22
            visible: false
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(parent._tex, parent._tex)
        }

        // Fallback background (shown while loading or on failure)
        Rectangle {
            anchors.fill: parent
            radius: size * 0.22
            color: Qt.rgba(
                Kirigami.Theme.highlightColor.r,
                Kirigami.Theme.highlightColor.g,
                Kirigami.Theme.highlightColor.b, 0.85)
            border.color: Qt.rgba(1, 1, 1, 0.4)
            border.width: 1
            visible: clubLogo.status !== Image.Ready

            Kirigami.Heading {
                anchors.centerIn: parent
                text: badge.teamName ? badge.teamName.substring(0, 1).toUpperCase() : "?"
                level: 4; font.bold: true; color: "white"
            }
        }

        // White card background for logos (ensures visibility on any bg)
        Rectangle {
            anchors.fill: parent
            radius: size * 0.22
            color: "white"
            visible: clubLogo.status === Image.Ready
        }

        // Clipped club logo - OpacityMask for a crisp edge on fractional scaling
        OpacityMask {
            source: clubLogo
            maskSource: clubMask
            anchors.fill: parent
            antialiasing: true
            visible: clubLogo.status === Image.Ready
        }

        // Subtle glossy highlight
        Item {
            anchors.fill: parent
            visible: clubLogo.status === Image.Ready

            Rectangle {
                id: clubGlossSource
                width: size; height: size
                visible: false
                layer.enabled: true
                color: "transparent"
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.22) }
                        GradientStop { position: 0.50; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }
            }

            OpacityMask {
                source: clubGlossSource
                maskSource: clubMask
                anchors.fill: parent
                antialiasing: true
            }
        }

    }
    }
}
