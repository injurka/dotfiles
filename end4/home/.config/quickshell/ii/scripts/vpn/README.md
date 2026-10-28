# VPN quick toggle

The classic right sidebar includes a VPN button. Left click disconnects the
currently connected managed VPN, or connects the first provider in the saved
priority list. Right click opens priority ordering and links to each client's
settings. A failed preferred provider is reported; no silent fallback occurs.

Providers:
- Prosebya: existing NetworkManager VPN connection named `Prosebya` (UUID is
  discovered locally; no credentials are stored here).
- AmneziaVPN: the running client's StatusNotifierItem / DBusMenu Connect and
  Disconnect actions, using the server selected in the client.
- Browsec: the running client's DBusMenu Start VPN and Stop VPN actions.

Requires Python 3, PyGObject, nmcli, notify-send and the VPN clients.
On Arch, the additional Python package is `python-gobject`.
Clients must expose their tray menu and have a configured account/server.
If a client is closed or its menu is unavailable, the button opens the client
and asks the user to configure it, then retry. Connection status is derived
from the client's available disconnect action, not from process existence;
it does not independently verify internet routing or the remote endpoint.

Priority is stored outside the repository at
`${XDG_CONFIG_HOME:-~/.config}/illogical-impulse/vpn.json`.
The first click disconnects an already active managed provider even when a
different provider has priority. The next click connects the preferred one.
The helper serializes toggle actions and polls status for confirmation.
