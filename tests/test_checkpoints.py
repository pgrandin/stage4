"""Checkpoint recovery uses disk state, not the lifetime or ID of a CI job."""
import json
from pathlib import Path
import tempfile
import unittest

from build_checkpoint import PHASES, select_checkpoint


class CheckpointTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=Path(__file__).parent)
        self.addCleanup(self.temporary.cleanup)
        self.storage = Path(self.temporary.name)

    def select(self, run="100", **kwargs):
        return select_checkpoint(self.storage, "XPS-9730", run,
                                 kwargs.pop("signature", "same-inputs"), "commit", **kwargs)

    def world_checkpoint(self, build, legacy=False):
        (build / "stage4/bin").mkdir(parents=True)
        (build / "stage4/bin/bash").touch()
        (build / "stage4/config.yml").write_text("hostname: XPS-9730\n")
        (build / "stage4/kernel-test.tgz").touch()
        # A completed package and its database entry must survive selection.
        (build / "stage4/var/db/pkg/app-misc/mime-types").mkdir(parents=True)
        (build / "stage3.ready").touch()
        (build / "world.started").touch()
        if not legacy:
            for phase in PHASES:
                (build / f"{phase}.done").touch()
        database = build / "var-cache/edb/mtimedb"
        database.parent.mkdir(parents=True)
        database.write_text(json.dumps({"resume": {"mergelist": [["ebuild", "/", "dev-vcs/git-1", "merge"]]}}))
        return database

    def test_new_run_reuses_completed_packages_and_saved_queue(self):
        first = self.select()
        database = self.world_checkpoint(first)
        before = database.read_bytes()
        resumed = self.select("200")
        self.assertEqual(first, resumed)
        self.assertEqual(database.read_bytes(), before)
        self.assertTrue((resumed / "stage4/var/db/pkg/app-misc/mime-types").is_dir())
        self.assertTrue(all((resumed / f"{p}.done").exists() for p in PHASES))
        self.assertFalse((self.storage / "XPS-9730/200").exists())

    def test_interruption_before_world_preserves_completed_stage(self):
        first = self.select()
        (first / "bootstrap.done").touch()
        resumed = self.select("200")
        self.assertEqual(first, resumed)
        self.assertTrue((resumed / "bootstrap.done").exists())
        self.assertFalse((resumed / "kernel.done").exists())

    def test_missing_or_corrupt_queue_never_starts_another_world(self):
        first = self.select()
        database = self.world_checkpoint(first)
        for contents in (None, "{broken", "{}", '{"resume": {"mergelist": []}}'):
            with self.subTest(contents=contents):
                if contents is None:
                    database.unlink()
                else:
                    database.write_text(contents)
                with self.assertRaisesRegex(ValueError, "refusing to restart @world"):
                    self.select("200")
                self.assertFalse((self.storage / "XPS-9730/200").exists())
                self.assertTrue((first / "stage4/bin/bash").exists())

    def test_input_changes_require_explicit_fresh_build_and_keep_old_state(self):
        first = self.select()
        database = self.world_checkpoint(first)
        with self.assertRaisesRegex(ValueError, "inputs changed"):
            self.select("200", signature="changed")
        fresh = self.select("200", signature="changed", fresh=True)
        self.assertNotEqual(first, fresh)
        self.assertTrue(database.exists())
        self.assertEqual(self.select("300", signature="changed"), fresh)

    def test_publication_releases_checkpoint_for_next_fresh_image(self):
        first = self.select()
        self.world_checkpoint(first)
        (first / "world.done").touch()
        self.assertEqual(self.select("200"), first)
        (first / "published.done").touch()
        self.assertNotEqual(self.select("300"), first)
        self.assertTrue((first / "world.done").exists())

    def test_adopt_running_legacy_build_and_resume_on_new_run(self):
        legacy = self.storage / "42"
        legacy.mkdir()
        database = self.world_checkpoint(legacy, legacy=True)
        before = database.read_bytes()
        adopted = self.select("42", adopt=legacy)
        self.assertEqual(adopted, legacy.resolve())
        self.assertTrue(all((adopted / f"{p}.done").exists() for p in PHASES))
        self.assertEqual(self.select("200"), adopted)
        self.assertEqual(database.read_bytes(), before)

    def test_missing_filesystem_or_stage_markers_does_not_overwrite_checkpoint(self):
        first = self.select()
        database = self.world_checkpoint(first)
        (first / "kernel.done").unlink()
        with self.assertRaisesRegex(ValueError, "stage markers"):
            self.select("200")
        (first / "kernel.done").touch()
        (first / "stage4/bin/bash").unlink()
        with self.assertRaisesRegex(ValueError, "filesystem is missing"):
            self.select("200")
        self.assertTrue(database.exists())
