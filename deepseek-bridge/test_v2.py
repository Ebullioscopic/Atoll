"""Local HTTP tests with fake Pi; no real keys or provider calls."""
import base64
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
import uuid
from unittest.mock import patch
import bridge


def uid(): return str(uuid.uuid4())


class FakePi:
    instances = []
    gate = None
    creating = None
    created_gate = None

    def __init__(self, config, state_dir, on_created=None):
        self.config = config
        self.closed = False
        self.prompts = []
        self.history = []
        self.started = threading.Event()
        self.release = threading.Event()
        self.instances.append(self)
        if self.creating:
            self.creating.set()
            self.created_gate.wait(3)
        if on_created: on_created(self)

    def restore(self, messages): self.history = messages

    def prompt(self, text, config, images=None, on_event=None):
        if self.closed: raise RuntimeError('prompt after close')
        self.prompts.append((text, images))
        if on_event:
            on_event({'type': 'tool_execution_start', 'toolName': 'read_file'})
            on_event({'type': 'tool_execution_update', 'toolName': 'read_file'})
        self.started.set()
        if self.gate: self.release.wait(3)
        return 'answer: ' + text  # Deliberately completes even after cancellation.

    def close(self): self.closed = True; self.release.set()


class V2Tests(unittest.TestCase):
    def setUp(self):
        FakePi.instances = []; FakePi.gate = None
        FakePi.creating = None; FakePi.created_gate = None
        self.tmp = tempfile.TemporaryDirectory()
        self.config = Path(self.tmp.name) / 'config.json'
        self.config.write_text(json.dumps({'api_key': 'fake', 'model': 'text-model'}))
        self.patch = patch('pi_backend.PiClient', FakePi)
        self.patch.start()
        self.server = bridge.make_server(0, self.config)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = 'http://127.0.0.1:%d' % self.server.server_port

    def tearDown(self):
        if FakePi.created_gate: FakePi.created_gate.set()
        for client in FakePi.instances: client.release.set()
        self.server.shutdown(); self.server.server_close(); self.thread.join(2)
        self.patch.stop(); self.tmp.cleanup()

    def request(self, path, body=None, headers=None):
        req = urllib.request.Request(self.url + path,
            data=None if body is None else json.dumps(body).encode(), headers=headers or {})
        try: response = urllib.request.build_opener(urllib.request.ProxyHandler({})).open(req, timeout=5)
        except urllib.error.HTTPError as error: response = error
        with response: return response.status, json.load(response)

    def payload(self, sid=None, jid=None, text='hello'):
        return dict(session_id=sid or uid(), request_id=jid or uid(),
                    messages=[dict(role='user', content=text)], thinking=True, tools=True)
    def start(self, body): return self.request('/atoll/chat', body)
    def poll(self, body):
        return self.request('/atoll/sessions/%s/jobs/%s' % (body['session_id'], body['request_id']))
    def stop(self, body, jid=None):
        return self.request('/atoll/sessions/%s/stop' % body['session_id'], {'job_id': jid or body['request_id']})
    def reset(self, body): return self.request('/atoll/sessions/%s/reset' % body['session_id'], {})
    def wait_done(self, body):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            status, result = self.poll(body)
            if status != 200 or result['status'] != 'pending': return status, result
            time.sleep(.005)
        self.fail('job did not settle')
    def wait_clients(self, count):
        deadline = time.monotonic() + 3
        while len(FakePi.instances) < count and time.monotonic() < deadline: time.sleep(.005)
        self.assertEqual(len(FakePi.instances), count)
        self.assertTrue(FakePi.instances[-1].started.wait(2))

    def test_health_and_nonblocking_progress(self):
        status, health = self.request('/health')
        self.assertEqual(health.get('protocol_version'), 2)
        self.assertEqual(health['capabilities'], {'jobs': True, 'sessions': True})
        FakePi.gate = True
        body = self.payload()
        self.assertEqual(self.start(body), (202, {'job_id': body['request_id'], 'status': 'pending', 'model': 'text-model'}))
        self.wait_clients(1)
        status, job = self.poll(body)
        self.assertEqual(status, 200)
        self.assertEqual(job, dict(job_id=body['request_id'], status='pending', model='text-model',
                                   tools=['read_file'], phase='tool_execution', content=''))
        FakePi.instances[0].release.set()
        self.assertEqual(self.wait_done(body)[1]['content'], 'answer: hello')

    def test_concurrent_sessions_and_mismatched_stop(self):
        FakePi.gate = True
        one, two = self.payload(), self.payload()
        self.assertEqual(self.start(one)[0], 202); self.assertEqual(self.start(two)[0], 202)
        self.wait_clients(2)
        self.assertEqual(self.stop(one, two['request_id'])[0], 409)
        self.assertEqual(self.poll(one)[1]['status'], 'pending')
        self.assertEqual(self.stop(one)[1]['status'], 'cancelled')
        self.assertEqual(self.poll(one)[1]['status'], 'cancelled')
        self.assertEqual(self.poll(two)[1]['status'], 'pending')
        self.assertEqual(self.start(one)[0], 409)
        for client in FakePi.instances: client.release.set()
        self.assertEqual(self.wait_done(two)[1]['status'], 'completed')

    def test_reset_retires_sid_and_discards_late_completion(self):
        FakePi.gate = True
        body = self.payload()
        self.assertEqual(self.start(body)[0], 202); self.wait_clients(1)
        self.assertEqual(self.reset(body)[0], 200)
        self.assertTrue(FakePi.instances[0].closed)
        self.assertEqual(self.poll(body)[0], 410)
        self.assertEqual(self.start(self.payload(sid=body['session_id']))[0], 410)
        self.assertEqual(self.reset(body)[0], 200)
        self.assertEqual(len(FakePi.instances), 1)

    def test_stop_and_reset_before_start(self):
        body = self.payload()
        self.assertEqual(self.stop(body)[1]['status'], 'cancelled')
        self.assertEqual(self.start(body)[0], 409)
        self.assertEqual(self.poll(body)[1]['status'], 'cancelled')
        self.assertEqual(self.start(self.payload(sid=body['session_id']))[0], 202)
        retired = self.payload()
        self.assertEqual(self.reset(retired)[0], 200)
        self.assertEqual(self.start(retired)[0], 410)

    def test_cancel_creation_waits_for_worker_before_ack(self):
        for action in (self.stop, self.reset):
            with self.subTest(action=action.__name__):
                FakePi.creating = threading.Event(); FakePi.created_gate = threading.Event()
                body = self.payload()
                self.assertEqual(self.start(body)[0], 202)
                self.assertTrue(FakePi.creating.wait(2))
                result = []
                thread = threading.Thread(target=lambda: result.append(action(body)))
                thread.start(); time.sleep(.04)
                self.assertTrue(thread.is_alive(), 'ack before constructor exits')
                FakePi.created_gate.set(); thread.join(3)
                self.assertFalse(thread.is_alive())
                self.assertEqual(result[0][0], 200)
                self.assertTrue(FakePi.instances[-1].closed)
                self.assertEqual(FakePi.instances[-1].prompts, [])

    def test_ids_flags_and_image_validation(self):
        valid = self.payload(); invalid = []
        for key in ('session_id', 'request_id', 'thinking', 'tools', 'messages'):
            body = dict(valid); del body[key]; invalid.append(body)
        for key in ('session_id', 'request_id'):
            for value in ('', '../x', 'not-uuid', 123, None, uid().replace('-', '')):
                invalid.append(dict(valid, **{key: value}))
        invalid.extend([dict(valid, thinking=1), dict(valid, tools='true'),
            dict(valid, messages=[{'role': 'user', 'content': 'x', 'images': ['bad']}]),
            dict(valid, messages=[{'role': 'assistant', 'content': 'x'}])])
        for body in invalid:
            with self.subTest(body=body): self.assertEqual(self.start(body)[0], 400)
        self.assertEqual(self.request('/atoll/sessions/bad/reset', {})[0], 400)
        self.assertEqual(self.request('/atoll/sessions/%s/stop' % uid(), {})[0], 400)
        self.assertEqual(self.request('/atoll/sessions/%s/jobs/bad' % uid())[0], 400)
        self.assertEqual(self.poll(valid)[0], 404)

    def test_host_and_origin_checks_cover_v2(self):
        for headers in ({'Host': 'evil.example'}, {'Origin': 'http://localhost'}):
            self.assertEqual(self.request('/atoll/chat', self.payload(), headers)[0], 403)
            self.assertEqual(self.request('/health', headers=headers)[0], 403)

    def test_reconnect_full_history_stop_and_vision(self):
        png = base64.b64encode(b'\x89PNG\r\n\x1a\nfixture').decode()
        body = self.payload(text='look'); body['messages'][0]['images'] = [png]
        self.assertEqual(self.start(body)[1]['model'], 'deepseek-v4-flash-vision-exp')
        self.assertEqual(self.wait_done(body)[1]['status'], 'completed')
        previous = FakePi.instances[-1]
        follow = self.payload(sid=body['session_id'], text='what color?')
        follow['messages'] = body['messages'] + [{'role': 'assistant', 'content': 'answer: look'}] + follow['messages']
        self.assertEqual(self.start(follow)[1]['model'], 'deepseek-v4-flash-vision-exp')
        self.wait_done(follow)
        self.assertEqual(len(FakePi.instances), 1); self.assertFalse(previous.closed)
        self.stop(follow)
        again = dict(follow, request_id=uid())
        self.start(again); self.wait_done(again)
        self.assertEqual(FakePi.instances[-1].history[0]['images'][0]['data'], png)
        self.assertEqual(FakePi.instances[-1].history[1]['content'], 'answer: look')
        self.assertEqual(FakePi.instances[-1].prompts, [('what color?', None)])
        reconnect = self.payload(sid=body['session_id'], text='new transcript')
        self.start(reconnect); self.wait_done(reconnect)
        self.assertTrue(FakePi.instances[-2].closed)
        self.assertEqual(FakePi.instances[-1].history, [])

    def test_duplicate_requests_and_busy_session(self):
        FakePi.gate = True
        body = self.payload()
        self.assertEqual(self.start(body)[0], 202); self.wait_clients(1)
        self.assertEqual(self.start(body)[0], 202)
        self.assertEqual(self.start(dict(body, tools=False))[0], 409)
        self.assertEqual(self.start(self.payload(sid=body['session_id']))[0], 409)
        FakePi.instances[0].release.set(); self.wait_done(body)
        self.assertEqual(self.start(body)[0], 200)
        self.assertEqual(len(FakePi.instances[0].prompts), 1)

    def test_uuid_case_preserves_accepted_job_id_and_normalizes_lookup(self):
        body = self.payload()
        body['session_id'] = body['session_id'].upper()
        body['request_id'] = body['request_id'].upper()
        self.assertEqual(self.start(body)[1]['job_id'], body['request_id'])
        self.assertEqual(self.wait_done(body)[1]['job_id'], body['request_id'])
        lower = {**body, 'session_id': body['session_id'].lower(), 'request_id': body['request_id'].lower()}
        self.assertEqual(self.poll(lower)[1]['job_id'], body['request_id'])
        self.assertEqual(self.stop(lower)[1]['status'], 'cancelled')
        self.assertEqual(self.start(body)[0], 409)

    def test_idle_cleanup_and_model_switch_restore_full_history(self):
        body = self.payload(text='first')
        body['messages'].insert(0, {'role': 'system', 'content': 'Remember the context'})
        self.start(body); self.wait_done(body)
        follow = self.payload(sid=body['session_id'], text='followup')
        follow['messages'] = body['messages'] + [{'role': 'assistant', 'content': 'answer: first'}] + follow['messages']
        with patch('jobs.IDLE_SECONDS', 0): self.server.jobs.cleanup()
        self.assertTrue(FakePi.instances[0].closed)
        self.start(follow); self.wait_done(follow)
        self.assertEqual(FakePi.instances[-1].history, follow['messages'][:-1])
        self.config.write_text(json.dumps({'api_key': 'fake', 'model': 'second-model'}))
        another = self.payload(sid=body['session_id'], text='third')
        another['messages'] = follow['messages'] + [{'role': 'assistant', 'content': 'answer: followup'}] + another['messages']
        another['thinking'] = False; another['tools'] = False
        self.assertEqual(self.start(another)[1]['model'], 'second-model')
        self.assertEqual(self.wait_done(another)[1]['model'], 'second-model')
        self.assertTrue(FakePi.instances[-2].closed)
        self.assertEqual(FakePi.instances[-1].history, another['messages'][:-1])
        self.assertFalse(FakePi.instances[-1].config['thinking'])
        self.assertFalse(FakePi.instances[-1].config['tools'])

    def test_late_http_start_after_stop_or_reset_ack_is_fenced(self):
        import jobs
        original = jobs.validate_chat
        for action, expected in ((self.stop, 409), (self.reset, 410)):
            entered, release = threading.Event(), threading.Event()
            body = self.payload(); result = []
            def validate(payload):
                entered.set(); release.wait(3)
                return original(payload)
            with patch('jobs.validate_chat', side_effect=validate):
                worker = threading.Thread(target=lambda: result.append(self.start(body)))
                worker.start(); self.assertTrue(entered.wait(2))
                self.assertEqual(action(body)[0], 200)
                release.set(); worker.join(3)
                self.assertEqual(result[0][0], expected)
        self.assertEqual(FakePi.instances, [])

    def test_missing_key_and_backend_failure_are_pollable(self):
        self.config.write_text('{}')
        body = self.payload(); self.assertEqual(self.start(body)[0], 202)
        result = self.wait_done(body)[1]
        self.assertEqual(result['status'], 'failed'); self.assertEqual(result['phase'], 'failed')
        self.assertIn('API Key', result['content'])
        self.assertEqual(FakePi.instances, [])
        self.config.write_text(json.dumps({'api_key': 'fake'}))
        with patch.object(FakePi, 'prompt', side_effect=RuntimeError('secret must not leak')):
            body = self.payload(); self.start(body)
            result = self.wait_done(body)[1]
            self.assertEqual(result['status'], 'failed')
            self.assertNotIn('secret', result['content'])
            self.assertTrue(FakePi.instances[-1].closed)

    def test_bounded_cleanup_keeps_stop_reset_and_dedupe_fences(self):
        with patch('jobs.MAX_RESULTS', 1):
            one, two = self.payload(), self.payload()
            self.start(one); self.wait_done(one)
            self.start(two); self.wait_done(two)
            self.assertEqual(self.poll(one)[0], 410)
            self.assertEqual(self.start(one)[0], 410)
            self.assertEqual(self.poll(two)[1]['status'], 'completed')
        self.stop(two)
        with patch('jobs.IDLE_SECONDS', 0), patch('jobs.RESULT_SECONDS', 0): self.server.jobs.cleanup()
        self.assertEqual(len(self.server.jobs.sessions), 0)
        self.assertTrue(all(c.closed for c in FakePi.instances))
        self.assertEqual(self.start(two)[0], 409)
        self.reset(one)
        self.assertEqual(self.start(self.payload(sid=one['session_id']))[0], 410)
        self.assertFalse(any((self.config.parent / 'pi-native').glob('*/models.json')))

    def test_capacity_rejects_new_ids_without_evicting_fences(self):
        with patch('jobs.MAX_IDENTITIES', 2), patch('jobs.MAX_REQUESTS', 2):
            one, two, three = self.payload(), self.payload(), self.payload()
            self.assertEqual(self.stop(one)[0], 200); self.assertEqual(self.stop(two)[0], 200)
            self.assertEqual(self.stop(three)[0], 503)
            self.assertEqual(self.start(self.payload(sid=one['session_id']))[0], 503)
            self.assertEqual(self.start(one)[0], 409)
            self.assertEqual(self.reset(one)[0], 200)
            self.assertEqual(self.start(one)[0], 410)

    def test_same_session_unknown_stop_does_not_close_unrelated_idle_client(self):
        body = self.payload(); self.start(body); self.wait_done(body)
        client = FakePi.instances[-1]
        early = self.payload(sid=body['session_id'])
        self.assertEqual(self.stop(early)[0], 200)
        self.assertFalse(client.closed)
        self.assertEqual(self.poll(body)[1]['status'], 'completed')

    def test_stop_wrong_session_rejects_an_id_owned_elsewhere(self):
        body = self.payload(); self.start(body); self.wait_done(body)
        wrong = self.payload(jid=body['request_id'])
        self.assertEqual(self.stop(wrong)[0], 409)
        self.assertFalse(FakePi.instances[-1].closed)

    def test_watchdog_fails_stalled_job_and_discards_its_late_result(self):
        FakePi.gate = True
        body = self.payload(); self.start(body); self.wait_clients(1)
        with patch('jobs.MAX_JOB_SECONDS', 0, create=True): self.server.jobs.cleanup()
        result = self.poll(body)[1]
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['phase'], 'failed')
        self.assertTrue(FakePi.instances[-1].closed)
        self.assertNotIn('answer:', result['content'])

    def test_partial_text_and_thinking_phase_do_not_expose_reasoning(self):
        thinking_ready, text_ready, advance = threading.Event(), threading.Event(), threading.Event()
        def prompt(client, text, config, images=None, on_event=None):
            on_event({'type': 'message_update', 'assistantMessageEvent': {'type': 'thinking_delta', 'delta': 'hidden'}})
            thinking_ready.set(); advance.wait(3)
            on_event({'type': 'message_update', 'assistantMessageEvent': {'type': 'text_delta', 'delta': 'visible'}})
            text_ready.set(); client.release.wait(3)
            return 'visible answer'
        with patch.object(FakePi, 'prompt', prompt):
            body = self.payload(); self.start(body)
            self.assertTrue(thinking_ready.wait(2))
            result = self.poll(body)[1]
            self.assertEqual((result['phase'], result['content']), ('thinking', ''))
            advance.set(); self.assertTrue(text_ready.wait(2))
            result = self.poll(body)[1]
            self.assertEqual((result['phase'], result['content']), ('generating', 'visible'))
            FakePi.instances[-1].release.set()
            self.assertEqual(self.wait_done(body)[1]['content'], 'visible answer')

    def test_native_reset_and_legacy_reset_are_independent(self):
        FakePi.gate = True
        body = self.payload(); self.start(body); self.wait_clients(1)
        self.assertEqual(self.request('/api/chat', {'messages': [{'role': 'user', 'content': '/reset'}]})[0], 200)
        self.assertEqual(self.poll(body)[1]['status'], 'pending')
        self.assertFalse(FakePi.instances[0].closed)
        legacy = FakePi({'api_key': 'fake'}, self.tmp.name)
        self.server.session.client = legacy
        self.reset(body)
        self.assertFalse(legacy.closed)

    def test_duplicate_stop_ack_waits_for_same_cancelled_worker(self):
        FakePi.creating, FakePi.created_gate = threading.Event(), threading.Event()
        body = self.payload(); self.start(body); self.assertTrue(FakePi.creating.wait(2))
        results = []
        threads = [threading.Thread(target=lambda: results.append(self.stop(body))) for _ in range(2)]
        for thread in threads: thread.start()
        time.sleep(.05)
        self.assertEqual(results, [])
        FakePi.created_gate.set()
        for thread in threads: thread.join(3)
        self.assertEqual([r[0] for r in results], [200, 200])
        self.assertEqual(FakePi.instances[-1].prompts, [])
        self.assertTrue(FakePi.instances[-1].closed)

    def test_custom_vision_model_upgrades_text_only_client_without_losing_history(self):
        self.config.write_text(json.dumps({'api_key': 'fake', 'model': 'custom-vision', 'vision_model': 'custom-vision'}))
        body = self.payload(text='first'); self.start(body); self.wait_done(body)
        image = self.payload(sid=body['session_id'], text='look')
        png = base64.b64encode(b'\x89PNG\r\n\x1a\nfixture').decode()
        image['messages'][-1]['images'] = [png]
        image['messages'] = body['messages'] + [{'role': 'assistant', 'content': 'answer: first'}] + image['messages']
        self.start(image); self.wait_done(image)
        self.assertTrue(FakePi.instances[0].closed)
        self.assertTrue(FakePi.instances[-1].config['_vision'])
        self.assertEqual(FakePi.instances[-1].history, body['messages'] + [{'role': 'assistant', 'content': 'answer: first'}])
        self.assertEqual(FakePi.instances[-1].prompts[-1][1][0]['data'], png)

    def test_result_trimming_cannot_drop_a_stalled_workers_join_handle(self):
        FakePi.creating, FakePi.created_gate = threading.Event(), threading.Event()
        body = self.payload(); self.start(body); self.assertTrue(FakePi.creating.wait(2))
        with patch('jobs.MAX_JOB_SECONDS', 0), patch('jobs.MAX_RESULTS', 0):
            cleanup = threading.Thread(target=self.server.jobs.cleanup)
            cleanup.start(); time.sleep(.05)
            self.assertTrue(cleanup.is_alive(), 'cleanup detached a constructor by trimming its worker handle')
            FakePi.created_gate.set(); cleanup.join(3)
            self.assertFalse(cleanup.is_alive())
        self.assertTrue(FakePi.instances[-1].closed)
        self.assertEqual(FakePi.instances[-1].prompts, [])

if __name__ == '__main__': unittest.main()
