"""Real signed bundles and production install transaction, confined to build/ and private HOME."""
import importlib.util
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('folio_release_grade', ROOT / 'scripts/release_grade.py')
grade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grade)
SOURCE = Path('/Applications/Folio.app')


class LocalInstallTests(unittest.TestCase):
    def setUp(self):
        self.real_digest = grade.digest(SOURCE / 'Contents/MacOS/TLMarkdown')
        parent = ROOT / 'build/accept/local-install'
        parent.mkdir(parents=True, exist_ok=True)
        self.work = Path(tempfile.mkdtemp(dir=parent))
        self.destination = self.work / 'Applications/Folio.app'
        self.destination.parent.mkdir()
        grade.subprocess.run(['ditto', str(SOURCE), str(self.destination)], check=True)
        self.home = self.work / 'home'
        self.home.mkdir()
        self.patch_destination = patch.object(grade, 'DESTINATION', self.destination)
        self.patch_home = patch.dict(os.environ, {'HOME': str(self.home)})
        self.patch_destination.start(); self.patch_home.start()

    def tearDown(self):
        self.patch_home.stop(); self.patch_destination.stop()
        self.assertEqual(grade.digest(SOURCE / 'Contents/MacOS/TLMarkdown'), self.real_digest)
        shutil.rmtree(self.work)

    def test_real_signed_transaction_preserves_previous_and_private_cli(self):
        result = grade.install_local(SOURCE)
        self.assertFalse(result['distribution'])
        self.assertFalse(result['notarization_requested'])
        previous = Path(result['previous'])
        self.assertEqual(grade.digest(previous / 'Contents/MacOS/TLMarkdown'), self.real_digest)
        self.assertEqual(grade.digest(self.destination / 'Contents/MacOS/TLMarkdown'), self.real_digest)
        self.assertEqual((self.home / '.local/bin/folio').resolve(), self.destination / 'Contents/Resources/bin/folio')

    def test_actual_cli_collision_rolls_app_back_and_preserves_existing_link(self):
        link = self.home / '.local/bin/folio'
        link.parent.mkdir(parents=True)
        link.symlink_to(self.home / 'unrelated-command')
        with self.assertRaises(grade.subprocess.CalledProcessError):
            grade.install_local(SOURCE)
        self.assertEqual(os.readlink(link), str(self.home / 'unrelated-command'))
        self.assertEqual(grade.digest(self.destination / 'Contents/MacOS/TLMarkdown'), self.real_digest)

    def test_post_swap_verification_failure_restores_the_real_previous_bundle(self):
        actual = grade.signature_grade
        visits = 0

        def fault(path):
            nonlocal visits
            if Path(path) == self.destination:
                visits += 1
                if visits == 2:
                    raise grade.BelowGrade('injected post-copy validation failure')
            return actual(path)

        with patch.object(grade, 'signature_grade', side_effect=fault):
            with self.assertRaises(grade.BelowGrade):
                grade.install_local(SOURCE)
        self.assertEqual(grade.digest(self.destination / 'Contents/MacOS/TLMarkdown'), self.real_digest)
        self.assertFalse((self.home / '.local/bin/folio').exists())


if __name__ == '__main__':
    unittest.main()
