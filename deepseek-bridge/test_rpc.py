"""Exercise the real PiClient against an offline JSON-lines subprocess."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import pi_backend


def fake_process():
    def emit(event): print(json.dumps(event), flush=True)
    directory = Path(os.environ['PI_CODING_AGENT_DIR'])
    mode = os.environ['DEEPSEEK_API_KEY']
    for line in sys.stdin:
        request = json.loads(line)
        with (directory / 'rpc.jsonl').open('a') as log: log.write(line)
        reply = {'type': 'response', 'id': request.get('id'), 'success': True}
        if request['type'] == 'get_commands':
            reply['data'] = {'commands': [{'name': 'atoll-tools'}, {'name': 'atoll-context'}]}
        emit(reply)
        if request.get('id') == 'tools' and mode == 'fake-block-input':
            (directory / 'blocked').touch()
            time.sleep(30)
        if request.get('id') == 'prompt':
            emit({'type': 'agent_start'})
            emit({'type': 'message_start', 'message': {'role': 'assistant', 'content': []}})
            emit({'type': 'message_update', 'assistantMessageEvent': {'type': 'thinking_delta', 'delta': 'private reasoning'}})
            emit({'type': 'tool_execution_start', 'toolName': 'read_file', 'toolCallId': 'one', 'args': {}})
            if mode == 'fake-tool':
                child = subprocess.Popen([sys.executable, '-c',
                    'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); print("ready",flush=True); time.sleep(30)'],
                    stdout=subprocess.PIPE, text=True)
                child.stdout.readline()
                (directory / 'child.pid').write_text(str(child.pid))
                time.sleep(30)
            emit({'type': 'tool_execution_update', 'toolName': 'read_file', 'toolCallId': 'one', 'partialResult': {'content': []}})
            emit({'type': 'tool_execution_end', 'toolName': 'read_file', 'toolCallId': 'one', 'isError': False})
            emit({'type': 'message_update', 'assistantMessageEvent': {'type': 'text_delta', 'delta': 'hello'}})
            emit({'type': 'message_end', 'message': {'role': 'assistant', 'stopReason': 'stop', 'content': [{'type': 'text', 'text': 'hello'}]}})
            emit({'type': 'agent_settled'})


class RPCTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = Path(self.tmp.name)
        self.clients = []
        real_popen = subprocess.Popen
        def spawn(args, **kwargs):
            return real_popen([sys.executable, str(Path(__file__).resolve()), '--fake-pi'], **kwargs)
        self.spawn_patch = patch('pi_backend.subprocess.Popen', side_effect=spawn)
        self.which_patch = patch('pi_backend.shutil.which', return_value='fake-pi')
        self.spawn_patch.start(); self.which_patch.start()

    def tearDown(self):
        for client in self.clients: client.close()
        self.spawn_patch.stop(); self.which_patch.stop(); self.tmp.cleanup()

    def client(self, mode='fake-normal', on_created=None):
        client = pi_backend.PiClient({'api_key': mode, 'model': 'test-model', '_native': True},
                                     self.directory, on_created=on_created)
        self.clients.append(client)
        return client

    def wait_file(self, name):
        deadline = time.monotonic() + 3
        path = self.directory / name
        while not path.exists() and time.monotonic() < deadline: time.sleep(.005)
        self.assertTrue(path.exists())
        return path

    def test_context_and_images_are_rpc_commands_not_replayed_turns(self):
        client = self.client()
        history = [{'role': 'system', 'content': 'System'}, {'role': 'user', 'content': 'look',
                   'images': [{'type': 'image', 'data': 'encoded', 'mimeType': 'image/png'}]},
                   {'role': 'assistant', 'content': 'red'}]
        client.restore(history)
        events = []
        self.assertEqual(client.prompt('color?', client.config, on_event=events.append), 'hello')
        requests = [json.loads(line) for line in (self.directory / 'rpc.jsonl').read_text().splitlines()]
        context = next(r for r in requests if r.get('id') == 'context')
        self.assertEqual(json.loads(context['message'].split(' ', 1)[1]), history)
        self.assertEqual([r['message'] for r in requests if r.get('id') == 'prompt'], ['color?'])
        self.assertEqual([e['toolName'] for e in events if e['type'] == 'tool_execution_start'], ['read_file'])
        self.assertFalse(json.loads((self.directory / 'settings.json').read_text())['compaction']['enabled'])
        client.close()
        with self.assertRaises(pi_backend.BackendError): client.prompt('late', client.config)

    def test_custom_vision_configuration_advertises_image_input(self):
        client = pi_backend.PiClient({'api_key': 'fake', 'model': 'custom-vision', '_native': True, '_vision': True}, self.directory)
        self.clients.append(client)
        models = json.loads((self.directory / 'models.json').read_text())
        self.assertEqual(models['providers']['atoll-deepseek']['models'][0]['input'], ['text', 'image'])

    def test_cancellation_breaks_a_blocked_pipe_write(self):
        client = self.client('fake-block-input')
        self.wait_file('blocked')
        errors = []
        def restore():
            try: client.restore([{'role': 'user', 'content': 'x' * 2000000}])
            except pi_backend.BackendError as error: errors.append(error)
        worker = threading.Thread(target=restore); worker.start()
        time.sleep(.05)
        start = time.monotonic(); client.close(); worker.join(3)
        self.assertLess(time.monotonic() - start, 3)
        self.assertFalse(worker.is_alive())
        self.assertEqual(len(errors), 1)

    def test_close_kills_tool_group_even_when_parent_exits_first(self):
        client = self.client('fake-tool')
        errors = []
        def prompt():
            try: client.prompt('read', client.config)
            except pi_backend.BackendError as error: errors.append(error)
        worker = threading.Thread(target=prompt); worker.start()
        pid = int(self.wait_file('child.pid').read_text())
        client.close(); worker.join(3)
        self.assertFalse(worker.is_alive())
        self.assertIsNotNone(client.proc.poll())
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            try: os.kill(pid, 0)
            except ProcessLookupError: break
            time.sleep(.01)
        else: self.fail('tool child survived cancellation')
        self.assertEqual(len(errors), 1)

    def test_cancel_immediately_after_spawn_does_not_send_startup(self):
        clients = []
        def cancel(client): clients.append(client); client.close()
        with self.assertRaises(pi_backend.BackendError): self.client(on_created=cancel)
        self.assertIsNotNone(clients[0].proc.poll())
        self.assertFalse((self.directory / 'rpc.jsonl').exists())


if __name__ == '__main__':
    if '--fake-pi' in sys.argv: fake_process()
    else: unittest.main()
