pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.sidebarRight.calendar
import qs.modules.ii.sidebarRight.todo
import qs.modules.ii.sidebarRight.pomodoro
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    clip: true
    implicitHeight: collapsed ? collapsedBottomWidgetGroupRow.implicitHeight : 350
    signal openTimerSettings()
    property int selectedTab: Persistent.states.sidebar.bottomGroup.tab
    readonly property int safeSelectedTab: Math.max(0, Math.min(selectedTab, tabs.length - 1))
    property bool collapsed: Persistent.states.sidebar.bottomGroup.collapsed
    property bool pendingScheduleOpen: false
    property var tabs: [
        {
            "type": "calendar",
            "name": Translation.tr("Calendar"),
            "icon": "calendar_month",
            "widget": "calendar/CalendarWidget.qml"
        },
        {
            "type": "todo",
            "name": Translation.tr("To Do"),
            "icon": "done_outline",
            "widget": "todo/TodoWidget.qml"
        },
        {
            "type": "timer",
            "name": Translation.tr("Timer"),
            "icon": "schedule",
            "widget": "pomodoro/PomodoroWidget.qml"
        },
    ]

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    function setCollapsed(state) {
        Persistent.states.sidebar.bottomGroup.collapsed = state;
        if (collapsed) {
            bottomWidgetGroupRow.opacity = 0;
        } else {
            collapsedBottomWidgetGroupRow.opacity = 0;
        }
        collapseCleanFadeTimer.start();
    }

    function openSchedule() {
        selectedTab = 0;
        Persistent.states.sidebar.bottomGroup.tab = 0;
        setCollapsed(false);
        if (tabStack.status === Loader.Ready && tabStack.item
                && typeof tabStack.item.openSchedule === "function") {
            pendingScheduleOpen = false;
            tabStack.item.openSchedule();
        } else {
            pendingScheduleOpen = true;
        }
    }

    Timer {
        id: collapseCleanFadeTimer
        interval: Appearance.animation.elementMove.duration / 2
        repeat: false
        onTriggered: {
            if (collapsed)
                collapsedBottomWidgetGroupRow.opacity = 1;
            else
                bottomWidgetGroupRow.opacity = 1;
        }
    }

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                root.selectedTab = Math.min(root.safeSelectedTab + 1, root.tabs.length - 1);
            } else if (event.key === Qt.Key_PageUp) {
                root.selectedTab = Math.max(root.safeSelectedTab - 1, 0);
            }
            event.accepted = true;
        }
    }

    // The thing when collapsed
    RowLayout {
        id: collapsedBottomWidgetGroupRow
        anchors.left: parent.left
        anchors.right: parent.right
        opacity: collapsed ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                id: collapsedBottomWidgetGroupRowFade
                duration: Appearance.animation.elementMove.duration / 2
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        spacing: 15

        CalendarHeaderButton {
            Layout.margins: 10
            Layout.rightMargin: 0
            forceCircle: true
            downAction: () => {
                root.setCollapsed(false);
            }
            contentItem: MaterialSymbol {
                text: "keyboard_arrow_up"
                iconSize: Appearance.font.pixelSize.larger
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colOnLayer1
            }
        }

        StyledText {
            property int remainingTasks: Todo.list.filter(task => !task.done).length
            Layout.margins: 10
            Layout.leftMargin: 0
            Layout.fillWidth: true
            text: remainingTasks > 0
                ? Translation.tr("%1   •   %2 tasks").arg(DateTime.collapsedCalendarFormat).arg(remainingTasks)
                : DateTime.collapsedCalendarFormat
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
        }

        CalendarHeaderButton {
            Layout.rightMargin: 10
            forceCircle: true
            tooltipText: Translation.tr("Schedule")
            Accessible.name: Translation.tr("Schedule")
            downAction: () => root.openSchedule()
            contentItem: MaterialSymbol {
                text: "open_in_full"
                iconSize: Appearance.font.pixelSize.larger
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colOnLayer1
            }
        }
    }

    // The thing when expanded
    RowLayout {
        id: bottomWidgetGroupRow

        opacity: collapsed ? 0 : 1
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                id: bottomWidgetGroupRowFade
                duration: Appearance.animation.elementMove.duration / 2
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        anchors.fill: parent
        // implicitHeight: tabStack.implicitHeight
        spacing: 20

        // Navigation rail
        Item {
            Layout.fillHeight: true
            Layout.fillWidth: false
            Layout.leftMargin: 10
            Layout.topMargin: 10
            implicitWidth: tabBar.implicitWidth
            // Navigation rail buttons
            NavigationRailTabArray {
                id: tabBar
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 5
                currentIndex: root.safeSelectedTab
                expanded: false
                Repeater {
                    model: root.tabs
                    NavigationRailButton {
                        required property int index
                        required property var modelData
                        showToggledHighlight: false
                        toggled: root.safeSelectedTab == index
                        buttonText: modelData.name
                        buttonIcon: modelData.icon
                        onPressed: {
                            root.selectedTab = index;
                            Persistent.states.sidebar.bottomGroup.tab = index;
                        }
                    }
                }
            }
            // Collapse button
            CalendarHeaderButton {
                anchors.left: parent.left
                anchors.top: parent.top
                forceCircle: true
                downAction: () => {
                    root.setCollapsed(true);
                }
                contentItem: MaterialSymbol {
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        // Content area
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // implicitHeight: tabStack.implicitHeight

            Loader {
                id: tabStack
                anchors.fill: parent
                anchors.bottomMargin: -anchors.topMargin
                source: Qt.resolvedUrl(root.tabs[root.safeSelectedTab].widget)
                onLoaded: {
                    if (root.pendingScheduleOpen) {
                        root.pendingScheduleOpen = false;
                        item.openSchedule();
                    }
                }
                onStatusChanged: if (status === Loader.Error)
                                     console.warn("[BottomWidgetGroup] Failed to load widget:", source)

                Connections {
                    target: tabStack.item
                    ignoreUnknownSignals: true
                    function onOpenTimerSettings() { root.openTimerSettings() }
                }
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - 24
                visible: tabStack.status === Loader.Error
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Could not load widget")
            }
        }
    }
}
