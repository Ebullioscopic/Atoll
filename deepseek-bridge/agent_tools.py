"""Read-only tools. Public web access and explicit local file approval."""
import http.client
import ipaddress
import json
from pathlib import Path
import socket
import ssl
import subprocess
import urllib.parse
from html.parser import HTMLParser
import xml.etree.ElementTree as ET

LIMIT = 16000
SECRET_DIR = (Path.home() / 'Library/Application Support/AtollDeepSeekBridge').resolve()

def spec(name, description, properties):
    return {'type':'function','function':{'name':name,'description':description,
        'parameters':{'type':'object','properties':{k:{'type':'string','description':v} for k,v in properties.items()},'required':list(properties),'additionalProperties':False}}}

def definitions(config):
    if not config.get('tools',True): return []
    tools=[spec('web_search','Search public web pages. Cite returned URLs; search snippets are not verified facts.',{'query':'Search query'}),
           spec('read_webpage','Read a public HTTP(S) page; cannot access localhost or private networks.',{'url':'Public URL'})]
    if config.get('file_access') == 'ask' or config.get('read_roots'):
        tools += [spec('list_files','List one local directory after user approval. Use explicit paths supplied by the user.',{'path':'Absolute directory path'}),
                  spec('read_file','Read a UTF-8 text file after user approval; its contents will be sent to DeepSeek. No PDFs or binary files.',{'path':'Absolute file path'})]
    return tools

def public_url(url):
    parts=urllib.parse.urlsplit(url)
    if parts.scheme not in ('http','https') or not parts.hostname or parts.username or parts.password:
        raise ValueError('Only public HTTP(S) URLs without credentials are allowed')
    port=parts.port or (443 if parts.scheme=='https' else 80)
    if port not in (80,443): raise ValueError('Only standard web ports are allowed')
    addresses=socket.getaddrinfo(parts.hostname,port,type=socket.SOCK_STREAM)
    ips=[entry[4][0] for entry in addresses]
    if not ips or any(not ipaddress.ip_address(ip).is_global for ip in ips):
        raise ValueError('Private or local network addresses are not allowed')
    return parts, ips[0], port

class PinnedHTTP(http.client.HTTPConnection):
    def __init__(self,host,port,ip):
        super().__init__(host,port,timeout=10)
        self.ip=ip
    def connect(self): self.sock=socket.create_connection((self.ip,self.port),self.timeout)
class PinnedHTTPS(PinnedHTTP):
    def connect(self):
        raw=socket.create_connection((self.ip,self.port),self.timeout)
        try: self.sock=ssl.create_default_context().wrap_socket(raw,server_hostname=self.host)
        except Exception:
            raw.close()
            raise

class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(); self.parts=[]; self.skip=0
    def handle_starttag(self,tag,attrs):
        if tag in ('script','style'): self.skip+=1
    def handle_endtag(self,tag):
        if tag in ('script','style'): self.skip=max(0,self.skip-1)
    def handle_data(self,data):
        if not self.skip and data.strip(): self.parts.append(data.strip())

def fetch(url):
    for _ in range(4):
        parts,ip,port=public_url(url)
        connection=(PinnedHTTPS if parts.scheme=='https' else PinnedHTTP)(parts.hostname,port,ip)
        try:
            path=urllib.parse.urlunsplit(('', '',parts.path or '/',parts.query,''))
            connection.request('GET',path,headers={'User-Agent':'AtollDeepSeekBridge/2.0','Accept-Encoding':'identity'})
            response=connection.getresponse()
            if response.status in (301,302,303,307,308):
                location=response.getheader('Location')
                if not location: raise ValueError('Missing redirect URL')
                url=urllib.parse.urljoin(url,location)
                continue
            if response.status!=200: raise ValueError('Web request failed (%d)' % response.status)
            content_type=response.getheader('Content-Type','').lower()
            if not any(t in content_type for t in ('text/','json','xml')): raise ValueError('Only text web pages are supported')
            raw=response.read(512001)
            if len(raw)>512000: raise ValueError('Web page exceeds size limit')
            return url,raw.decode('utf-8',errors='replace')
        finally: connection.close()
    raise ValueError('Too many redirects')

def approve(path,directory):
    prompt=('允许 DeepSeek '+('列出此目录' if directory else '读取此文本文件')+'？\n\n'+str(path)+
            '\n\n读取结果将发送给 DeepSeek 官方 API。本次允许不会授权其他文件。')
    script='on run argv\n display dialog (item 1 of argv) with title "Atoll 文件访问请求" buttons {"拒绝", "允许本次"} default button "拒绝" giving up after 90\n if gave up of result then return "拒绝"\n return button returned of result\nend run'
    result=subprocess.run(['/usr/bin/osascript','-e',script,prompt],capture_output=True,text=True,timeout=95)
    return result.returncode==0 and result.stdout.strip()=='允许本次'

def checked_path(value,config):
    path=Path(value).expanduser().resolve()
    if path==SECRET_DIR or SECRET_DIR in path.parents:
        raise ValueError('Bridge credential/configuration directory is excluded')
    if config.get('file_access') == 'ask': return path
    roots=[Path(root).expanduser().resolve() for root in config.get('read_roots',[])]
    if not any(path==root or root in path.parents for root in roots): raise ValueError('Path outside approved roots')
    if any(part.startswith('.') for part in path.parts): raise ValueError('Hidden files are excluded')
    return path

def execute(name,args,config):
    if not isinstance(args,dict): raise ValueError('Expected tool arguments object')
    if name in ('read_file','list_files'):
        if not isinstance(args.get('path'),str): raise ValueError('Expected path')
        path=checked_path(args['path'],config)
        directory=name=='list_files'
        if config.get('file_access')=='ask' and not approve(path,directory):
            raise ValueError('User denied file access or approval timed out; do not retry without a new user request')
        # Resolve again after the approval dialog to detect a changed symlink.
        if Path(args['path']).expanduser().resolve()!=path: raise ValueError('Path changed after approval')
        if directory:
            if not path.is_dir(): raise ValueError('Not a directory')
            items=[]
            for child in path.iterdir():
                if child.name.startswith('.') or child.is_symlink(): continue
                items.append(child.name+('/' if child.is_dir() else ''))
                if len(items)>=200: break
            return json.dumps({'path':str(path),'entries':sorted(items),'limit':200},ensure_ascii=False)[:LIMIT]
        if not path.is_file() or path.stat().st_size>256000: raise ValueError('Not a small text file (maximum 256 KB)')
        text=path.read_bytes()
        if len(text)>256000 or b'\x00' in text: raise ValueError('Binary or oversized file')
        return json.dumps({'path':str(path),'text':text.decode('utf-8')[:LIMIT],'truncated':len(text)>LIMIT},ensure_ascii=False)
    if name=='read_webpage':
        url,html=fetch(args['url'])
        parser=PlainText(); parser.feed(html)
        return json.dumps({'url':url,'text':'\n'.join(parser.parts)[:LIMIT]},ensure_ascii=False)
    if name=='web_search':
        query=args.get('query','')
        if not isinstance(query,str) or not 0<len(query)<=500: raise ValueError('Invalid search query')
        url,xml=fetch('https://www.bing.com/search?format=rss&q='+urllib.parse.quote(query))
        root=ET.fromstring(xml)
        results=[{'title':item.findtext('title'),'url':item.findtext('link'),'snippet':item.findtext('description')} for item in root.findall('.//item')[:5]]
        return json.dumps({'source':url,'results':results},ensure_ascii=False)[:LIMIT]
    raise ValueError('Unknown or unavailable tool')
