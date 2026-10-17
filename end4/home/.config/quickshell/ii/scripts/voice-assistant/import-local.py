#!/usr/bin/env python3
"""Import local runtime files without putting credentials or model weights in dotfiles."""
import argparse
import json
import os
from pathlib import Path
import shutil
import sqlite3


def xdg(name, fallback):
    value = os.environ.get(name)
    return Path(value) if value and Path(value).is_absolute() else Path.home() / fallback


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--from', dest='source', required=True, type=Path,
                        help='Original assistant project directory')
    args = parser.parse_args()
    source = args.source.resolve()
    resources = source / 'apps/resources'
    library = resources / 'libvosk.so'
    model = resources / 'models/vosk'
    if not library.is_file() or not (model / 'am/final.mdl').is_file():
        parser.error('Source must contain apps/resources/libvosk.so and models/vosk/am/final.mdl')

    data = xdg('XDG_DATA_HOME', '.local/share') / 'voice-assistant'
    state = xdg('XDG_STATE_HOME', '.local/state') / 'voice-assistant'
    config_dir = xdg('XDG_CONFIG_HOME', '.config') / 'voice-assistant'
    for directory in (data, state, config_dir):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)

    config_source = source / 'apps/core/config.json'
    config_target = config_dir / 'config.json'
    if not config_target.exists():
        template = Path(__file__).with_name('config.example.json')
        payload = json.loads((config_source if config_source.exists() else template).read_text())
        payload['uiMode'] = 'external'
        descriptor = os.open(config_target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'w') as output:
            json.dump(payload, output, ensure_ascii=False, indent=2)
            output.write('\n')

    if not (data / 'libvosk.so').exists():
        shutil.copy2(library, data / 'libvosk.so')
    if not (data / 'models/vosk').exists():
        (data / 'models').mkdir(exist_ok=True)
        staging = data / 'models' / f'.vosk-import-{os.getpid()}'
        try:
            shutil.copytree(model, staging)
            staging.rename(data / 'models/vosk')
        finally:
            if staging.exists():
                shutil.rmtree(staging)

    whisper_binary = source / 'apps/whisper/whisper.cpp/build/bin/whisper-server'
    whisper_model = resources / 'models/ggml-large-v3-turbo-q5_0.bin'
    if whisper_binary.is_file() and whisper_model.is_file():
        runtime = data / 'whisper'
        runtime.mkdir(exist_ok=True)
        for original in [whisper_binary, *whisper_binary.parent.glob('*.so*')]:
            target = runtime / original.name
            if original.is_file() and not target.exists():
                shutil.copy2(original, target)
        target_model = data / 'models' / whisper_model.name
        if not target_model.exists():
            shutil.copy2(whisper_model, target_model)

    history = resources / 'data/history.sqlite'
    destination = state / 'history.sqlite'
    if history.is_file() and not destination.exists():
        with sqlite3.connect(history.as_uri() + '?mode=ro', uri=True) as original:
            with sqlite3.connect(destination) as imported:
                original.backup(imported)
        destination.chmod(0o600)

    print('Local config, Vosk resources and history are ready.')
    print('Runtime directories:', config_dir, data, state)


if __name__ == '__main__':
    main()
