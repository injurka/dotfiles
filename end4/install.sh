#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
SOURCE_HOME="$ROOT/home"
ORIGINAL_HOME="/home/injurka"
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
  --monitor-scale VALUE       Set the laptop monitor scale (default: 1).
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

if [[ ! -d "$SOURCE_HOME/.config/hypr" || ! -d "$SOURCE_HOME/.config/quickshell/ii" ]]; then
  echo "Incomplete snapshot: Hyprland or Quickshell config is missing." >&2
  exit 1
fi

if [[ "$DRY_RUN" != true ]]; then
  for relative in .config/hypr .config/quickshell/ii .config/illogical-impulse/config.json Wallpapers; do
    target="$HOME/$relative"
    if [[ -L "$target" ]]; then
      echo "Refusing to write through a symlink: $target" >&2
      exit 1
    fi
  done
fi

python3 - "$SOURCE_HOME" "$HOME" <<'PY'
from pathlib import Path
import sys

source_home, home = Path(sys.argv[1]), Path(sys.argv[2])
for relative in [Path(".config/hypr"), Path(".config/quickshell/ii"),
                 Path(".config/illogical-impulse/config.json"), Path("Wallpapers")]:
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
PY

if [[ "$DRY_RUN" == true ]]; then
  echo "Read-only hardware profile:"
  python3 "$ROOT/machine-profile.py"
  echo
  if [[ "$MODE" == "full" ]]; then
    echo "Plan: run the pinned end-4 installer, back up existing settings, copy the saved snapshot, and configure monitor scale $MONITOR_SCALE."
  else
    echo "Plan: back up existing settings, copy the saved snapshot, and configure monitor scale $MONITOR_SCALE."
  fi
  echo "No files, packages, or services were changed."
  exit 0
fi

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run as your regular user, not root." >&2
  exit 1
fi

if [[ "$MODE" == "full" ]]; then
  command -v git >/dev/null || { echo "Install git first." >&2; exit 1; }
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
for relative in .config/hypr .config/quickshell/ii .config/illogical-impulse/config.json Wallpapers; do
  target="$HOME/$relative"
  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p "$backup/$(dirname -- "$relative")"
    cp -a -- "$target" "$backup/$relative"
  fi
done
echo "Existing settings backed up to: $backup"

if [[ "$MODE" == "full" ]]; then
  echo "Running the end-4 setup. Review its package and service prompts."
  (cd "$upstream" && ./setup install)
fi

for relative in .config/hypr .config/quickshell/ii .config/illogical-impulse/config.json Wallpapers; do
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

python3 - "$SOURCE_HOME" "$HOME" "$ORIGINAL_HOME" "$MONITOR_SCALE" <<'PY'
from pathlib import Path
import re
import sys

source_home = Path(sys.argv[1])
home = Path(sys.argv[2])
old_home = sys.argv[3].encode()
scale = sys.argv[4]
relative_paths = [Path(".config/hypr"), Path(".config/quickshell/ii"),
                  Path(".config/illogical-impulse/config.json"), Path("Wallpapers")]

# Rewrite only files that came from this snapshot. Existing laptop-only data,
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
    "-- Laptop profile: automatically select connected displays.\n"
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
    "echo \"Desktop monitor profiles are disabled in this portable laptop setup.\" >&2\n"
    "exit 1\n"
)
PY

echo "Settings restored with monitor scale $MONITOR_SCALE. Previous files: $backup"
echo "Log out and back in to load the new session."
echo "To restore files, copy the matching paths back from $backup."
