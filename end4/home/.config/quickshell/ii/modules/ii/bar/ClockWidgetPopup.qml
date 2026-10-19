import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    readonly property string dayNumber: Qt.locale().toString(DateTime.clock.date, "d")
    readonly property string weekday: Qt.locale().toString(DateTime.clock.date, "dddd")
    readonly property string monthYear: Qt.locale().toString(DateTime.clock.date, "MMMM yyyy")
    property string formattedUptime: DateTime.uptime
    readonly property bool hasPendingTasks: Todo.list.some(item => !item.done)
    property string todosSection: getUpcomingTodos()

    function getUpcomingTodos() {
        const unfinishedTodos = Todo.list.filter(function (item) {
            return !item.done;
        });
        if (unfinishedTodos.length === 0) {
            return Translation.tr("No pending tasks");
        }

        // Limit to first 5 todos to keep popup manageable
        const limitedTodos = unfinishedTodos.slice(0, 5);
        let todoText = limitedTodos.map(function (item, index) {
            return `  ${index + 1}. ${item.content}`;
        }).join('\n');

        if (unfinishedTodos.length > 5) {
            todoText += `\n  ${Translation.tr("... and %1 more").arg(unfinishedTodos.length - 5)}`;
        }

        return todoText;
    }

    ColumnLayout {
        id: content
        anchors.centerIn: parent
        implicitWidth: 300
        width: implicitWidth
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            StyledText {
                Layout.preferredWidth: 42
                horizontalAlignment: Text.AlignHCenter
                text: root.dayNumber
                font {
                    pixelSize: 36
                    weight: Font.DemiBold
                }
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: root.weekday
                    elide: Text.ElideRight
                    font {
                        pixelSize: Appearance.font.pixelSize.large
                        weight: Font.DemiBold
                    }
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.monthYear
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.6
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: "timelapse"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("System uptime:")
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                text: root.formattedUptime
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        // Tasks
        Column {
            spacing: 0
            Layout.fillWidth: true

            StyledPopupValueRow {
                icon: "checklist"
                label: Translation.tr("To Do:")
                value: root.hasPendingTasks ? "" : root.todosSection
            }

            StyledText {
                visible: root.hasPendingTasks
                width: parent.width
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnSurfaceVariant
                text: root.todosSection
            }
        }
    }
}
