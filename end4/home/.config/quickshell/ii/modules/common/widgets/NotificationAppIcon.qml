import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

MaterialShape { // App icon
    id: root
    property var appIcon: ""
    property var summary: ""
    property var urgency: NotificationUrgency.Normal
    property bool isUrgent: urgency === NotificationUrgency.Critical
    property var image: ""
    property real materialIconScale: 0.57
    property real appIconScale: 0.8
    property real smallAppIconScale: 0.49
    property real materialIconSize: implicitSize * materialIconScale
    property real appIconSize: implicitSize * appIconScale
    property real smallAppIconSize: implicitSize * smallAppIconScale

    implicitSize: 38 * scale
    readonly property string effectiveAppIcon: {
        const rawIcon = String(root.appIcon || (String(root.image || "").startsWith("image://icon/") ? String(root.image).slice("image://icon/".length).split("?")[0] : ""));
        if (!rawIcon) return "";
        if (rawIcon.startsWith("/") || rawIcon.startsWith("file://")) return rawIcon;
        return (Quickshell.iconPath(rawIcon, true).length > 0 && !rawIcon.includes("image-missing")) ? rawIcon : "";
    }
    readonly property string effectiveAppIconSource: {
        if (!root.effectiveAppIcon) return "";
        if (root.effectiveAppIcon.startsWith("/")) return "file://" + root.effectiveAppIcon;
        if (root.effectiveAppIcon.startsWith("file://")) return root.effectiveAppIcon;
        return Quickshell.iconPath(root.effectiveAppIcon, "image-missing");
    }
    readonly property string effectiveImage: {
        const rawImage = String(root.image || "");
        if (!rawImage || rawImage.startsWith("image://icon/")) return "";
        return rawImage;
    }
    property list<var> urgentShapes: [
        MaterialShape.Shape.VerySunny,
        MaterialShape.Shape.SoftBurst,
    ]
    shape: isUrgent ? urgentShapes[Math.floor(Math.random() * urgentShapes.length)] : MaterialShape.Shape.Circle

    color: isUrgent ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
    Loader {
        id: materialSymbolLoader
        active: root.effectiveAppIcon == "" && root.effectiveImage == ""
        anchors.fill: parent
        sourceComponent: MaterialSymbol {
            text: {
                const defaultIcon = NotificationUtils.findSuitableMaterialSymbol("")
                const guessedIcon = NotificationUtils.findSuitableMaterialSymbol(root.summary)
                return (root.urgency == NotificationUrgency.Critical && guessedIcon === defaultIcon) ?
                    "priority_high" : guessedIcon
            }
            anchors.fill: parent
            color: isUrgent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            iconSize: root.materialIconSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    Loader {
        id: appIconLoader
        active: root.effectiveImage == "" && root.effectiveAppIcon != ""
        anchors.centerIn: parent
        sourceComponent: IconImage {
            id: appIconImage
            implicitSize: root.appIconSize
            asynchronous: true
            source: root.effectiveAppIconSource
        }
    }
    Loader {
        id: notifImageLoader
        active: root.effectiveImage != ""
        anchors.fill: parent
        sourceComponent: Item {
            anchors.fill: parent
            StyledImage {
                id: notifImage
                anchors.fill: parent
                readonly property int size: parent.width

                source: root.effectiveImage
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                asynchronous: true

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: notifImage.size
                        height: notifImage.size
                        radius: Appearance.rounding.full
                    }
                }
            }
            Loader {
                id: notifImageAppIconLoader
                active: root.effectiveAppIcon != ""
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                sourceComponent: IconImage {
                    implicitSize: root.smallAppIconSize
                    asynchronous: true
                    source: root.effectiveAppIconSource
                }
            }
        }
    }
}