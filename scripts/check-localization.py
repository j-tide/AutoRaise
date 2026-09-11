#!/usr/bin/env python3
"""Exercise the actual nib and UI in an isolated preference domain without starting the engine."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import platform

root = Path(__file__).resolve().parents[1]
build = root / 'build'
app = build / 'AutoRaise.app'
with (app / 'Contents/Info.plist').open('rb') as f:
    assert plistlib.load(f)['CFBundleIdentifier'] == 'com.sbmpost.AutoRaise'
engine = app / 'Contents/Resources/AutoRaise'
for option in ['--help', '--version']:
    result = subprocess.run([str(engine), option], check=True, capture_output=True, text=True, timeout=10)
    assert '简体中文版' in result.stdout
    print(result.stdout.splitlines()[0:3])
for binary in [engine, app / 'Contents/MacOS/AutoRaise']:
    archs = subprocess.check_output(['lipo', '-archs', str(binary)], text=True)
    assert 'arm64' in archs and 'x86_64' in archs
check = build / 'LocalizationCheck.app'
if check.exists(): shutil.rmtree(check)
shutil.copytree(app, check)
with (check / 'Contents/Info.plist').open('rb') as f: info = plistlib.load(f)
info['CFBundleIdentifier'] = 'AutoRaise.LocalizationCheck'
with (check / 'Contents/Info.plist').open('wb') as f: plistlib.dump(info, f)
source = (root / 'Launcher/AppDelegate.swift').read_text().replace('@NSApplicationMain', '')
source = source.replace('let prefs = UserDefaults.standard', 'let prefs = UserDefaults(suiteName: "AutoRaise.LocalizationCheck.\\(ProcessInfo.processInfo.processIdentifier)")!')
(build / 'CheckDelegate.swift').write_text(source)
shutil.copy(root / 'scripts/LocalizationCheck.swift', build / 'main.swift')
headers = root / 'vendor/MASShortcut/Framework'
includes = [arg for p in sorted({p.parent for p in headers.rglob('*.h')}) for arg in ['-I', str(p)]]
arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-module-name', 'AutoRaise', *includes,
    '-import-objc-header', str(root / 'Launcher/Bridging-Header.h'), str(build / 'CheckDelegate.swift'),
    str(build / 'main.swift'), *map(str, sorted((build / arch).glob('*.o'))),
    '-framework', 'AppKit', '-framework', 'Carbon', '-framework', 'ServiceManagement',
    '-o', str(check / 'Contents/MacOS/AutoRaise')], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(check)], check=True)
subprocess.run([str(check / 'Contents/MacOS/AutoRaise')], check=True, timeout=30,
    env={**os.environ, 'AUTORAISE_CHECK_OUTPUT': str(build)})
