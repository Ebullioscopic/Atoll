#!/usr/bin/env python3
import getpass
import json
import os
from pathlib import Path
from bridge import CONFIG, DEFAULT_MODEL, read_config

print('配置 DeepSeek 官方 API；输入 Key 时不会显示字符。')
previous = read_config(CONFIG)
key = getpass.getpass('DeepSeek API Key（回车保留已有 Key）: ').strip() or previous.get('api_key','')
if not key or any(c.isspace() for c in key):
    raise SystemExit('Key 为空或含空格，未修改配置。')
model = input('模型名称 ['+previous.get('model',DEFAULT_MODEL)+']: ').strip() or previous.get('model',DEFAULT_MODEL)
thinking = input('开启思考模式？[Y/n]: ').strip().lower() != 'n'
CONFIG.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
temp = CONFIG.with_suffix('.tmp')
fd = os.open(str(temp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd,'w') as file:
    json.dump(dict(previous,api_key=key,model=model,thinking=thinking,tools=True,file_access='ask'),file)
os.chmod(temp,0o600)
os.replace(temp,CONFIG)
print('配置已保存，只允许当前用户读取。无需重启服务，现在可以在 Atoll 发送文字。')
input('按回车关闭。')
