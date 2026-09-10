import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import pi_backend

class FakePi:
    def __init__(self,config,state_dir): self.config=config; self.prompts=[]; self.closed=False
    def prompt(self,text,config): self.prompts.append(text); return 'answer '+str(len(self.prompts))
    def close(self): self.closed=True

class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.session=pi_backend.Session(self.tmp.name,wait_seconds=.2)
        self.config={'api_key':'test','model':'deepseek-v4-flash'}
    def tearDown(self): self.session.reset(); self.tmp.cleanup()
    def chat(self,text): return self.session.chat(self.config,[{'role':'user','content':text}])
    def test_memory_reset_and_switches(self):
        with patch('pi_backend.PiClient',FakePi):
            self.assertEqual(self.chat('first'),'answer 1')
            client=self.session.client
            self.assertEqual(self.chat('second'),'answer 2')
            self.chat('/thinking off'); self.chat('/tools off')
            self.assertEqual(self.session.overrides,{'thinking':False,'tools':False})
            self.chat('/reset')
            self.assertTrue(client.closed)
            self.assertEqual(self.chat('third'),'answer 1')
    def test_pending_does_not_drop_new_prompt_silently(self):
        event=threading.Event()
        class Slow(FakePi):
            def prompt(self,text,config): event.wait(2); return 'done'
        self.session.wait_seconds=.005
        with patch('pi_backend.PiClient',Slow):
            self.assertIn('/result',self.chat('slow'))
            self.assertIn('尚未执行',self.chat('new question'))
            event.set(); time.sleep(.02)
            self.assertEqual(self.chat('/result'),'done')
    def test_reset_discards_old_result(self):
        event=threading.Event()
        class Slow(FakePi):
            def prompt(self,text,config): event.wait(1); return 'old'
            def close(self): event.set()
        self.session.wait_seconds=.005
        with patch('pi_backend.PiClient',Slow):
            self.chat('slow'); self.chat('/reset'); time.sleep(.03)
            self.assertIn('没有',self.chat('/result'))
            self.assertEqual(self.session.turn_count,0)
    def test_image_reaches_rpc(self):
        import queue
        client=object.__new__(pi_backend.PiClient)
        client.events=queue.Queue()
        sent=[]
        def send(message):
            sent.append(message)
            client.events.put({'type':'response','id':message.get('id'),'success':True})
            if message.get('id')=='prompt':
                client.events.put({'type':'message_end','message':{'role':'assistant','content':[{'type':'text','text':'Red'}]}})
                client.events.put({'type':'agent_settled'})
        client.send=send
        image={'type':'image','data':'encoded','mimeType':'image/png'}
        self.assertEqual(client.prompt('color?',self.config,images=[image]),'Red')
        self.assertEqual(sent[-1]['images'],[image])

    def test_credential_change_new_session(self):
        with patch('pi_backend.PiClient',FakePi):
            self.chat('hi'); old=self.session.client
            self.config['api_key']='new'
            self.chat('hi again')
            self.assertTrue(old.closed)
            self.assertEqual(self.session.turn_count,1)

if __name__ == '__main__': unittest.main()
