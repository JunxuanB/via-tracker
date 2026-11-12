#!/usr/bin/env python3
"""Wait for the native root view before taking a simulator screenshot.

The Debug app emits timing-only startup events. A slow SwiftData/simulator
startup must fail the capture rather than silently produce a loading screen.
"""
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time

device, language, scene, output = sys.argv[1:]
bundle = 'com.junxuanb.viatracker'
env = dict(os.environ, SIMCTL_CHILD_VIA_QA_SCENARIO=scene)
env.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
subprocess.run(['xcrun', 'simctl', 'terminate', device, bundle], env=env,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
process = subprocess.Popen(['xcrun', 'simctl', 'launch', '--console', device, bundle,
    '-AppleLanguages', f'({language})', '-AppleLocale', 'en_CA' if language == 'en' else 'zh_CN'],
    env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
try:
    deadline = time.monotonic() + 180
    data = b''
    while time.monotonic() < deadline:
        if selector.select(timeout=1):
            chunk = os.read(process.stdout.fileno(), 8192)
            if not chunk:
                raise RuntimeError(f'App launch ended before root view appeared: {scene}')
            data += chunk
            if b'VIA_STARTUP root.appear' in data:
                break
        if process.poll() is not None:
            raise RuntimeError(f'App launch failed: {scene}, exit {process.returncode}')
    else:
        raise TimeoutError(f'Native root view did not appear within 180 seconds: {scene}')
    time.sleep(4)  # Allow navigation / sheet presentation to finish after root appearance.
    Path(output).parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', output], env=env,
                   check=True, timeout=30, stdout=subprocess.DEVNULL)
    # Simulator PNGs include an alpha channel even when every pixel is opaque.
    # Remove it to produce a consistent opaque RGB capture.
    subprocess.run(['swift', str(Path(__file__).with_name('normalize-screenshot.swift')), output],
                   env=env, check=True, timeout=60)
    print(output, flush=True)
finally:
    selector.close()
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
