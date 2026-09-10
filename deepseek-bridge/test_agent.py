import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
import agent_tools

class ToolTests(unittest.TestCase):
    def test_file_scope_and_symlink(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside:
            root=Path(directory)
            (root/'ok.txt').write_text('hello')
            (root/'.env').write_text('secret')
            (root/'link').symlink_to(outside,target_is_directory=True)
            config={'read_roots':[str(root)]}
            self.assertIn('hello',agent_tools.execute('read_file',{'path':str(root/'ok.txt')},config))
            for path in (str(root/'.env'),str(root/'link'/'x'),str(Path(outside)/'x')):
                with self.assertRaises(ValueError): agent_tools.execute('read_file',{'path':path},config)
    def test_each_file_access_requires_consent(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'note.txt'
            path.write_text('approved text')
            with patch('agent_tools.approve',return_value=False) as approve:
                with self.assertRaises(ValueError):
                    agent_tools.execute('read_file',{'path':str(path)},{'file_access':'ask'})
                approve.assert_called_once_with(path.resolve(),False)
            with patch('agent_tools.approve',return_value=True) as approve:
                self.assertIn('approved text',agent_tools.execute('read_file',{'path':str(path)},{'file_access':'ask'}))
                approve.assert_called_once_with(path.resolve(),False)
    def test_credentials_excluded_even_with_approval(self):
        with patch('agent_tools.approve',return_value=True) as approve:
            with self.assertRaises(ValueError):
                agent_tools.execute('read_file',{'path':str(agent_tools.SECRET_DIR/'config.json')},{'file_access':'ask'})
            approve.assert_not_called()
    def test_private_url_blocked(self):
        for url in ('http://127.0.0.1/x','http://169.254.169.254','file:///etc/passwd','https://user:pass@example.com'):
            with self.assertRaises(ValueError): agent_tools.public_url(url)
    def test_dns_private_blocked(self):
        with patch('agent_tools.socket.getaddrinfo',return_value=[(2,1,6,'',('127.0.0.1',443))]):
            with self.assertRaises(ValueError): agent_tools.public_url('https://example.com')
    def test_hidden_file_not_listed(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'.env').write_text('secret')
            (root/'note.txt').write_text('hello')
            output=agent_tools.execute('list_files',{'path':directory},{'read_roots':[directory]})
            self.assertIn('note.txt',output)
            self.assertNotIn('.env',output)

if __name__ == '__main__': unittest.main()
