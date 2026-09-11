#!/usr/bin/env python3
"""Package an already built app. Does not publish to GitHub."""
from pathlib import Path
import hashlib
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
app = root / 'build/AutoRaise.app'
with (app / 'Contents/Info.plist').open('rb') as f: info = plistlib.load(f)
version = info['CFBundleShortVersionString']
dist = root / 'dist'
dist.mkdir(exist_ok=True)
staging = root / 'build/dmg'
if staging.exists(): shutil.rmtree(staging)
staging.mkdir()
shutil.copytree(app, staging / 'AutoRaise.app')
(staging / 'Applications').symlink_to('/Applications')
shutil.copy(root / 'INSTALL.zh-CN.md', staging / '安装说明.md')
shutil.copy(root / 'LICENSE.md', staging / 'LICENSE.md')
name = f'AutoRaise-{version}-zh-Hans-universal'
dmg, zipfile = dist / (name + '.dmg'), dist / (name + '.zip')
for p in [dmg, zipfile]:
    if p.exists(): p.unlink()
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
subprocess.run(['hdiutil', 'create', '-volname', 'AutoRaise 简体中文版', '-srcfolder', str(staging),
    '-format', 'UDZO', '-ov', str(dmg)], check=True)
subprocess.run(['ditto', '-c', '-k', '--keepParent', '--norsrc', str(app), str(zipfile)], check=True)
subprocess.run(['hdiutil', 'verify', str(dmg)], check=True)
subprocess.run(['unzip', '-tq', str(zipfile)], check=True)
(dist / 'SHA256SUMS.txt').write_text(''.join(
    f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in [dmg, zipfile]))
print((dist / 'SHA256SUMS.txt').read_text())
