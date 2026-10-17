import QtQuick
import Quickshell.Io
import qs.modules.common.models.hyprland
import qs.services

QuickToggleModel {
    id: root
    name: Translation.tr("Game mode")
    toggled: confOpt.value !== undefined && !confOpt.value
    icon: "gamepad"

    // Use the same entry point as Super + Alt + G.
    mainAction: () => {
        if (!toggleProc.running) toggleProc.running = true;
    }

    Process {
        id: toggleProc
        command: ["bash", "-c", 'exec bash "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/custom/scripts/end4-game-mode.sh"']
        onExited: (exitCode, exitStatus) => {
            confOpt.fetch();
            if (exitCode !== 0) console.warn("Game mode toggle failed:", exitCode);
        }
    }

    HyprlandConfigOption {
        id: confOpt
        key: "animations:enabled"
    }

    tooltipText: Translation.tr("Game mode")
}
