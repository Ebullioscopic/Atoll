import base64
import tempfile
import unittest
from pathlib import Path
import images

PNG=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=')
class Tests(unittest.TestCase):
    def test_binary_payload_survives(self):
        result=images.decode_images([base64.b64encode(PNG).decode()])
        self.assertEqual(result[0]['mimeType'],'image/png')
        self.assertEqual(base64.b64decode(result[0]['data']),PNG)
    def test_non_image_rejected(self):
        with self.assertRaises(ValueError): images.decode_images([base64.b64encode(b'secret text').decode()])
    def test_legacy_only_exact_screenshot(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'screenshot_123.png').write_bytes(PNG)
            text='Question\n\nI have attached the following files for your analysis:\n- screenshot_123.png (Image)\n\nPlease analyze these files in the context of my question.'
            self.assertEqual(len(images.legacy_images(text,root)),1)
            self.assertEqual(images.legacy_images('hello',root),[])
            with self.assertRaises(ValueError): images.legacy_images(text.replace('screenshot_123.png','other.png'),root)
    def test_explicit_path_with_spaces(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'my image.png'; p.write_bytes(PNG)
            prompt,result=images.prepare('/image '+str(p)+'\nDescribe it',[],Path(tmp))
            self.assertEqual(prompt,'Describe it'); self.assertEqual(len(result),1)
    def test_missing_screenshot_fails_visibly(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError): images.legacy_images('I have attached the following files for your analysis:\n- screenshot_123.png (Image)',Path(tmp))
if __name__=='__main__': unittest.main()
