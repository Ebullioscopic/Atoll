# -*- coding: utf-8 -*-
"""Offline native-chat acceptance backend, using the real v2 registry/HTTP routes."""
from pathlib import Path
import json
import sys
import tempfile
import threading
import signal
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'deepseek-bridge'))
import bridge
import pi_backend

root = Path(__file__).resolve().parents[2]
events = root / 'build/Acceptance/ui-fixture-events.jsonl'
events.parent.mkdir(parents=True, exist_ok=True)
lock = threading.Lock()

def record(kind, **values):
    with lock:
        with events.open('a', encoding='utf-8') as f:
            f.write(json.dumps(dict(event=kind, **values), ensure_ascii=False) + '\n')

class FixturePi:
    def __init__(self, config, state_dir, on_created=None):
        self.config = config
        self.release = threading.Event()
        self.sid = Path(state_dir).name
        if on_created: on_created(self)
        record('created', session=self.sid)
    def restore(self, messages):
        record('restored', session=self.sid, turns=len(messages), images=sum(len(m.get('images', [])) for m in messages))
    def prompt(self, text, config, images=None, on_event=None):
        record('prompt', session=self.sid, text=text, images=len(images or []), thinking=config.get('thinking'), tools=config.get('tools'))
        if '慢' in text:
            self.release.wait(45)
        content = '# 聊天界面验收\n\n中文输入和 **加粗文字** 正常。\n\n1. 第一项：保留多轮上下文\n2. 第二项：图片可点击放大\n\n```python\nprint("你好，Atoll")\nlong_line = "' + 'long-code-' * 18 + '"\n```\n\n| 项目 | 结果 |\n| --- | --- |\n| 中文 | 正常 |\n| 图片 | ' + str(len(images or [])) + ' 张 |\n\n> 这是完全离线的测试回答。'
        if on_event:
            on_event({'type':'tool_execution_start','toolName':'web_search'})
            on_event({'type':'tool_execution_end','toolName':'web_search'})
            for start in range(0, len(content), 45):
                if self.release.wait(.12): break
                on_event({'type':'message_update','assistantMessageEvent':{'type':'text_delta','delta':content[start:start+45]}})
        return content
    def close(self):
        self.release.set()
        record('closed', session=self.sid)

pi_backend.PiClient = FixturePi
with tempfile.TemporaryDirectory(prefix='atoll-ui-fixture-') as tmp:
    config = Path(tmp)/'config.json'
    config.write_text(json.dumps({'api_key':'offline-fixture','model':'Atoll UI fixture'}))
    server = bridge.make_server(11436, config)
    def stop(*_): raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, stop)
    print('Offline Atoll UI fixture listening on 127.0.0.1:11436', flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()
