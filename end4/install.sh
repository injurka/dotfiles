#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
SOURCE_HOME="$ROOT/home"
FONT_SOURCE="$SOURCE_HOME/.local/share/fonts/MapleMono"
if [[ "${XDG_DATA_HOME:-}" == /* ]]; then
  FONT_TARGET="$XDG_DATA_HOME/fonts/MapleMono"
else
  FONT_TARGET="$HOME/.local/share/fonts/MapleMono"
fi
SESSION_SOURCE="$ROOT/session/end4-portable.desktop.in"
SESSION_RENDERER="$ROOT/session/render-session.py"
SESSION_TARGET="/usr/share/wayland-sessions/end4-portable.desktop"
SESSION_LAUNCHER="$SOURCE_HOME/.local/bin/start-end4-hyprland"
FISH_ALIAS_SOURCE="$SOURCE_HOME/.config/fish/conf.d/end4-git-aliases.fish"
ORIGINAL_HOME="/home/injurka"

# Upstream files intentionally removed from this portable snapshot.
REMOVED_QUICKSHELL_PATHS=(
  "assets/icons/nyarch-symbolic.svg"
  "defaults/ai/prompts/ii-Imouto.md"
  "defaults/ai/prompts/nyarch-Acchan.md"
  "modules/ii/sidebarLeft/Anime.qml"
  "modules/ii/sidebarLeft/anime/BooruImage.qml"
  "modules/ii/sidebarLeft/anime/BooruResponse.qml"
  "scripts/colors/random/random_konachan_wall.sh"
  "scripts/colors/random/random_osu_wall.sh"
  "services/Booru.qml"
  "services/BooruResponseData.qml"
)
MODE="full"
DRY_RUN=false
INVENTORY=false
MONITOR_SCALE="1"
MONITOR_SCALE_SET=false

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --inventory                 Print a privacy-conscious hardware profile as JSON.
  --dry-run                   Show what would happen without changing files or installing packages.
  --configs-only              Apply the saved configs to an existing end-4 installation.
  --monitor-scale VALUE       Set the target display scale (default: 1).
  -h, --help                  Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory)
      INVENTORY=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --configs-only)
      MODE="configs-only"
      ;;
    --monitor-scale)
      [[ $# -ge 2 ]] || { echo "--monitor-scale needs a numeric value." >&2; exit 2; }
      MONITOR_SCALE="$2"
      MONITOR_SCALE_SET=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

command -v python3 >/dev/null || { echo "Install python3 first." >&2; exit 1; }

if [[ "$INVENTORY" == true ]]; then
  if [[ "$DRY_RUN" == true || "$MODE" != "full" || "$MONITOR_SCALE_SET" == true ]]; then
    echo "--inventory cannot be combined with installation options." >&2
    exit 2
  fi
  exec python3 "$ROOT/machine-profile.py"
fi

if ! MONITOR_SCALE="$(python3 - "$MONITOR_SCALE" <<'PY'
import math
import sys
try:
    value = float(sys.argv[1])
except ValueError:
    raise SystemExit(1)
if not math.isfinite(value) or value < 0.5 or value > 4.0:
    raise SystemExit(1)
print(f"{value:.2f}".rstrip("0").rstrip("."))
PY
)"; then
  echo "Monitor scale must be a number from 0.5 to 4.0." >&2
  exit 2
fi

if [[ ! -d "$SOURCE_HOME/.config/hypr" || ! -d "$SOURCE_HOME/.config/quickshell/ii" \
   || ! -x "$SESSION_LAUNCHER" || ! -d "$FONT_SOURCE" || ! -s "$FONT_SOURCE/LICENSE.txt" \
   || ! -s "$FISH_ALIAS_SOURCE" || ! -f "$SESSION_SOURCE" || ! -f "$SESSION_RENDERER" ]]; then
  echo "Incomplete snapshot: configs, Fish Git aliases, Maple Mono font/license, session template, renderer, or executable launcher is missing." >&2
  exit 1
fi
if ! compgen -G "$FONT_SOURCE/*.ttf" >/dev/null; then
  echo "Incomplete snapshot: Maple Mono TTF files are missing." >&2
  exit 1
fi

if [[ "$MODE" == "full" && (-e "$SESSION_TARGET" || -L "$SESSION_TARGET") ]]; then
  if [[ -L "$SESSION_TARGET" ]] || ! grep -Fqx 'X-End4-Portable=true' "$SESSION_TARGET"; then
    echo "Refusing to replace an unrelated Wayland session entry: $SESSION_TARGET" >&2
    exit 1
  fi
fi

if [[ "$DRY_RUN" != true ]]; then
  for relative in .config/hypr .config/quickshell/ii .config/illogical-impulse/config.json .config/systemd/user/voice-assistant.service .config/fish/conf.d/end4-git-aliases.fish Wallpapers .local/bin/start-end4-hyprland; do
    target="$HOME/$relative"
    if [[ -L "$target" ]]; then
      echo "Refusing to write through a symlink: $target" >&2
      exit 1
    fi
  done
fi

python3 - "$SOURCE_HOME" "$HOME" "$FONT_TARGET" "${REMOVED_QUICKSHELL_PATHS[@]}" <<'PY'
from pathlib import Path
import sys

source_home, home, font_target = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
removed_quickshell_paths = [Path(item) for item in sys.argv[4:]]
for relative in [Path(".config/hypr"), Path(".config/quickshell/ii"),
                 Path(".config/illogical-impulse/config.json"),
                 Path(".config/systemd/user/voice-assistant.service"),
                 Path(".config/fish/conf.d/end4-git-aliases.fish"), Path("Wallpapers"),
                 Path(".local/bin/start-end4-hyprland")]:
    source = source_home / relative
    candidates = [source] if source.is_file() else source.rglob("*") if source.is_dir() else []
    for item in candidates:
        if item.is_symlink():
            continue
        target = home / item.relative_to(source_home)
        current = target
        while current == home or home in current.parents:
            if current.is_symlink():
                print("Refusing to write through a symlink: " + str(current), file=sys.stderr)
                raise SystemExit(1)
            if current == home:
                break
            current = current.parent
for current in (font_target, *font_target.parents):
    if current.is_symlink():
        print("Refusing to write through a symlink: " + str(current), file=sys.stderr)
        raise SystemExit(1)
quickshell_target = home / ".config/quickshell/ii"
for relative in removed_quickshell_paths:
    current = quickshell_target
    if current.is_symlink():
        print("Refusing to remove files through a symlink: " + str(current), file=sys.stderr)
        raise SystemExit(1)
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            print("Refusing to remove a symlinked Quickshell path: " + str(current), file=sys.stderr)
            raise SystemExit(1)
PY

if [[ -e "$FONT_TARGET" && ! -d "$FONT_TARGET" ]]; then
  echo "Refusing to replace a non-directory font target: $FONT_TARGET" >&2
  exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "Read-only hardware profile:"
  python3 "$ROOT/machine-profile.py"
  echo
  if [[ "$MODE" == "full" ]]; then
    echo "Plan: run the pinned end-4 installer, back up existing settings, copy the saved snapshot, Fish Git aliases and Voice Assistance user service, remove retired anime files, install Maple Mono fonts and launcher, register the end-4 Wayland session, and configure display scale $MONITOR_SCALE."
  else
    echo "Plan: back up existing settings, copy the saved snapshot, Fish Git aliases and Voice Assistance user service, remove retired anime files, install Maple Mono fonts and launcher, and configure display scale $MONITOR_SCALE. System session registration is full-mode only."
  fi
  echo "No files, packages, or services were changed."
  exit 0
fi

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run as your regular user, not root." >&2
  exit 1
fi

if [[ "$MODE" == "full" ]]; then
  command -v git >/dev/null || { echo "Install git first (for example: sudo pacman -S --needed git)." >&2; exit 1; }
  command -v sudo >/dev/null || { echo "Install sudo and configure access for your user first." >&2; exit 1; }
  [[ -t 0 && -t 1 ]] || { echo "Full installation needs an interactive terminal for end-4 prompts." >&2; exit 1; }
  [[ "$HOME" == /* ]] || { echo "HOME must be an absolute path." >&2; exit 1; }
  command -v pacman >/dev/null || { echo "The automatic setup expects Arch Linux or CachyOS." >&2; exit 1; }
  base_commit="$(<"$ROOT/upstream-base-commit.txt")"
  [[ "$base_commit" =~ ^[0-9a-fA-F]{40}$ ]] || { echo "Invalid pinned upstream commit." >&2; exit 1; }
  upstream="$HOME/.local/src/end4-dots-hyprland-$(printf %.8s "$base_commit")"
  if [[ ! -d "$upstream/.git" ]]; then
    mkdir -p "$(dirname -- "$upstream")"
    git clone https://github.com/injurka/dots-hyprland.git "$upstream"
  fi
  if ! git -C "$upstream" cat-file -e "$base_commit^{commit}" 2>/dev/null; then
    git -C "$upstream" fetch origin "$base_commit"
  fi
  git -C "$upstream" checkout --detach "$base_commit"
  [[ "$(git -C "$upstream" rev-parse HEAD)" == "$base_commit" ]] || {
    echo "Unexpected end-4 checkout revision in $upstream." >&2
    exit 1
  }
  git -C "$upstream" submodule update --init --recursive
fi

backup_root="$HOME/.local/state/end4-transfer-backups"
mkdir -p "$backup_root"
backup="$(mktemp -d "$backup_root/$(date +%Y%m%d-%H%M%S)-XXXXXX")"
for relative in .config/hypr .config/quickshell/ii .config/illogical-impulse/config.json .config/systemd/user/voice-assistant.service .config/fish/conf.d/end4-git-aliases.fish Wallpapers .local/bin/start-end4-hyprland; do
  target="$HOME/$relative"
  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p "$backup/$(dirname -- "$relative")"
    cp -a -- "$target" "$backup/$relative"
  fi
done
if [[ -e "$FONT_TARGET" ]]; then
  mkdir -p "$backup/fonts"
  cp -a -- "$FONT_TARGET" "$backup/fonts/MapleMono"
fi
if [[ "$MODE" == "full" && -e "$SESSION_TARGET" ]]; then
  mkdir -p "$backup/system/usr/share/wayland-sessions"
  cp -a -- "$SESSION_TARGET" "$backup/system/usr/share/wayland-sessions/end4-portable.desktop"
fi
echo "Existing settings backed up to: $backup"

if [[ "$MODE" == "full" ]]; then
  echo "Running the end-4 setup. Review its package and service prompts."
  (cd "$upstream" && ./setup install)
fi

for relative in .config/hypr .config/quickshell/ii .config/illogical-impulse/config.json .config/systemd/user/voice-assistant.service .config/fish/conf.d/end4-git-aliases.fish Wallpapers .local/bin/start-end4-hyprland; do
  source="$SOURCE_HOME/$relative"
  target="$HOME/$relative"
  [[ -e "$source" ]] || continue
  if [[ -L "$target" ]]; then
    echo "Refusing to write through a symlink: $target" >&2
    exit 1
  fi
  if [[ -d "$source" ]]; then
    mkdir -p "$target"
    cp -a -- "$source/." "$target/"
  else
    mkdir -p "$(dirname -- "$target")"
    cp -a -- "$source" "$target"
  fi
done
python3 - "$HOME" "${REMOVED_QUICKSHELL_PATHS[@]}" <<'PY'
from pathlib import Path
import sys

home = Path(sys.argv[1])
root = home / ".config/quickshell/ii"
for relative in map(Path, sys.argv[2:]):
    target = root / relative
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            print("Refusing to remove a symlinked Quickshell path: " + str(current), file=sys.stderr)
            raise SystemExit(1)
    if target.exists():
        if not target.is_file():
            print("Refusing to remove a non-file Quickshell path: " + str(target), file=sys.stderr)
            raise SystemExit(1)
        target.unlink()
        print("Removed retired anime file: " + str(target))
try:
    (root / "modules/ii/sidebarLeft/anime").rmdir()
except OSError:
    pass
PY
mkdir -p "$(dirname -- "$FONT_TARGET")"
mkdir -p "$FONT_TARGET"
cp -a -- "$FONT_SOURCE/." "$FONT_TARGET/"

python3 - "$SOURCE_HOME" "$HOME" "$ORIGINAL_HOME" "$MONITOR_SCALE" <<'PY'
from pathlib import Path
import re
import sys

source_home = Path(sys.argv[1])
home = Path(sys.argv[2])
old_home = sys.argv[3].encode()
scale = sys.argv[4]
relative_paths = [Path(".config/hypr"), Path(".config/quickshell/ii"),
                  Path(".config/illogical-impulse/config.json"), Path("Wallpapers"),
                  Path(".config/systemd/user/voice-assistant.service"),
                  Path(".config/fish/conf.d/end4-git-aliases.fish"),
                  Path(".local/bin/start-end4-hyprland")]

# Rewrite only files that came from this snapshot. Data on the target computer,
# such as calendar entries and notification history, is left untouched.
for relative in relative_paths:
    source = source_home / relative
    target = home / relative
    if source.is_dir():
        source_files = [path for path in source.rglob("*") if path.is_file() and not path.is_symlink()]
        pairs = [(path, target / path.relative_to(source)) for path in source_files]
    elif source.is_file() and not source.is_symlink():
        pairs = [(source, target)]
    else:
        pairs = []
    for source_path, target_path in pairs:
        if not target_path.is_file() or target_path.is_symlink():
            continue
        data = target_path.read_bytes()
        if old_home in data and b"\0" not in data:
            target_path.write_bytes(data.replace(old_home, str(home).encode()))

hypr = home / ".config/hypr"
(hypr / "monitors.lua").write_text(
    "-- Portable profile: automatically select connected displays.\n"
    "hl.monitor({ output = \"\", mode = \"preferred\", position = \"auto\", scale = " + scale + " })\n"
)
for name in ["custom/general.lua", "custom/personal-keybinds.lua", "hyprland.lua"]:
    path = hypr / name
    if path.exists():
        content = path.read_text()
        content = re.sub(r"^.*hl\.workspace_rule\(.*monitor\s*=.*\n", "", content, flags=re.M)
        content = re.sub(r"^.*hl\.bind\(.*switch_monitors_(?:profile|size)\.sh.*\n", "", content, flags=re.M)
        path.write_text(content)
(hypr / "scripts/apply_monitors.sh").write_text(
    "#!/usr/bin/env bash\n"
    "echo \"Manual monitor profiles are disabled in this portable setup.\" >&2\n"
    "exit 1\n"
)
PY

command -v fc-cache >/dev/null || {
  echo "fontconfig fc-cache is required to register the bundled Maple Mono fonts." >&2
  exit 1
}
fc-cache -f "$FONT_TARGET"
if ! fc-match -f '%{family}\n' 'Maple Mono' | grep -Fq 'Maple Mono'; then
  echo "Maple Mono was copied but fontconfig cannot find the family." >&2
  exit 1
fi
echo "Installed Maple Mono in $FONT_TARGET"

if [[ "$MODE" == "full" ]]; then
  [[ -x /usr/bin/start-hyprland ]] || {
    echo "end-4 setup did not install /usr/bin/start-hyprland; cannot register the portable session." >&2
    exit 1
  }
  rendered_session="$backup/end4-portable.desktop"
  python3 "$SESSION_RENDERER" "$SESSION_SOURCE" "$HOME/.local/bin/start-end4-hyprland" "$rendered_session"
  sudo install -D -m 0644 -- "$rendered_session" "$SESSION_TARGET"
  echo "Registered Wayland session: $SESSION_TARGET"
fi

echo "Settings restored with monitor scale $MONITOR_SCALE. Previous files: $backup"
echo "Log out and back in to load the new session."
echo "To restore files, copy the matching paths back from $backup."
