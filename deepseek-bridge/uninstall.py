#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess

dest = Path.home() / 'Library/Application Support/AtollDeepSeekBridge'
subprocess.run(['launchctl','bootout','gui/%d/local.atoll.deepseek-bridge' % os.getuid()],capture_output=True)
agent = Path.home() / 'Library/LaunchAgents/local.atoll.deepseek-bridge.plist'
if agent.exists(): agent.unlink()
backup = dest / 'atoll-settings-before.json'
if backup.exists():
    for key, value in json.loads(backup.read_text()).items():
        cmd = ['defaults','delete','com.Ebullioscopic.Atoll',key] if value is None else ['defaults','write','com.Ebullioscopic.Atoll',key,'-string',value]
        subprocess.run(cmd,capture_output=True)
print('Service stopped and startup removed. Previous Atoll settings restored. Local configuration files retained.')
