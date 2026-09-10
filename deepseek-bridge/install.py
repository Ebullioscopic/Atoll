#!/usr/bin/env python3
"""Install this user's local bridge and configure only Atoll's local provider."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time

source = Path(__file__).resolve().parent
dest = Path.home() / 'Library/Application Support/AtollDeepSeekBridge'
dest.mkdir(parents=True, exist_ok=True, mode=0o700)
for name in ('bridge.py','configure.py','配置 DeepSeek.command','pi_backend.py','pi-tools.ts','agent_tools.py','tool_runner.py','images.py','jobs.py'):
    shutil.copy2(source / name, dest / name)
subprocess.run(['/usr/bin/python3',str(source/'build_image_access.py')],check=True)
shutil.copytree(source/'build/Atoll Image Access.app',dest/'Atoll Image Access.app',dirs_exist_ok=True)
agent = Path.home() / 'Library/LaunchAgents/local.atoll.deepseek-bridge.plist'
agent.parent.mkdir(parents=True,exist_ok=True)
label = 'local.atoll.deepseek-bridge'
service = 'gui/%d/%s' % (os.getuid(),label)
settings = {'Label':label,'ProgramArguments':['/usr/bin/python3',str(dest / 'bridge.py')],
    'RunAtLoad':True,'KeepAlive':True,'ThrottleInterval':10,
    'StandardOutPath':str(dest / 'service.log'),'StandardErrorPath':str(dest / 'service.log')}
if agent.exists(): subprocess.run(['launchctl','bootout',service],capture_output=True)
agent.write_bytes(plistlib.dumps(settings))
for attempt in range(5):
    loaded = subprocess.run(['launchctl','bootstrap','gui/%d' % os.getuid(),str(agent)],capture_output=True,text=True)
    if loaded.returncode == 0: break
    if attempt == 4: raise RuntimeError('Unable to start bridge: ' + loaded.stderr.strip())
    time.sleep(0.5) # launchd may still be removing the previous service.

# Preserve only the settings changed here, not unrelated credentials.
backup = dest / 'atoll-settings-before.json'
if not backup.exists():
    original = {}
    for key in ('selectedAIProvider','localModelEndpoint'):
        result = subprocess.run(['defaults','read','com.Ebullioscopic.Atoll',key],capture_output=True,text=True)
        original[key] = result.stdout.rstrip('\n') if result.returncode == 0 else None
    backup.write_text(json.dumps(original))
    backup.chmod(0o600)
subprocess.run(['defaults','write','com.Ebullioscopic.Atoll','localModelEndpoint','-string','http://127.0.0.1:11435'],check=True)
subprocess.run(['defaults','write','com.Ebullioscopic.Atoll','selectedAIProvider','-string','Local Model'],check=True)
print('Installed loopback service with login startup; Atoll set to Local Model at 127.0.0.1:11435.')
print('Key configuration: ' + str(dest / '配置 DeepSeek.command'))
