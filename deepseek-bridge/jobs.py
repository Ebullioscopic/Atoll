"""Native v2 jobs. Registry locks never cover Pi startup, RPC waits, or joins.

An ID ledger lasts for this server's lifetime. Its hard limits reject new IDs
instead of evicting cancellation/retirement fences and resurrecting late work.
"""
from dataclasses import dataclass, field
import hashlib
import json
from pathlib import Path
import re
import shutil
import threading
import time
import uuid

import pi_backend
from images import decode_images

MAX_IDENTITIES = 4096
MAX_REQUESTS = 8192
MAX_SESSIONS = 16
MAX_RESULTS = 128
IDLE_SECONDS = 1800
RESULT_SECONDS = 1800
MAX_CONTENT = 1024 * 1024
MAX_TURNS = 64
MAX_JOB_SECONDS = 360  # Includes startup/configuration as well as generation.


class APIError(Exception):
    def __init__(self, status, message):
        self.status = status
        super().__init__(message)


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(
            r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', value):
        raise APIError(400, 'Expected a UUID string')
    return str(uuid.UUID(value))


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()


def validate_chat(payload):
    if not isinstance(payload, dict): raise APIError(400, 'Expected an object')
    sid = identifier(payload.get('session_id'))
    jid = identifier(payload.get('request_id'))
    if type(payload.get('thinking')) is not bool or type(payload.get('tools')) is not bool:
        raise APIError(400, 'thinking and tools must be booleans')
    messages = payload.get('messages')
    if not isinstance(messages, list) or not messages or len(messages) > 2048:
        raise APIError(400, 'Expected 1–2048 messages')
    clean = []
    for message in messages:
        if (not isinstance(message, dict) or message.get('role') not in ('user', 'assistant', 'system')
                or not isinstance(message.get('content'), str)):
            raise APIError(400, 'Expected text messages with valid roles')
        item = {'role': message['role'], 'content': message['content']}
        if 'images' in message:
            if message['role'] != 'user': raise APIError(400, 'Only user messages can contain images')
            try: images = decode_images(message['images'])
            except ValueError as error: raise APIError(400, str(error)) from None
            if images: item['images'] = images
        clean.append(item)
    if clean[-1]['role'] != 'user': raise APIError(400, 'The last message must be a user message')
    return sid, jid, clean


@dataclass
class Job:
    jid: str
    model: str
    fingerprint: str = ''
    output_id: str = ''
    status: str = 'pending'
    content: str = ''
    tools: list = field(default_factory=list)
    phase: str = 'pending'
    touched: float = field(default_factory=time.monotonic)
    expired: bool = False
    thread: object = None
    cancel_done: object = None

    def snapshot(self):
        return dict(job_id=self.output_id or self.jid, status=self.status, content=self.content,
                    model=self.model, tools=list(self.tools), phase=self.phase)


@dataclass
class NativeSession:
    sid: str
    directory: Path
    client: object = None
    job: object = None
    stopping: bool = False
    history_digest: str = ''
    turns: int = 0
    latest_job_id: str = ''
    touched: float = field(default_factory=time.monotonic)


class Jobs:
    def __init__(self, state_dir):
        self.state_dir = Path(state_dir)
        self.lock = threading.RLock()
        self.identities = {}  # SID -> None (live) or reset completion Event (retired)
        self.requests = {}    # (SID, JID) -> result or compact non-reusable ID record
        self.sessions = {}
        self.closed = threading.Event()
        self.reaper = threading.Thread(target=self._reap, daemon=True, name='atoll-cleanup')
        self.reaper.start()

    def _identity(self, sid):
        if self.closed.is_set(): raise APIError(503, 'Bridge is shutting down')
        if sid in self.identities:
            if self.identities[sid] is not None: raise APIError(410, 'Session is retired; use a new session_id')
        else:
            if len(self.identities) >= MAX_IDENTITIES: raise APIError(503, 'Session ID capacity reached; restart bridge')
            self.identities[sid] = None

    def _room_for_request(self):
        if len(self.requests) >= MAX_REQUESTS: raise APIError(503, 'Request ID capacity reached; restart bridge')

    def start(self, config, payload):
        sid, jid, messages = validate_chat(payload)
        current = dict(config, thinking=payload['thinking'], tools=payload['tools'], _native=True)
        if any(m.get('images') for m in messages):
            current['model'] = current.get('vision_model', pi_backend.VISION_MODEL)
            current['_vision'] = True
        model = current.get('model', pi_backend.VISION_MODEL)
        fingerprint = digest([messages, payload['thinking'], payload['tools']])
        with self.lock:
            self._identity(sid)
            existing = self.requests.get((sid, jid))
            if existing:
                if existing.status == 'cancelled': raise APIError(409, 'Job was cancelled; use a new request_id')
                if existing.fingerprint != fingerprint: raise APIError(409, 'request_id already has another payload')
                if existing.expired: raise APIError(410, 'Job result expired; use a new request_id')
                if existing.status == 'pending':
                    return 202, dict(job_id=existing.output_id, status='pending', model=existing.model)
                return 200, existing.snapshot()
            self._room_for_request()
            session = self.sessions.get(sid)
            if session and (session.stopping or session.job):
                raise APIError(409, 'Session is busy; stop or wait for its current job')
            if not session:
                # Never close a different session in this request. The periodic
                # reaper frees idle slots; active sessions remain independent.
                if len(self.sessions) >= MAX_SESSIONS: raise APIError(503, 'Live session capacity reached')
                session = NativeSession(sid, self.state_dir / sid)
                self.sessions[sid] = session
            job = Job(jid, model, fingerprint, output_id=payload['request_id'])
            self.requests[sid, jid] = job
            session.job = job
            session.latest_job_id = jid
            job.thread = threading.Thread(target=self._work, args=(session, job, current, messages),
                                          daemon=True, name='atoll-job-' + jid)
            # Publish and start under the same lock: cancel can always join it.
            job.thread.start()
            self._trim_results()
            return 202, dict(job_id=job.output_id, status='pending', model=model)

    def poll(self, sid, jid):
        with self.lock:
            if sid in self.identities and self.identities[sid] is not None:
                raise APIError(410, 'Session is retired')
            job = self.requests.get((sid, jid))
            if not job: raise APIError(404, 'Job not found in this session')
            if job.expired: raise APIError(410, 'Job result expired')
            return job.snapshot()

    def _live(self, session, job):
        return not self.closed.is_set() and not session.stopping and session.job is job and job.status == 'pending'

    def _created(self, session, job, client):
        # Pi publishes its process before startup RPC waits, so cancellation
        # can terminate it even while the constructor is still running.
        with self.lock:
            live = self._live(session, job)
            if live: session.client = client
        if not live: client.close()

    def _progress(self, session, job, event):
        with self.lock:
            if not self._live(session, job): return
            kind = event.get('type')
            if kind in ('tool_execution_start', 'tool_execution_update'):
                job.phase = 'tool_execution'
                name = event.get('toolName')
                if kind == 'tool_execution_start' and name in pi_backend.TOOLS and name not in job.tools:
                    job.tools.append(name)
            elif kind in ('agent_start', 'turn_start', 'tool_execution_end'):
                job.phase = 'generating'
            elif kind == 'message_update':
                delta = event.get('assistantMessageEvent', {})
                if delta.get('type') in ('thinking_start', 'thinking_delta'): job.phase = 'thinking'
                elif delta.get('type') in ('text_start', 'text_delta'):
                    job.phase = 'generating'
                    if delta.get('type') == 'text_delta':
                        job.content = (job.content + delta.get('delta', ''))[:MAX_CONTENT]
            elif kind == 'message_start' and event.get('message', {}).get('role') == 'assistant':
                job.content = ''
            elif kind == 'message_end' and event.get('message', {}).get('role') == 'assistant':
                job.content = '\n'.join(p.get('text', '') for p in event['message'].get('content', [])
                                         if p.get('type') == 'text')[:MAX_CONTENT]

    def _work(self, session, job, config, messages):
        client = None
        try:
            if not config.get('api_key', '').strip():
                raise pi_backend.BackendError('请先运行「配置 DeepSeek.command」填写 API Key。')
            with self.lock:
                if not self._live(session, job): return
                job.phase = 'starting'
                client = session.client
                replace = client and (session.history_digest != digest(messages[:-1])
                    or session.turns >= MAX_TURNS or time.monotonic() - session.touched > IDLE_SECONDS
                    or any(client.config.get(k) != config.get(k) for k in ('api_key', 'model', '_vision')))
            if replace:
                client.close()
                with self.lock:
                    if session.client is client: session.client = None
                client = None
            if not client:
                with self.lock:
                    if not self._live(session, job): return
                client = pi_backend.PiClient(config, session.directory,
                    on_created=lambda value: self._created(session, job, value))
                with self.lock:
                    live = self._live(session, job)
                    if live:
                        session.client = client
                        session.turns = 0
                if not live:
                    client.close(); return
                client.restore(messages[:-1])
            with self.lock:
                if not self._live(session, job): return
                job.phase = 'generating'
            # close() fences RPC writes. Cancellation also joins this worker;
            # no prompt or constructor can execute after the stop/reset ACK.
            answer = client.prompt(messages[-1]['content'], config, images=messages[-1].get('images'),
                                   on_event=lambda event: self._progress(session, job, event))
            if len(answer) > MAX_CONTENT: raise pi_backend.BackendError('回答超过字符数上限，请缩小任务。')
            with self.lock:
                if self._live(session, job):
                    job.status = job.phase = 'completed'
                    job.content = answer
                    session.history_digest = digest(messages + [dict(role='assistant', content=answer)])
                    session.turns += 1
        except Exception as error:
            if client: client.close()
            with self.lock:
                if self._live(session, job):
                    job.status = job.phase = 'failed'
                    job.content = str(error) if isinstance(error, (pi_backend.BackendError, ValueError)) else 'pi 执行失败，请重试。'
                    session.client = None
                    session.history_digest = ''
        finally:
            with self.lock:
                # Cancellation owns client cleanup while stopping is true.
                if session.job is job and not session.stopping:
                    session.job = None
                job.touched = session.touched = time.monotonic()
                self._trim_results()

    def stop(self, sid, jid, model):
        output_id = jid
        jid = identifier(jid)
        with self.lock:
            self._identity(sid)
            session = self.sessions.get(sid)
            job = self.requests.get((sid, jid))
            if not job and any(j == jid for (_, j) in self.requests):
                raise APIError(409, 'job_id belongs to another session')
            if session and session.job and session.job.jid != jid:
                raise APIError(409, 'job_id does not match the active job in this session')
            if job and job.cancel_done:
                done = job.cancel_done
                owner = False
            else:
                if session and session.stopping: raise APIError(409, 'Session is stopping')
                if not job:
                    self._room_for_request()
                    job = Job(jid, model, output_id=output_id)
                    self.requests[sid, jid] = job
                job.status = job.phase = 'cancelled'
                job.content = ''
                job.expired = False
                job.cancel_done = done = threading.Event()
                owner = True
                # A historical job must not close a newer idle client's memory.
                target = session if session and (session.job is job or session.latest_job_id == jid) else None
                if target: target.stopping = True
        if owner:
            try:
                if target: self._terminate(target, job)
            finally: done.set()
        else: done.wait()
        with self.lock: return job.snapshot()

    def reset(self, sid):
        with self.lock:
            if sid in self.identities and self.identities[sid] is not None:
                done = self.identities[sid]
                owner = False
            else:
                self._identity(sid)
                done = threading.Event()
                self.identities[sid] = done  # Fence all late creation immediately.
                session = self.sessions.get(sid)
                prior_stop = None
                if session:
                    if session.stopping and session.job: prior_stop = session.job.cancel_done
                    session.stopping = True
                    if session.job: session.job.status = session.job.phase = 'cancelled'
                owner = True
        if owner:
            try:
                if prior_stop: prior_stop.wait()
                if session: self._terminate(session, session.job, remove=True)
                with self.lock:
                    for (s, _), job in self.requests.items():
                        if s == sid: job.content = ''; job.tools.clear(); job.expired = True
            finally: done.set()
        else: done.wait()
        return dict(session_id=sid, status='reset')

    def _terminate(self, session, job, remove=False):
        with self.lock:
            client = session.client
            worker = job.thread if job else None
        if client: client.close()
        if worker: worker.join()
        # Constructor may have returned after the first client snapshot.
        with self.lock: client = session.client
        if client: client.close()
        shutil.rmtree(session.directory, ignore_errors=True)
        with self.lock:
            session.client = None
            session.job = None
            session.history_digest = ''
            session.turns = 0
            session.touched = time.monotonic()
            session.stopping = False
            if remove: self.sessions.pop(session.sid, None)
            if job: job.thread = None

    def _trim_results(self):
        now = time.monotonic()
        retained = sorted((j for j in self.requests.values() if j.status != 'pending'
                           and not j.expired and not (j.cancel_done and not j.cancel_done.is_set())),
                          key=lambda j: j.touched, reverse=True)
        for index, job in enumerate(retained):
            if index >= MAX_RESULTS or now - job.touched > RESULT_SECONDS:
                job.content = ''; job.tools.clear()
                # A watchdog can mark a still-constructing job failed. Keep
                # its join barrier until termination has actually finished.
                if job.thread and not job.thread.is_alive(): job.thread = None
                # Cancellation fences remain pollable after payload cleanup.
                if job.status != 'cancelled': job.expired = True

    def cleanup(self):
        with self.lock:
            stalled = [(s, s.job) for s in self.sessions.values() if s.job and not s.stopping
                       and time.monotonic() - s.job.touched > MAX_JOB_SECONDS]
            for session, job in stalled:
                session.stopping = True
                job.status = job.phase = 'failed'
                job.content = '任务达到运行时间上限，请缩小任务后重试。'
            idle = [s for s in self.sessions.values() if not s.job and not s.stopping
                    and time.monotonic() - s.touched > IDLE_SECONDS]
            for session in idle: session.stopping = True
            self._trim_results()
        for session, job in stalled: self._terminate(session, job)
        for session in idle: self._terminate(session, None, remove=True)

    def _reap(self):
        while not self.closed.wait(30): self.cleanup()

    def close(self):
        self.closed.set()
        self.reaper.join()
        with self.lock:
            sessions = list(self.sessions.values())
            for session in sessions:
                session.stopping = True
                if session.job: session.job.status = session.job.phase = 'cancelled'
        for session in sessions: self._terminate(session, session.job, remove=True)
