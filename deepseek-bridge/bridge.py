#!/usr/bin/env python3
"""Loopback-only Ollama-to-DeepSeek adapter. No third-party dependencies."""
import argparse
import datetime
import json
import signal
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from pi_backend import Session
from jobs import Jobs, APIError, identifier

DEFAULT_MODEL = 'deepseek-v4-flash-vision-exp'
CONFIG = Path.home() / 'Library/Application Support/AtollDeepSeekBridge/config.json'
def read_config(path):
    try:
        config = json.loads(path.read_text())
        if not isinstance(config, dict): return {}
        if not isinstance(config.get('api_key',''), str): return {}
        if not isinstance(config.get('model',DEFAULT_MODEL), str): return {}
        return config
    except (OSError, ValueError): return {}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass  # Never log prompts, responses or credentials.
    def reply(self, status, data):
        encoded = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Content-Length',str(len(encoded)))
        self.end_headers()
        try: self.wfile.write(encoded)
        except (BrokenPipeError, ConnectionResetError): pass
    def allowed(self):
        host = self.headers.get('Host','').split(':')[0]
        if self.headers.get('Origin') or host not in ('127.0.0.1','localhost'):
            self.reply(403, {'error':'Local app requests only'})
            return False
        return True
    def do_GET(self):
        if not self.allowed(): return
        config = read_config(self.server.config_path)
        if self.path == '/health':
            self.reply(200, {'status':'ok', 'backend':'pi', 'configured':bool(config.get('api_key','').strip()),
                             'model':config.get('model',DEFAULT_MODEL), 'protocol_version':2,
                             'capabilities':{'jobs':True, 'sessions':True}})
        elif self.path.startswith('/atoll/'):
            try:
                match = re.fullmatch(r'/atoll/sessions/([^/]*)/jobs/([^/]*)', self.path)
                if not match: raise APIError(404, 'Not found')
                self.reply(200, self.server.jobs.poll(identifier(match[1]), identifier(match[2])))
            except APIError as error: self.reply(error.status, {'error':str(error)})
        elif self.path == '/api/tags':
            self.reply(200, {'models':[{'name':config.get('model',DEFAULT_MODEL)}]})
        else: self.reply(404, {'error':'Not found'})
    def do_POST(self):
        if not self.allowed(): return
        if self.path.startswith('/atoll/'):
            self.native_post(); return
        if self.path != '/api/chat':
            self.reply(404, {'error':'Not found'}); return
        try:
            length = int(self.headers.get('Content-Length','0'))
            if not 0 < length <= 48 * 1024 * 1024: raise ValueError()
            self.connection.settimeout(10)
            payload = json.loads(self.rfile.read(length))
            messages = payload['messages']
            if not isinstance(messages,list) or not messages: raise ValueError()
            if payload.get('stream',False): raise ValueError()
            clean = []
            for message in messages:
                if message.get('role') not in ('system','user','assistant'): raise ValueError()
                if not isinstance(message.get('content'),str): raise ValueError()
                item={'role':message['role'], 'content':message['content']}
                if message.get('images'):
                    if message['role']!='user' or not isinstance(message['images'],list): raise ValueError()
                    item['images']=message['images']
                clean.append(item)
        except (ValueError, KeyError, TypeError, AttributeError, OSError):
            self.reply(400, {'error':'Expected non-streaming text messages'}); return
        config = read_config(self.server.config_path)
        content = self.server.session.chat(config, clean)
        # Atoll only displays message.content; represent actionable upstream errors there.
        self.reply(200, {'model':config.get('model',DEFAULT_MODEL),
            'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'message':{'role':'assistant','content':content}, 'done':True})

    def native_post(self):
        try:
            match = re.fullmatch(r'/atoll/sessions/([^/]*)/(reset|stop)', self.path)
            if self.path != '/atoll/chat' and not match: raise APIError(404, 'Not found')
            if self.headers.get('Transfer-Encoding'): raise APIError(400, 'Use Content-Length')
            lengths = self.headers.get_all('Content-Length', [])
            if len(lengths) != 1: raise APIError(400, 'Expected Content-Length')
            length = int(lengths[0])
            if not 0 < length <= 48 * 1024 * 1024: raise APIError(400, 'Body must be 1–48 MiB')
            self.connection.settimeout(10)
            payload = json.loads(self.rfile.read(length))
            if not isinstance(payload, dict): raise APIError(400, 'Expected an object')
            config = read_config(self.server.config_path)
            if self.path == '/atoll/chat':
                status, result = self.server.jobs.start(config, payload)
            else:
                sid = identifier(match[1])
                if match[2] == 'reset':
                    if payload: raise APIError(400, 'reset expects {}')
                    result = self.server.jobs.reset(sid)
                else:
                    identifier(payload.get('job_id'))
                    result = self.server.jobs.stop(sid, payload['job_id'],
                                                   config.get('model', DEFAULT_MODEL))
                status = 200
            self.reply(status, result)
        except APIError as error: self.reply(error.status, {'error':str(error)})
        except (ValueError, TypeError, OSError, RecursionError):
            self.reply(400, {'error':'Malformed JSON request'})


class BridgeServer(ThreadingHTTPServer):
    def server_close(self):
        if hasattr(self, 'jobs'): self.jobs.close()
        if hasattr(self, 'session'): self.session.reset()
        super().server_close()

def make_server(port, config_path):
    server = BridgeServer(('127.0.0.1',port), Handler)
    server.daemon_threads = True
    server.config_path = config_path
    server.session = Session(config_path.parent / "pi-agent")
    server.jobs = Jobs(config_path.parent / 'pi-native')
    return server

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port',type=int,default=11435)
    parser.add_argument('--config',type=Path,default=CONFIG)
    args = parser.parse_args()
    server = make_server(args.port,args.config)
    def stop_service(_signum, _frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop_service)
    try:
        server.serve_forever()
    finally:
        server.session.reset()
        server.server_close()
