import "quickshellBar"
import qs
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    property bool opened: false
    property bool editing: false
    onOpenedChanged: if (!opened) editing = false
    readonly property var apps: {
        // byId alone does not notify when the desktop database finishes loading.
        const entries = DesktopEntries.applications.values;
        return Config.options.launcher.pinnedApps.map(id => entries.find(entry =>
            entry.id.replace(/\.desktop$/, "") === id.replace(/\.desktop$/, ""))
            ?? DesktopEntries.byId(id)).filter(entry => entry !== null && entry !== undefined);
    }

    readonly property var otherApps: apps

    function appStyle(app) {
        const id = app.id.toLowerCase();
        if (id.includes("kitty") || id.includes("terminal"))
            return { icon: "terminal", color: "#a8dcc1", label: "Терминал" };
        if (id.includes("trip-scheduler"))
            return { icon: "travel_explore", color: "#9ed7e0", label: "Путешествия и маршруты" };
        if (id.includes("wander-mark"))
            return { icon: "edit_note", color: "#c9d99c", label: "Заметки · Markdown" };
        if (id.includes("dolphin"))
            return { icon: "folder_open", color: "#a9cdf4", label: "Файлы" };
        if (id.includes("deadlock"))
            return { icon: "sports_esports", color: "#e5bd82", label: "Steam · игры" };
        if (id.includes("cmake"))
            return { icon: "deployed_code", color: "#f1bd99", label: "Сборка проектов" };
        if (id.includes("insight-book"))
            return { icon: "auto_stories", color: "#d4bffa", label: "Книги и языки" };
        return { icon: "apps", color: Appearance.m3colors.m3primary, label: "Приложение" };
    }

    function launch(app) {
        opened = false;
        app.execute();
    }

    function openAssistant() {
        root.opened = false;
        Qt.callLater(() => GlobalStates.sidebarLeftOpen = true);
    }

    function openSrs() {
        const screenName = root.QsWindow.window?.screen?.name;
        root.opened = false;
        Qt.callLater(() => SrsService.showPopup(screenName));
    }

    implicitWidth: Config.options.bar.vertical ? 36 : 40
    implicitHeight: Config.options.bar.vertical ? 36 : 32
    buttonRadius: Appearance.rounding.full
    toggled: opened
    colBackgroundToggled: Appearance.colors.colPrimaryContainer
    colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
    colRippleToggled: Appearance.colors.colPrimaryContainerActive
    onClicked: opened = !opened

    MaterialSymbol {
        renderType: Text.QtRendering
        renderTypeQuality: Text.HighRenderTypeQuality
        font.hintingPreference: Font.PreferNoHinting
        anchors.centerIn: parent
        text: "apps"
        iconSize: 20
        color: root.opened ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0
    }

    // Native Button input avoids the custom RippleButton MouseArea in scrolling content.
    component MenuButton: Button {
        id: control
        property real buttonRadius: 16
        property color colBackground: Appearance.colors.colLayer1
        property color colBackgroundHover: Appearance.colors.colLayer1Hover
        property color colRipple: colBackgroundHover
        property bool toggled: false
        hoverEnabled: true
        padding: 0
        background: Rectangle {
            radius: control.buttonRadius
            color: control.down ? Qt.darker(control.colBackgroundHover, 1.08)
                : control.hovered ? control.colBackgroundHover : control.colBackground
            border.width: control.activeFocus ? 1 : 0
            border.color: Appearance.m3colors.m3primary
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() { root.opened = false; }
    }

    PanelWindow {
        id: popup
        visible: root.opened
        color: "transparent"
        implicitWidth: Math.min(672, (screen?.width ?? 1920) - Appearance.sizes.baseVerticalBarWidth - 24)
        implicitHeight: Math.min(menu.implicitHeight + 36, (root.QsWindow.window?.screen?.height ?? 800) * 0.7)
        screen: root.QsWindow.window?.screen ?? Quickshell.screens[0]
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:favorites"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors {
            top: Config.options.bar.vertical || !Config.options.bar.bottom
            bottom: !Config.options.bar.vertical && Config.options.bar.bottom
            left: !Config.options.bar.vertical || !Config.options.bar.bottom
            right: Config.options.bar.vertical && Config.options.bar.bottom
        }
        margins {
            left: Config.options.bar.vertical ? 4
                : Math.max(12, Math.min((root.QsWindow.window?.mapFromItem(root, 0, 0).x ?? 12), (popup.screen?.width ?? 1920) - popup.implicitWidth - 12))
            right: 4
            top: Config.options.bar.vertical
                ? Math.max(12, Math.min((root.QsWindow.window?.mapFromItem(root, 0, 0).y ?? 12), (popup.screen?.height ?? 1080) - popup.implicitHeight - 12))
                : Appearance.sizes.barHeight + 8
            bottom: Appearance.sizes.barHeight + 8
        }
        mask: Region { item: frame }
        Component.onDestruction: GlobalFocusGrab.removeDismissable(popup)
        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(popup);
                frame.forceActiveFocus();
            } else {
                GlobalFocusGrab.removeDismissable(popup);
            }
        }

        Rectangle {
            id: frame
            anchors.fill: parent
            color: Appearance.m3colors.m3surfaceContainer
            radius: 24
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            Keys.onEscapePressed: root.opened = false

            Flickable {
                id: viewport
                anchors.fill: parent
                anchors.margins: 18
                contentWidth: width
                contentHeight: menu.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: menu
                    width: viewport.width
                    spacing: 12

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 50
                        Column {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            width: parent.width - 52
                            spacing: 3
                            StyledText {
                                renderType: Text.QtRendering
                                renderTypeQuality: Text.HighRenderTypeQuality
                                font.hintingPreference: Font.PreferNoHinting
                                text: "БЫСТРЫЙ ДОСТУП"
                                font.pixelSize: 11
                                font.letterSpacing: 1.8
                                color: Appearance.m3colors.m3onSurfaceVariant
                            }
                            StyledText {
                                renderType: Text.QtRendering
                                renderTypeQuality: Text.HighRenderTypeQuality
                                font.hintingPreference: Font.PreferNoHinting
                                width: parent.width
                                text: root.editing ? "Собери своё меню" : "Твои приложения"
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }
                        MenuButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36
                            height: 36
                            colBackground: root.editing ? Appearance.m3colors.m3primary : Appearance.colors.colLayer1
                            colBackgroundHover: root.editing ? Qt.lighter(Appearance.m3colors.m3primary, 1.1) : Appearance.colors.colLayer1Hover
                            buttonRadius: 12
                            toggled: root.editing
                            onClicked: root.editing = !root.editing
                            contentItem: MaterialSymbol {
                                renderType: Text.QtRendering
                                renderTypeQuality: Text.HighRenderTypeQuality
                                font.hintingPreference: Font.PreferNoHinting
                                text: root.editing ? "check" : "tune"
                                iconSize: 19
                                horizontalAlignment: Text.AlignHCenter
                                color: root.editing ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurfaceVariant
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: root.editing ? "Готово" : "Изменить избранное"
                        }
                    }

                    RowLayout {
                        visible: !root.editing
                        Layout.fillWidth: true
                        spacing: 10
                        ShellActionButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            label: "Нейронка"
                            description: "Чат и помощник"
                            symbol: "auto_awesome"
                            accent: "#d4bffa"
                            trigger: () => root.openAssistant()
                        }
                        ShellActionButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            label: "Повторение · SRS"
                            description: "Слова и карточки"
                            symbol: "style"
                            accent: "#a8dcc1"
                            trigger: () => root.openSrs()
                        }
                    }

                    TextField {
                        id: search
                        visible: root.editing
                        Layout.fillWidth: true
                        implicitHeight: 40
                        leftPadding: 12
                        placeholderText: "Найти приложение…"
                        renderType: TextInput.QtRendering
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                        font.hintingPreference: Font.PreferNoHinting
                        color: Appearance.m3colors.m3onSurface
                        placeholderTextColor: Appearance.m3colors.m3onSurfaceVariant
                        background: Rectangle {
                            radius: 12
                            color: Appearance.colors.colLayer1
                            border.width: search.activeFocus ? 1 : 0
                            border.color: Appearance.m3colors.m3primary
                        }
                        onVisibleChanged: if (!visible) text = ""
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: viewport.width >= 560 ? 3 : 2
                        rowSpacing: 10
                        columnSpacing: 10
                        Repeater {
                            model: root.editing
                                ? DesktopEntries.applications.values.filter(app => app.name.toLowerCase().includes(search.text.toLowerCase())).sort((a, b) => a.name.localeCompare(b.name))
                                : root.otherApps
                            delegate: MenuButton {
                                id: tile
                                required property var modelData
                                required property int index
                                readonly property var style: root.appStyle(modelData)
                                Layout.fillWidth: true
                                Layout.preferredWidth: 145
                                Layout.columnSpan: 1
                                implicitHeight: 104
                                padding: 0
                                buttonRadius: 17
                                colBackground: Appearance.colors.colLayer1
                                colBackgroundHover: Appearance.colors.colLayer1Hover
                                onClicked: {
                                    if (root.editing) LauncherApps.togglePin(modelData.id);
                                    else root.launch(modelData);
                                }
                                contentItem: Item {
                                    Rectangle {
                                        x: 13; y: 12
                                        width: 33; height: 33; radius: 11
                                        color: Qt.alpha(tile.style.color, 0.15)
                                        MaterialSymbol {
                                            renderType: Text.QtRendering
                                            renderTypeQuality: Text.HighRenderTypeQuality
                                            font.hintingPreference: Font.PreferNoHinting
                                            anchors.centerIn: parent
                                            text: tile.style.icon
                                            iconSize: 21
                                            color: tile.style.color
                                        }
                                    }
                                    MaterialSymbol {
                                        renderType: Text.QtRendering
                                        renderTypeQuality: Text.HighRenderTypeQuality
                                        font.hintingPreference: Font.PreferNoHinting
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 13
                                        text: root.editing
                                            ? (LauncherApps.isPinned(tile.modelData.id) ? "star" : "add")
                                            : "arrow_outward"
                                        iconSize: 15
                                        color: root.editing && LauncherApps.isPinned(tile.modelData.id)
                                            ? tile.style.color : Appearance.m3colors.m3onSurfaceVariant
                                        opacity: root.editing || tile.hovered ? 1 : 0.4
                                    }
                                    Column {
                                        x: 13; y: 56
                                        width: parent.width - 26
                                        spacing: 3
                                        StyledText {
                                            renderType: Text.QtRendering
                                            renderTypeQuality: Text.HighRenderTypeQuality
                                            font.hintingPreference: Font.PreferNoHinting
                                            width: parent.width
                                            text: tile.modelData.name
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            renderType: Text.QtRendering
                                            renderTypeQuality: Text.HighRenderTypeQuality
                                            font.hintingPreference: Font.PreferNoHinting
                                            width: parent.width
                                            text: tile.style.label
                                            font.pixelSize: 11
                                            color: Appearance.m3colors.m3onSurfaceVariant
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        renderType: Text.QtRendering
                        renderTypeQuality: Text.HighRenderTypeQuality
                        font.hintingPreference: Font.PreferNoHinting
                        visible: !root.editing && root.apps.length === 0
                        Layout.fillWidth: true
                        Layout.margins: 8
                        text: "Добавь любимые приложения\nкнопкой в правом верхнем углу."
                        wrapMode: Text.WordWrap
                    }

                }
            }
        }
    }
}
