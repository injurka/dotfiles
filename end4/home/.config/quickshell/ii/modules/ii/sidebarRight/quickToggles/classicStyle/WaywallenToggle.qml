import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io

QuickToggleButton {
    id: root

    property bool waywallenInstalled: false
    property bool rendererRunning: false
    property bool pausedByToggle: false

    visible: waywallenInstalled
    toggled: rendererRunning && !pausedByToggle
    buttonIcon: "wallpaper"

    function openWaywallen() {
        GlobalStates.sidebarRightOpen = false;
        Quickshell.execDetached([Directories.scriptPath + "/waywallen.sh", "--open"]);
    }

    onClicked: {
        if (!rendererRunning) {
            openWaywallen();
            return;
        }

        if (playbackControl.running) return;

        playbackControl.pauseRequested = !pausedByToggle;
        playbackControl.command = [
            "busctl", "--user", "call",
            "org.waywallen.waywallen.Daemon",
            "/org/waywallen/waywallen/Daemon",
            "org.waywallen.waywallen.Daemon1",
            playbackControl.pauseRequested ? "Pause" : "Resume"
        ];
        playbackControl.running = true;
    }

    altAction: () => openWaywallen()

    Process {
        id: installationCheck
        command: [Directories.scriptPath + "/waywallen.sh", "--check"]
        running: true
        onExited: (exitCode, exitStatus) => {
            root.waywallenInstalled = exitCode === 0;
            if (root.waywallenInstalled && !rendererCheck.running)
                rendererCheck.running = true;
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            if (!installationCheck.running) installationCheck.running = true;
        }
    }

    Timer {
        interval: 2000
        running: root.waywallenInstalled
        repeat: true
        onTriggered: {
            if (!rendererCheck.running) rendererCheck.running = true;
        }
    }

    Process {
        id: rendererCheck
        command: ["pgrep", "-f", "[/]waywallen-layer-shell"]
        onExited: (exitCode, exitStatus) => {
            const wasRunning = root.rendererRunning;
            root.rendererRunning = exitCode === 0;
            if (!root.rendererRunning || !wasRunning) root.pausedByToggle = false;
        }
    }

    Process {
        id: playbackControl
        property bool pauseRequested: false
        command: []
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.pausedByToggle = pauseRequested;
            } else {
                console.warn("Waywallen playback control failed", exitCode, exitStatus);
            }
        }
    }

    StyledToolTip {
        text: Translation.tr("Waywallen | click to launch or pause/resume, right-click to open")
    }
}
