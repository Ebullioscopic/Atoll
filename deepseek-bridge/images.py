"""Image input for Ollama payloads and the installed Atoll screenshot format."""
import base64
import binascii
from pathlib import Path
import re
import subprocess

MAX_IMAGE=16*1024*1024
MAX_IMAGES=8
SCREENSHOTS=Path.home()/'Documents/ScreenAssistantScreenshots'
SECRET_DIR=(Path.home()/'Library/Application Support/AtollDeepSeekBridge').resolve()

def decode_images(values):
    if not isinstance(values,list) or len(values)>MAX_IMAGES:
        raise ValueError('最多发送 8 张图片。')
    result=[]
    for value in values:
        if not isinstance(value,str) or len(value)>MAX_IMAGE*4//3+4: raise ValueError('每张图片不能超过 16 MB。')
        try: data=base64.b64decode(value,validate=True)
        except (ValueError,binascii.Error): raise ValueError('图片 Base64 无效。') from None
        if len(data)>MAX_IMAGE: raise ValueError('每张图片不能超过 16 MB。')
        if data.startswith(b'\x89PNG\r\n\x1a\n'): mime='image/png'
        elif data.startswith(b'\xff\xd8\xff'): mime='image/jpeg'
        elif data[:6] in (b'GIF87a',b'GIF89a'): mime='image/gif'
        elif data[:4]==b'RIFF' and data[8:12]==b'WEBP': mime='image/webp'
        else: raise ValueError('请使用 PNG、JPEG、GIF 或 WebP 图片。')
        result.append({'type':'image','data':value,'mimeType':mime})
    return result

def read_image(path):
    path=Path(path).expanduser().resolve()
    if not path.is_absolute() or SECRET_DIR==path or SECRET_DIR in path.parents or any(p.startswith('.') for p in path.parts):
        raise ValueError('此路径不允许作为图片读取。')
    try:
        with path.open('rb') as file: data=file.read(MAX_IMAGE+1)
    except PermissionError:
        helper=SECRET_DIR/'Atoll Image Access.app/Contents/MacOS/ImageAccess'
        if path.parent==SCREENSHOTS.resolve() and re.fullmatch(r'screenshot_\d+\.png',path.name) and helper.exists():
            result=subprocess.run([str(helper),'--read',path.name],capture_output=True,text=True,timeout=30)
            if result.returncode==0: return decode_images([result.stdout.strip()])[0]
            raise ValueError('截图目录尚未授权。请打开 Atoll Image Access，选择 Documents/ScreenAssistantScreenshots 并允许，然后重新发送截图。')
        raise ValueError('macOS 拒绝后台服务读取该图片。可将图片复制到 /tmp 后用 /image /tmp/图片.png 发送。') from None
    except OSError: raise ValueError('无法读取图片，请检查完整路径和访问权限。') from None
    return decode_images([base64.b64encode(data).decode()])[0]

def legacy_images(text,root=SCREENSHOTS):
    marker='I have attached the following files for your analysis:'
    if marker not in text: return []
    section=text.rsplit(marker,1)[1].split('\n\n',1)[0]
    entries=re.findall(r'^- (.+) \(([^\n]+)\)$',section,re.M)
    if not entries: raise ValueError('Atoll 未发送附件内容。图片请用 /image 完整路径 发送。')
    if len(entries)>MAX_IMAGES: raise ValueError('最多发送 8 张图片。')
    result=[]
    for name,kind in entries:
        if kind!='Image' or not re.fullmatch(r'screenshot_\d+\.png',name):
            raise ValueError('原版 Atoll 只传附件名。普通图片请发送 /image 完整路径，下一行填写问题。')
        path=root/name
        if path.is_symlink() or path.resolve().parent!=root.resolve(): raise ValueError('截图路径无效。')
        result.append(read_image(path))
    return result

def prepare(text,values,root=SCREENSHOTS):
    if values: return text,decode_images(values)
    if text.startswith('/image '):
        path,_,question=text[7:].partition('\n')
        path=path.strip().strip('"').strip("'")
        if not Path(path).expanduser().is_absolute(): raise ValueError('请提供图片的绝对路径。')
        return question.strip() or '请描述并分析这张图片。',[read_image(path)]
    return text,legacy_images(text,root)
