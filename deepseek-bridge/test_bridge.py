import json
import threading
import unittest
import urllib.request
import urllib.error
from unittest.mock import patch
from pathlib import Path
import tempfile
import bridge

class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.server = bridge.make_server(0, Path(self.tmp.name) / 'config.json')
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = 'http://127.0.0.1:%d' % self.server.server_port
    def tearDown(self):
        self.server.session.reset()
        self.server.shutdown()
        self.server.server_close()
        self.tmp.cleanup()
    def post(self, body, headers=None):
        request = urllib.request.Request(self.url + '/api/chat', data=json.dumps(body).encode(), headers=headers or {'Content-Type':'application/json'})
        return json.load(urllib.request.urlopen(request))
    def test_missing_key_visible_in_atoll(self):
        result = self.post({'messages':[{'role':'user','content':'hello'}]})
        self.assertIn('API Key', result['message']['content'])
        self.assertTrue(result['done'])
    def test_translation_and_model_override(self):
        self.server.config_path.write_text(json.dumps({'api_key':'fake-key','model':'deepseek-v4-flash'}))
        with patch.object(self.server.session, 'chat', return_value='你好') as call:
            result = self.post({'model':'llama3.2','stream':False,'messages':[{'role':'user','content':'hello'}]})
        self.assertEqual(result['message']['content'], '你好')
        self.assertEqual(call.call_args[0][1], [{'role':'user','content':'hello'}])
        self.assertEqual(result['model'],'deepseek-v4-flash')
    def test_images_are_forwarded(self):
        import base64
        png=base64.b64encode(b'\x89PNG\r\n\x1a\n' + b'test').decode()
        message={'role':'user','content':'color?','images':[png]}
        with patch.object(self.server.session,'chat',return_value='Red') as call:
            result=self.post({'messages':[message]})
        self.assertEqual(result['message']['content'],'Red')
        self.assertEqual(call.call_args[0][1][0]['images'],[png])

    def test_browser_origin_rejected(self):
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.post({}, {'Origin':'https://example.com','Content-Type':'application/json'})
        self.assertEqual(error.exception.code, 403)
    def test_invalid_messages(self):
        with self.assertRaises(urllib.error.HTTPError): self.post({'messages':'wrong'})
    def test_status_without_key(self):
        result = self.post({'messages':[{'role':'user','content':'/status'}]})
        self.assertIn('pi + DeepSeek',result['message']['content'])

if __name__ == '__main__': unittest.main()
