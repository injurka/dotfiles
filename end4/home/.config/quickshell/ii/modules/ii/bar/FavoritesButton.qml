import "quickshellBar"
import qs
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    property bool opened: false
    property bool editing: false
    // One theme-derived accent; spacing and shape are shared by all launch targets.
    readonly property color menuAccent: Appearance.m3colors.m3primary
    readonly property int menuRadius: 12
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
            return { icon: "terminal", label: "Терминал" };
        if (id.includes("trip-scheduler"))
            return { icon: "travel_explore", label: "Путешествия и маршруты" };
        if (id.includes("wander-mark"))
            return { icon: "edit_note", label: "Заметки · Markdown" };
        if (id.includes("dolphin"))
            return { icon: "folder_open", label: "Файлы" };
        if (id.includes("deadlock"))
            return { icon: "sports_esports", label: "Steam · игры" };
        if (id.includes("cmake"))
            return { icon: "deployed_code", label: "Сборка проектов" };
        if (id.includes("insight-book"))
            return { icon: "auto_stories", label: "Книги и языки" };
        if (id.includes("antigravity"))
            return { icon: "rocket_launch", label: "AI IDE & Агент" };
        if (id.includes("codex") || id.includes("chatgpt"))
            return { icon: "forum", label: "Чат-ассистент" };
        if (id.includes("hermes"))
            return { icon: "psychology", label: "Автономный агент" };
        if (id.includes("zcode") || id.includes("zai"))
            return { icon: "code", label: "IDE & разработка" };
        return { icon: "apps", label: "Приложение" };
    }

    Process {
        id: cmdLauncher
        function run(cmd) {
            command = ["bash", "-c", "nohup " + cmd + " >/dev/null 2>&1 &"];
            running = true;
        }
    }

    function launch(app) {
        opened = false;
        app.execute();
    }

    function launchAiApp(desktopId, fallbackCmd) {
        root.opened = false;
        const entry = DesktopEntries.byId(desktopId)
            ?? DesktopEntries.byId(desktopId + ".desktop")
            ?? DesktopEntries.applications.values.find(e =>
                e.id.replace(/\.desktop$/, "").toLowerCase() === desktopId.replace(/\.desktop$/, "").toLowerCase());
        if (entry) {
            entry.execute();
        } else if (fallbackCmd) {
            cmdLauncher.run(fallbackCmd);
        }
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
        property real buttonRadius: root.menuRadius
        property color colBackground: Appearance.colors.colLayer1
        property color colBackgroundHover: Appearance.colors.colLayer1Hover
        property color colRipple: colBackgroundHover
        property bool toggled: false
        hoverEnabled: true
        Accessible.name: ToolTip.text
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

    component SectionHeader: RowLayout {
        id: secHeader
        property string title: ""
        property string icon: ""
        property string badge: ""
        property color accent: Appearance.m3colors.m3onSurfaceVariant
        Layout.fillWidth: true
        Layout.topMargin: 8
        Layout.bottomMargin: 0
        spacing: 7

        MaterialSymbol {
            visible: secHeader.icon !== ""
            renderType: Text.QtRendering
            renderTypeQuality: Text.HighRenderTypeQuality
            font.hintingPreference: Font.PreferNoHinting
            text: secHeader.icon
            iconSize: 15
            color: secHeader.accent
        }

        StyledText {
            renderType: Text.QtRendering
            renderTypeQuality: Text.HighRenderTypeQuality
            font.hintingPreference: Font.PreferNoHinting
            text: secHeader.title
            font.pixelSize: 12
            font.letterSpacing: 0
            font.weight: Font.DemiBold
            color: secHeader.accent
        }

        Item { Layout.fillWidth: true }

        Rectangle {
            visible: secHeader.badge !== ""
            implicitHeight: 18
            implicitWidth: badgeText.implicitWidth + 14
            radius: 9
            color: Qt.alpha(secHeader.accent, 0.12)

            StyledText {
                id: badgeText
                anchors.centerIn: parent
                renderType: Text.QtRendering
                renderTypeQuality: Text.HighRenderTypeQuality
                font.hintingPreference: Font.PreferNoHinting
                text: secHeader.badge
                font.pixelSize: 10
                font.weight: Font.Medium
                color: secHeader.accent
            }
        }
    }

    component AiCard: Button {
        id: card
        property real buttonRadius: root.menuRadius
        property string label: ""
        property string description: ""
        property string symbol: "auto_awesome"
        property var trigger: () => {}
        property bool featured: false

        Layout.fillWidth: true
        implicitHeight: featured ? 68 : 60
        padding: 0
        hoverEnabled: true
        Accessible.name: label
        Accessible.description: description

        background: Rectangle {
            radius: card.buttonRadius
            color: card.down ? Qt.darker(Appearance.colors.colLayer1Hover, 1.08)
                : card.hovered ? Appearance.colors.colLayer1Hover
                : card.featured ? Appearance.colors.colPrimaryContainer : "transparent"
            border.width: card.activeFocus ? 2 : 0
            border.color: root.menuAccent

            Behavior on border.color { ColorAnimation { duration: 150 } }
            Behavior on color { ColorAnimation { duration: 150 } }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        onClicked: trigger()

        contentItem: Item {
            Rectangle {
                id: iconContainer
                anchors.left: parent.left
                anchors.leftMargin: 13
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                radius: 12
                color: card.featured ? Qt.alpha(root.menuAccent, 0.12) : "transparent"

                MaterialSymbol {
                    renderType: Text.QtRendering
                    renderTypeQuality: Text.HighRenderTypeQuality
                    font.hintingPreference: Font.PreferNoHinting
                    anchors.centerIn: parent
                    text: card.symbol
                    iconSize: card.featured ? 23 : 20
                    color: card.featured ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurfaceVariant
                }
            }

            Column {
                anchors.left: iconContainer.right
                anchors.leftMargin: 12
                anchors.right: indicatorIcon.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                StyledText {
                    renderType: Text.QtRendering
                    renderTypeQuality: Text.HighRenderTypeQuality
                    font.hintingPreference: Font.PreferNoHinting
                    width: parent.width
                    text: card.label
                    color: card.featured ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                StyledText {
                    renderType: Text.QtRendering
                    renderTypeQuality: Text.HighRenderTypeQuality
                    font.hintingPreference: Font.PreferNoHinting
                    width: parent.width
                    text: card.description
                    font.pixelSize: 11
                    color: card.featured ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurfaceVariant
                    elide: Text.ElideRight

                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            MaterialSymbol {
                id: indicatorIcon
                renderType: Text.QtRendering
                renderTypeQuality: Text.HighRenderTypeQuality
                font.hintingPreference: Font.PreferNoHinting
                anchors.right: parent.right
                anchors.rightMargin: 13
                anchors.verticalCenter: parent.verticalCenter
                text: "arrow_forward"
                iconSize: 15
                color: card.featured ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurfaceVariant
                opacity: card.hovered || card.activeFocus || card.featured ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() { root.opened = false; }
    }

    PanelWindow {
        id: popup
        visible: root.opened
        color: "transparent"
        implicitWidth: Math.min(560, (screen?.width ?? 1920) - Appearance.sizes.baseVerticalBarWidth - 24)
        implicitHeight: Math.min(menu.implicitHeight + 40, (root.QsWindow.window?.screen?.height ?? 800) * 0.85)
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
            radius: 20
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            Keys.onEscapePressed: root.opened = false

            Flickable {
                id: viewport
                anchors.fill: parent
                anchors.margins: 20
                contentWidth: width
                contentHeight: menu.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: menu
                    width: viewport.width
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 60
                        Column {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            width: parent.width - 52
                            spacing: 3
                            StyledText {
                                renderType: Text.QtRendering
                                renderTypeQuality: Text.HighRenderTypeQuality
                                font.hintingPreference: Font.PreferNoHinting
                                width: parent.width
                                text: root.editing ? "Избранные приложения" : "Быстрый доступ"
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StyledText {
                                renderType: Text.QtRendering
                                renderTypeQuality: Text.HighRenderTypeQuality
                                font.hintingPreference: Font.PreferNoHinting
                                width: parent.width
                                elide: Text.ElideRight
                                text: root.editing ? "Выбери приложения для быстрого доступа" : "Твои приложения и инструменты"
                                font.pixelSize: 11
                                font.letterSpacing: 0
                                color: Appearance.m3colors.m3onSurfaceVariant
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

                    // Section 1: AI & Neural Networks
                    SectionHeader {
                        visible: !root.editing
                        title: "Ассистенты"
                        badge: ""
                    }

                    // Featured built-in assistant
                    AiCard {
                        visible: !root.editing
                        featured: true
                        label: "Нейронка"
                        description: "Встроенный ассистент · чат и контекст"
                        symbol: "auto_awesome"

                        trigger: () => root.openAssistant()
                    }

                    // 2x2 Desktop AI Applications
                    GridLayout {
                        visible: !root.editing
                        Layout.fillWidth: true
                        columns: viewport.width >= 420 ? 2 : 1
                        rowSpacing: 4
                        columnSpacing: 8

                        AiCard {
                            label: "Antigravity"
                            description: "AI IDE & Агент"
                            symbol: "rocket_launch"

                            trigger: () => root.launchAiApp("antigravity", "/home/injurka/Applications/Antigravity-x64/antigravity")
                        }

                        AiCard {
                            label: "ChatGPT"
                            description: "Десктоп-ассистент"
                            symbol: "forum"

                            trigger: () => root.launchAiApp("codex-desktop", "/usr/bin/codex-desktop")
                        }

                        AiCard {
                            label: "Hermes"
                            description: "Автономный агент"
                            symbol: "psychology"

                            trigger: () => root.launchAiApp("com.nousresearch.hermes", "/home/injurka/.local/bin/hermes desktop --skip-build")
                        }

                        AiCard {
                            label: "ZCode (Z.AI)"
                            description: "IDE & разработка"
                            symbol: "code"

                            trigger: () => root.launchAiApp("zcode", "/usr/bin/zcode")
                        }
                    }

                    // Section 2: Tools & Learning
                    SectionHeader {
                        visible: !root.editing
                        title: "Обучение"
                    }

                    AiCard {
                        visible: !root.editing
                        label: "Повторение · SRS"
                        description: "Слова и карточки интервального повторения"
                        symbol: "style"

                        trigger: () => root.openSrs()
                    }

                    // Section 3: Applications
                    SectionHeader {
                        visible: !root.editing
                        title: "Приложения"
                        badge: root.apps.length > 0 ? String(root.apps.length) : ""
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
                        columns: viewport.width >= 420 ? 2 : 1
                        rowSpacing: 4
                        columnSpacing: 8
                        Repeater {
                            model: root.editing
                                ? DesktopEntries.applications.values.filter(app => app.name.toLowerCase().includes(search.text.toLowerCase())).sort((a, b) => a.name.localeCompare(b.name))
                                : root.otherApps
                            delegate: MenuButton {
                                id: tile
                                required property var modelData
                                required property int index
                                readonly property var style: root.appStyle(modelData)
                                Accessible.name: modelData.name
                                Accessible.description: root.editing ? (LauncherApps.isPinned(modelData.id) ? "Убрать из избранного" : "Добавить в избранное") : style.label
                                Layout.fillWidth: true
                                Layout.preferredWidth: 145
                                Layout.columnSpan: 1
                                implicitHeight: 64
                                padding: 0
                                buttonRadius: root.menuRadius
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer1Hover
                                onClicked: {
                                    if (root.editing) LauncherApps.togglePin(modelData.id);
                                    else root.launch(modelData);
                                }
                                contentItem: Item {
                                    Rectangle {
                                        x: 10; y: 14
                                        width: 36; height: 36; radius: 10
                                        color: Appearance.colors.colLayer1
                                        MaterialSymbol {
                                             renderType: Text.QtRendering
                                            renderTypeQuality: Text.HighRenderTypeQuality
                                            font.hintingPreference: Font.PreferNoHinting
                                            anchors.centerIn: parent
                                            text: tile.style.icon
                                            iconSize: 21
                                            color: Appearance.m3colors.m3onSurfaceVariant
                                        }
                                    }
                                    MaterialSymbol {
                                        renderType: Text.QtRendering
                                        renderTypeQuality: Text.HighRenderTypeQuality
                                        font.hintingPreference: Font.PreferNoHinting
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.rightMargin: 10
                                        text: root.editing
                                            ? (LauncherApps.isPinned(tile.modelData.id) ? "star" : "add")
                                            : "arrow_forward"
                                        iconSize: 15
                                        color: root.editing && LauncherApps.isPinned(tile.modelData.id)
                                            ? root.menuAccent : Appearance.m3colors.m3onSurfaceVariant
                                        opacity: root.editing || tile.hovered || tile.activeFocus ? 1 : 0
                                    }
                                    Column {
                                        x: 58; anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 86
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
