import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

StyledTextArea {
    id: root
    property string markdown: ""
    property bool error: false
    property string renderedHtml: ""
    property string renderedRequest: ""
    readonly property string renderRequest: JSON.stringify({
        markdown: markdown,
        accent: Appearance.colors.colPrimary.toString(),
        foreground: Appearance.colors.colOnLayer1.toString(),
        surface: Appearance.colors.colLayer3.toString()
    })
    readonly property bool formatted: !error && renderedRequest === renderRequest
    onRenderRequestChanged: renderDelay.restart()
    onErrorChanged: renderDelay.restart()
    Component.onCompleted: renderDelay.restart()

    text: formatted ? renderedHtml : markdown
    textFormat: formatted ? TextEdit.RichText : TextEdit.PlainText
    color: error ? Appearance.colors.colError : Appearance.colors.colOnLayer1
    renderType: Text.QtRendering
    font.hintingPreference: Font.PreferNoHinting
    wrapMode: TextEdit.Wrap
    readOnly: true
    selectByMouse: true
    padding: 0
    background: null
    onLinkActivated: link => {
        if (/^(https?:|mailto:)/i.test(link)) Qt.openUrlExternally(link)
    }

    Timer {
        id: renderDelay
        interval: 40
        onTriggered: {
            if (root.error || !root.markdown || formatter.running) return
            formatter.request = root.renderRequest
            formatter.stdinEnabled = true
            formatter.running = true
        }
    }
    Process {
        id: formatter
        property string request: ""
        command: [Quickshell.env("HOME") + "/.bun/bin/bun", Directories.scriptPath + "/voice-assistant/render-markdown.ts"]
        onStarted: {
            write(request)
            stdinEnabled = false
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (formatter.request !== root.renderRequest) return
                try {
                    const result = JSON.parse(text)
                    root.renderedHtml = result.html
                    root.renderedRequest = formatter.request
                } catch (e) {
                    console.warn("Voice response formatting failed; showing plain text")
                }
            }
        }
        onExited: {
            if (request !== root.renderRequest) renderDelay.restart()
        }
    }
}
