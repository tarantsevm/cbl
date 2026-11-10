"""Release privacy regressions; real packaging with a fake Go compiler."""
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]


class ReleasePrivacyTests(unittest.TestCase):
    def test_release_omits_builder_metadata(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as tmp:
            base = Path(tmp)
            fake = base / 'fake'
            fake.mkdir()
            compiler = fake / 'go'
            compiler.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
with open(os.environ['GO_BUILD_LOG'], 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
out = pathlib.Path(sys.argv[sys.argv.index('-o') + 1])
out.write_text('synthetic build for packaging test\\n')
out.chmod(0o755)
''')
            compiler.chmod(0o755)
            log = base / 'build.jsonl'
            env = dict(os.environ, PATH=str(fake) + ':' + os.environ['PATH'],
                       GO_BUILD_LOG=str(log), VERSION='v0.0.0-test')
            out = base / 'out'
            result = subprocess.run(['bash', str(ROOT / 'release/package-release.sh'), str(out)],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            builds = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(len(builds), 2)
            for args in builds:
                self.assertIn('-trimpath', args)
                self.assertIn('-buildvcs=false', args)
            with tarfile.open(out / 'cbl-v0.0.0-test-linux-amd64.tar.gz') as archive:
                license_file = archive.extractfile('cbl-v0.0.0-test/LICENSE')
                self.assertIsNotNone(license_file)
                assert license_file is not None
                self.assertEqual(license_file.read(), (ROOT / 'LICENSE').read_bytes())
                notices = archive.extractfile('cbl-v0.0.0-test/THIRD_PARTY_NOTICES.txt')
                assert notices is not None
                self.assertEqual(notices.read(), (ROOT / 'THIRD_PARTY_NOTICES.txt').read_bytes())
                for member in archive:
                    self.assertEqual((member.uid, member.gid, member.uname, member.gname),
                                     (0, 0, '', ''), member.name)
                    self.assertEqual(member.mtime, 0, member.name)
            with zipfile.ZipFile(out / 'cbl-v0.0.0-test-linux-amd64.zip') as archive:
                for member in archive.infolist():
                    self.assertEqual(member.date_time, (1980, 1, 1, 0, 0, 0), member.filename)
                    self.assertFalse(member.extra, member.filename)
                    self.assertFalse(member.comment, member.filename)


if __name__ == '__main__':
    unittest.main()
