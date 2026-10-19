pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var state: ({ available: false, active: false, config: {}, capabilities: {}, errors: [] })
    readonly property bool available: state.available ?? false
    readonly property bool active: state.active ?? false
    readonly property bool busy: worker.running
    readonly property var config: state.config ?? ({})
    readonly property var capabilities: state.capabilities ?? ({})
    readonly property string errorText: (state.errors ?? []).join("\n")

    property var pendingPatch: ({})
    function request(action, patch) {
        if (worker.running) {
            if (action === "configure") pendingPatch = Object.assign({}, pendingPatch, patch);
            return;
        }
        worker.command = ["python3", Quickshell.shellPath("scripts/power-saving/controller.py"), action];
        if (patch !== undefined) worker.command = [...worker.command, JSON.stringify(patch)];
        worker.running = true;
    }
    function configure(key, value) {
        const patch = {};
        patch[key] = value;
        request("configure", patch);
    }
    function toggle() { request("toggle"); }

    Process {
        id: worker
        stderr: StdioCollector { id: workerError }
        onExited: (exitCode, exitStatus) => {
            Qt.callLater(() => {
                if (Object.keys(root.pendingPatch).length === 0) return;
                const patch = root.pendingPatch;
                root.pendingPatch = {};
                root.request("configure", patch);
            });
            if (exitCode !== 0) root.state = Object.assign({}, root.state, {
                errors: [workerError.text || "Failed to start power saving controller"]
            });
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.state = JSON.parse(text); }
                catch (e) { root.state = Object.assign({}, root.state, { errors: ["Failed to read power saving state"] }); }
            }
        }
    }
    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.request("tick")
    }
    Component.onCompleted: request("tick")
}
