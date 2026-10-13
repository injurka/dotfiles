#!/usr/bin/env python3
"""Previous/next image in the current wallpaper directory, through end-4 IPC."""
from pathlib import Path
import argparse,json,os,subprocess
p=argparse.ArgumentParser();p.add_argument('direction',choices=['next','prev']);p.add_argument('--dry-run',action='store_true');a=p.parse_args()
h=Path.home();config=Path(os.environ.get('XDG_CONFIG_HOME',h/'.config'));state=Path(os.environ.get('XDG_STATE_HOME',h/'.local/state'))
c=json.loads((config/'illogical-impulse/config.json').read_text());path=c.get('background',{}).get('wallpaperPath','')
if not path:
 saved=state/'quickshell/user/generated/wallpaper/path.txt';path=saved.read_text().strip() if saved.exists() else ''
current=Path(path).expanduser() if path else h/'Pictures/Wallpapers/no-image'
folder=current.parent; extensions={'.jpg','.jpeg','.png','.webp','.avif','.bmp','.svg'}
images=sorted((x for x in folder.iterdir() if x.is_file() and x.suffix.lower() in extensions),key=lambda x:x.name.casefold()) if folder.is_dir() else []
if images:
 index=images.index(current) if current in images else (-1 if a.direction=='next' else 0)
 target=images[(index+(1 if a.direction=='next' else -1))%len(images)]
 command=['qs','-c','ii','ipc','call','wallpapers','apply',str(target)]
else:command=['qs','-c','ii','ipc','call','wallpaperSelector','toggle']
if a.dry_run:print(json.dumps(command,ensure_ascii=False))
else:subprocess.run(command,check=True)
