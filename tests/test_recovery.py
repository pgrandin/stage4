"""Run with python3 -m unittest discover -s tests."""
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class RecoveryTests(unittest.TestCase):
    def test_resume_retries_saved_list_without_restarting_world(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as tmp:
            root = Path(tmp)
            emerge = root / "emerge"
            emerge.write_text('#!/bin/bash\necho "$*" >> "$CALLS"\n[[ $(wc -l < "$CALLS") -gt 1 ]]\n')
            emerge.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}", CALLS=str(root / "calls"))
            result = subprocess.run(["bash", str(REPO / "chroot/03_rebuild_world.sh"), "XPS-9730", "--resume"], env=env)
            self.assertEqual(result.returncode, 0)
            calls = (root / "calls").read_text().splitlines()
            self.assertEqual(len(calls), 2)
            self.assertTrue(all(c.startswith("--resume ") and "@world" not in c for c in calls))

    def test_validation_rejects_missing_package_excluded_packages_and_kernel(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as tmp:
            root = Path(tmp)
            (root / "var/lib/portage").mkdir(parents=True)
            (root / "var/tmp").mkdir(parents=True)
            (root / "var/lib/portage/world").write_text("net-dns/bind\ngui-apps/sddm\n")
            query = root / "portageq"
            query.write_text('#!/bin/bash\ngrep -qxF "$3" "$2/installed"\n')
            query.chmod(0o755)
            installed = root / "installed"
            installed.write_text("net-dns/bind\ngui-apps/sddm\n")
            kernel = root / "kernel-test.tgz"
            with tarfile.open(kernel, "w:gz") as archive:
                for name in ("usr/src/linux/arch/x86/boot/bzImage", "lib/modules/test/kernel/test.ko"):
                    item = tarfile.TarInfo(name)
                    item.size = 1
                    archive.addfile(item, io.BytesIO(b"x"))
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}")

            def validate():
                return subprocess.run(["bash", str(REPO / "chroot/06_validate.sh"), str(root)], env=env, capture_output=True, text=True)

            self.assertEqual(validate().returncode, 0)
            installed.write_text("net-dns/bind\n")
            self.assertIn("gui-apps/sddm", validate().stderr)
            self.assertNotEqual(validate().returncode, 0)
            for excluded in ("www-client/firefox", "www-client/chromium", "media-gfx/blender"):
                with self.subTest(excluded=excluded):
                    installed.write_text(f"net-dns/bind\ngui-apps/sddm\n{excluded}\n")
                    result = validate()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(excluded, result.stderr)
            installed.write_text("net-dns/bind\ngui-apps/sddm\n")
            kernel.unlink()
            self.assertNotEqual(validate().returncode, 0)
