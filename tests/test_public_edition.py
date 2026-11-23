import hashlib
from pathlib import Path
import tempfile
import unittest

from public_edition import EXTRAS, audit, binhost, configure


class PublicEditionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=Path(__file__).parent)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_configuration_isolated_idempotent_and_preserves_other_world_packages(self):
        with self.assertRaises(ValueError):
            configure(Path("/"))
        with self.assertRaises(ValueError):
            configure(self.root)
        (self.root / "config.yml").write_text("hostname: XPS-9730\n")
        (self.root / "var/lib/portage").mkdir(parents=True)
        (self.root / "etc/portage/package.license").mkdir(parents=True)
        world = self.root / "var/lib/portage/world"
        world.write_text("\n".join(["www-client/firefox", *EXTRAS, "sys-kernel/linux-firmware"]) + "\n")
        config = self.root / "etc/portage/make.conf"
        config.write_text('USE="X cuda"\n')
        configure(self.root)
        first = config.read_text()
        configure(self.root)
        self.assertEqual(config.read_text(), first)
        self.assertEqual(world.read_text(), "www-client/firefox\nsys-kernel/linux-firmware\n")
        self.assertEqual((self.root / "etc/portage/package.mask/stage4-public").read_text().splitlines(), list(EXTRAS))

    @staticmethod
    def missing(cpv, metadata):
        return [] if metadata["LICENSE"] == "MIT" else [metadata["LICENSE"]]

    def package(self, cpv, license="MIT", restrict=""):
        folder = self.root / "var/db/pkg" / cpv
        folder.mkdir(parents=True)
        for key, value in {"LICENSE": license, "RESTRICT": restrict, "SLOT": "0", "USE": ""}.items():
            (folder / key).write_text(value)

    def test_image_audit_rejects_restricted_unknown_and_missing_metadata(self):
        self.package("app-misc/jq-1.8.2")
        self.package("virtual/zlib-1", license="")
        self.assertEqual(len(audit(self.root, self.missing)), 2)
        self.package("example/restricted-1", restrict="bindist")
        self.package("example/proprietary-1", license="unknown")
        self.package("example/no-license-1", license="")
        self.package("net-im/slack-1")  # Excluded even if metadata claims a free license.
        with self.assertRaises(ValueError) as error:
            audit(self.root, self.missing)
        for reason in ("RESTRICT=bindist", "unaccepted licenses", "missing license", "optional proprietary"):
            self.assertIn(reason, str(error.exception))

    def test_binhost_checks_content_and_filters_index_and_package_files(self):
        source, dest = self.root / "source", self.root / "public"
        source.mkdir()
        blocks = []
        for cpv, license, restrict in [("app-misc/jq-1", "MIT", ""), ("net-im/slack-1", "bad", "bindist")]:
            path = f"{cpv}.gpkg.tar"
            file = source / path
            file.parent.mkdir(exist_ok=True)
            file.write_bytes(cpv.encode())
            blocks.append(f"CPV: {cpv}\nPATH: {path}\nLICENSE: {license}\nRESTRICT: {restrict}\nSIZE: {file.stat().st_size}\nMD5: {hashlib.md5(file.read_bytes()).hexdigest()}")
        index = source / "Packages"
        index.write_text("VERSION: 0\nPACKAGES: 2\nURI: https://personal.invalid/\n\n" + "\n\n".join(blocks) + "\n")
        result = binhost(source, dest, self.missing)
        self.assertEqual(result["published"], 1)
        self.assertEqual(len(result["excluded"]), 1)
        self.assertIn("PACKAGES: 1", (dest / "Packages").read_text())
        self.assertNotIn("slack", (dest / "Packages").read_text())
        self.assertNotIn("URI:", (dest / "Packages").read_text())
        self.assertFalse((dest / "net-im").exists())
        self.assertEqual(binhost(dest, None, self.missing)["published"], 1)
        with self.assertRaisesRegex(ValueError, "Public binhost audit failed"):
            binhost(source, None, self.missing)
        prior = (dest / "Packages").read_bytes()
        (source / "app-misc/jq-1.gpkg.tar").write_bytes(b"corrupt")
        with self.assertRaises(ValueError):
            binhost(source, dest, self.missing)
        self.assertEqual((dest / "Packages").read_bytes(), prior)
        index.write_text(index.read_text().replace("PATH: app-misc/jq-1.gpkg.tar", "PATH: ../escape"))
        with self.assertRaisesRegex(ValueError, "Unsafe package path"):
            binhost(source, dest, self.missing)

    def test_sourceforge_index_reuses_published_files_and_never_overwrites_changed_bytes(self):
        source, dest = self.root / "cache", self.root / "public"
        file = source / "app-misc/jq/jq-1-1.gpkg.tar"
        file.parent.mkdir(parents=True)
        index = source / "Packages"

        def write_cache(data):
            file.write_bytes(data)
            index.write_text(
                "VERSION: 0\nPACKAGES: 1\nTIMESTAMP: 1\n\n"
                f"CPV: app-misc/jq-1\nPATH: {file.relative_to(source)}\nLICENSE: MIT\n"
                f"SIZE: {len(data)}\nMD5: {hashlib.md5(data).hexdigest()}\n"
            )

        write_cache(b"old")
        previous = self.root / "previous-Packages"
        previous.write_bytes(index.read_bytes())
        binhost(source, dest, self.missing, previous)
        self.assertIn(f"PATH: {file.relative_to(source)}\n", (dest / "Packages").read_text())
        self.assertEqual((dest / "upload-files.txt").read_text(), "")

        write_cache(b"new")
        binhost(source, dest, self.missing, previous)
        path = (dest / "upload-files.txt").read_text().strip()
        self.assertEqual(path, f"objects/{hashlib.sha256(b'new').hexdigest()}/{file.name}")
        self.assertIn(f"PATH: {path}\n", (dest / "Packages").read_text())
        self.assertEqual((dest / path).read_bytes(), b"new")
        self.assertFalse((dest / file.relative_to(source)).exists())
