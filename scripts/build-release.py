#!/usr/bin/env python3
"""Build the Chinese universal app using only Xcode's bundled tools."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
APP = BUILD / 'AutoRaise.app'
VERSION = '5.7.1'

def run(*args):
    subprocess.run([str(a) for a in args], cwd=ROOT, check=True)

if APP.exists():
    shutil.rmtree(APP)
resources = APP / 'Contents/Resources'
macos = APP / 'Contents/MacOS'
resources.mkdir(parents=True)
macos.mkdir()
sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
source = ROOT / 'vendor/MASShortcut/Framework'
includes = [arg for p in sorted({p.parent for p in source.rglob('*.h')}) for arg in ['-I', str(p)]]
for arch in ['arm64', 'x86_64']:
    target = arch + '-apple-macos12.0'
    objects = BUILD / arch
    objects.mkdir(exist_ok=True)
    run('xcrun', 'clang++', '-O2', '-Wall', '-fobjc-arc', '-DNS_FORMAT_ARGUMENT(A)=',
        '-DSKYLIGHT_AVAILABLE=1', '-DEXPERIMENTAL_FOCUS_FIRST', '-DOLD_ACTIVATION_METHOD',
        '-target', target, '-isysroot', sdk, 'AutoRaise.mm', '-framework', 'AppKit',
        '-F/System/Library/PrivateFrameworks', '-framework', 'SkyLight', '-o', objects / 'AutoRaise')
    objfiles = []
    for src in sorted(source.rglob('*.m')):
        obj = objects / (src.stem + '.o')
        run('xcrun', 'clang', '-O2', '-fobjc-arc', '-fmodules', '-include', 'Cocoa/Cocoa.h', '-target', target, '-isysroot', sdk,
            *includes, '-c', src, '-o', obj)
        objfiles.append(obj)
    run('xcrun', 'swiftc', '-O', '-parse-as-library', '-swift-version', '5', '-module-name', 'AutoRaise',
        '-target', target, '-sdk', sdk, *includes, '-import-objc-header', 'Launcher/Bridging-Header.h',
        'Launcher/AppDelegate.swift', *objfiles, '-framework', 'AppKit', '-framework', 'Carbon',
        '-framework', 'ServiceManagement', '-o', objects / 'Launcher')
run('xcrun', 'lipo', '-create', BUILD / 'arm64/AutoRaise', BUILD / 'x86_64/AutoRaise', '-output', resources / 'AutoRaise')
run('xcrun', 'lipo', '-create', BUILD / 'arm64/Launcher', BUILD / 'x86_64/Launcher', '-output', macos / 'AutoRaise')
run('xcrun', 'ibtool', '--compile', resources / 'MainMenu.nib', 'Launcher/Base.lproj/MainMenu.xib', '--minimum-deployment-target', '12.0')
run('xcrun', 'actool', 'Launcher/Images.xcassets', '--compile', resources,
    '--platform', 'macosx', '--minimum-deployment-target', '12.0', '--app-icon', 'AppIcon',
    '--output-partial-info-plist', BUILD / 'assets.plist')
shutil.copytree(ROOT / 'Launcher/zh-Hans.lproj', resources / 'zh-Hans.lproj')
# This distribution deliberately uses Chinese on every system language.
shutil.copy(ROOT / 'Launcher/zh-Hans.lproj/Localizable.strings', resources / 'Localizable.strings')
with (ROOT / 'Launcher/Info.plist').open('rb') as f:
    info = plistlib.load(f)
info.update(CFBundleExecutable='AutoRaise', CFBundleName='AutoRaise',
    CFBundleIdentifier='com.sbmpost.AutoRaise', CFBundleShortVersionString=VERSION,
    CFBundleVersion='2026091101', CFBundleDevelopmentRegion='zh-Hans',
    CFBundleLocalizations=['zh-Hans'], LSMinimumSystemVersion='12.0')
with (BUILD / 'assets.plist').open('rb') as f:
    info.update(plistlib.load(f))
with (APP / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)
shutil.copy(ROOT / 'LICENSE.md', resources)
shutil.copy(ROOT / 'vendor/MASShortcut/LICENSE', resources / 'MASShortcut-LICENSE')
run('codesign', '--force', '--sign', '-', resources / 'AutoRaise')
run('codesign', '--force', '--sign', '-', APP)
run('codesign', '--verify', '--deep', '--strict', '--verbose=2', APP)
print(f'Built {APP}')
