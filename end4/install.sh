#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_HOME="$ROOT/home"
ORIGINAL_HOME="/home/injurka"
MODE="${1:-}"

if [[ "$MODE" != "" && "$MODE" != "--configs-only" ]]; then
  echo "Usage: $0 [--configs-only]" >&2
  exit 2
fi
if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run as your regular user, not root." >&2
  exit 1
fi
if [[ ! -d "$SOURCE_HOME/.config/hypr" || ! -d "$SOURCE_HOME/.config/quickshell/ii" ]]; then
  echo "Incomplete snapshot: Hyprland or Quickshell config is missing." >&2
  exit 1
fi
command -v python3 >/dev/null || { echo "Install python3 first." >&2; exit 1; }

backup_root="$HOME/.local/state/end4-transfer-backups"
mkdir -p "$backup_root"
backup="$(mktemp -d "$backup_root/$(date +%Y%m%d-%H%M%S)-XXXXXX")"
for relative in .config/hypr .config/quickshell/ii .config/illogical-impulse/config.json Wallpapers; do
  target="$HOME/$relative"
  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p "$backup/$(dirname "$relative")"
    cp -a -- "$target" "$backup/$relative"
  fi
done
echo "Existing laptop settings backed up to: $backup"

if [[ "$MODE" != "--configs-only" ]]; then
  command -v git >/dev/null || { echo "Install git first." >&2; exit 1; }
  command -v pacman >/dev/null || { echo "The automatic setup expects Arch Linux or CachyOS." >&2; exit 1; }
  base_commit="$(<"$ROOT/upstream-base-commit.txt")"
  upstream="$HOME/.local/src/end4-dots-hyprland-${base_commit:0:8}"
  if [[ ! -d "$upstream/.git" ]]; then
    mkdir -p "$(dirname "$upstream")"
    git clone https://github.com/injurka/dots-hyprland.git "$upstream"
    git -C "$upstream" checkout --detach "$base_commit"
    git -C "$upstream" submodule update --init --recursive
  fi
  if [[ "$(git -C "$upstream" rev-parse HEAD)" != "$base_commit" ]]; then
    echo "Unexpected end-4 checkout revision in $upstream." >&2
    exit 1
  fi
  echo "Running the end-4 setup. Answer its package and service prompts."
  (cd "$upstream" && ./setup install)
fi

for relative in .config/hypr .config/quickshell/ii .config/illogical-impulse/config.json Wallpapers; do
  source="$SOURCE_HOME/$relative"
  target="$HOME/$relative"
  [[ -e "$source" ]] || continue
  mkdir -p "$(dirname "$target")"
  if [[ -d "$source" ]]; then
    mkdir -p "$target"
    cp -a -- "$source/." "$target/"
  else
    cp -a -- "$source" "$target"
  fi
done

python3 - "$HOME" "$ORIGINAL_HOME" <<'PY'
from pathlib import Path
import re
import sys

home = Path(sys.argv[1])
old_home = sys.argv[2].encode()
config_paths = [home / '.config/hypr', home / '.config/quickshell/ii',
                home / '.config/illogical-impulse/config.json']
for root in config_paths:
    paths = root.rglob('*') if root.is_dir() else [root]
    for path in paths:
        if not path.is_file() or path.is_symlink():
            continue
        data = path.read_bytes()
        if old_home in data and b'\0' not in data:
            path.write_bytes(data.replace(old_home, str(home).encode()))

hypr = home / '.config/hypr'
(hypr / 'monitors.lua').write_text(
    '-- Laptop: automatically select the connected display.\n'
    'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })\n'
)
for name in ['custom/general.lua', 'custom/personal-keybinds.lua', 'hyprland.lua']:
    path = hypr / name
    if path.exists():
        content = path.read_text()
        content = re.sub(r'^.*hl\.workspace_rule\(.*monitor\s*=.*\n', '', content, flags=re.M)
        content = re.sub(r'^.*hl\.bind\(.*switch_monitors_(?:profile|size)\.sh.*\n', '', content, flags=re.M)
        path.write_text(content)
(hypr / 'scripts/apply_monitors.sh').write_text(
    '#!/usr/bin/env bash\n'
    'echo "Desktop monitor profiles are disabled on this laptop." >&2\n'
    'exit 1\n'
)
PY

echo "Settings restored. Previous laptop files: $backup"
echo "Log out and back in to load the new session."
echo "Desktop monitor settings remain in this repository's snapshot."
