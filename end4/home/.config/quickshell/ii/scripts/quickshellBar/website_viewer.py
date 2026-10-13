#!/usr/bin/env python3
"""Open InsightBook in a standalone WebKitGTK application window."""
import os
import sys

# WebKit's accelerated path hangs in this Wayland/driver combination.
os.environ.setdefault("WEBKIT_DISABLE_COMPOSITING_MODE", "1")
os.environ.setdefault("WEBKIT_DISABLE_DMABUF_RENDERER", "1")

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import Gdk, Gtk, WebKit2


class InsightBookWindow(Gtk.Window):
    def __init__(self, url):
        super().__init__(title="InsightBook")
        self.set_decorated(False)
        self.set_default_size(1280, 840)
        self.set_size_request(680, 480)
        self.connect("destroy", Gtk.main_quit)
        self.connect("key-press-event", self.on_key_press)

        self.webview = WebKit2.WebView()
        self.webview.load_uri(url)
        self.add(self.webview)

    def on_key_press(self, _window, event):
        if event.state & Gdk.ModifierType.CONTROL_MASK and event.keyval == Gdk.KEY_r:
            self.webview.reload()
            return True
        if event.state & Gdk.ModifierType.MOD1_MASK and event.keyval == Gdk.KEY_Left:
            self.webview.go_back()
            return True
        if event.state & Gdk.ModifierType.MOD1_MASK and event.keyval == Gdk.KEY_Right:
            self.webview.go_forward()
            return True
        return False


def main():
    url = sys.argv[1] if len(sys.argv) > 1 else "https://insight-book.ru"
    if not url.startswith("https://"):
        raise SystemExit("InsightBook webview only accepts an HTTPS URL")
    window = InsightBookWindow(url)
    window.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
