pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    function memoryRows(used, free, total) {
        return [
            { icon: "clock_loader_60", label: "Used:", value: ResourceUsage.kbToGbString(used) },
            { icon: "check_circle", label: "Free:", value: ResourceUsage.kbToGbString(free) },
            { icon: "empty_dashboard", label: "Total:", value: ResourceUsage.kbToGbString(total) }
        ];
    }

    readonly property var sections: {
        const hardware = ResourceUsage.hardware;
        const sections = [{ icon: "memory", label: "RAM", rows: memoryRows(ResourceUsage.memoryUsed, ResourceUsage.memoryFree, ResourceUsage.memoryTotal) }];
        if (ResourceUsage.swapTotal > 0)
            sections.push({ icon: "swap_horiz", label: "Swap", rows: memoryRows(ResourceUsage.swapUsed, ResourceUsage.swapFree, ResourceUsage.swapTotal) });
        sections.push({ icon: "planner_review", label: "CPU", rows: [
            { icon: "bolt", label: "Load:", value: `${Math.round(ResourceUsage.cpuUsage * 100)}%` },
            ...hardware.cpu
        ] });
        if (hardware.gpu.length > 0)
            sections.push({ icon: "developer_board", label: "GPU", rows: hardware.gpu });
        if (hardware.board.length > 0)
            sections.push({ icon: "developer_board", label: "Motherboard", rows: hardware.board });
        if (hardware.storage.length > 0)
            sections.push({ icon: "hard_drive", label: "Storage", rows: hardware.storage });
        return sections;
    }

    GridLayout {
        anchors.centerIn: parent
        columns: 3
        columnSpacing: 8
        rowSpacing: 8

        Repeater {
            model: root.sections

            Rectangle {
                id: section
                required property var modelData
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerHigh
                implicitWidth: sectionContent.implicitWidth + 60
                implicitHeight: sectionContent.implicitHeight + 28

                ColumnLayout {
                    id: sectionContent
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 6

                    StyledPopupHeaderRow {
                        icon: section.modelData.icon
                        label: Translation.tr(section.modelData.label)
                    }

                    Repeater {
                        model: section.modelData.rows

                        StyledPopupValueRow {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            icon: modelData.icon
                            label: Translation.tr(modelData.label)
                            value: modelData.value
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
