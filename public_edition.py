#!/usr/bin/env python3
"""Configure and audit a public stage4 copy; filter its binary package mirror."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil


EXTRAS = ("net-im/slack", "media-sound/spotify", "dev-util/nvidia-cuda-toolkit")


def configure(root):
    root = root.resolve(strict=True)
    if root == Path("/") or not (root / "config.yml").is_file():
        raise ValueError("Supply a separate stage4 working copy, not the host root")
    world = root / "var/lib/portage/world"
    world.write_text("\n".join(a for a in world.read_text().splitlines() if a not in EXTRAS) + "\n")
    config = root / "etc/portage"
    (config / "package.mask").mkdir(exist_ok=True)
    (config / "package.mask/stage4-public").write_text("\n".join(EXTRAS) + "\n")
    policy = ('\n# Public edition: optional proprietary apps are installed separately.\n'
              'USE="${USE} -cuda -cuda-clang -nvenc"\n'
              'ACCEPT_LICENSE="-* @FREE"\n'
              'ACCEPT_RESTRICT="* -bindist"\n')
    make_conf = config / "make.conf"
    if policy not in make_conf.read_text():
        with make_conf.open("a") as stream:
            stream.write(policy)
    for name in ("slack", "spotify", "nvidia"):
        (config / "package.license" / name).unlink(missing_ok=True)
    (root / "etc/stage4-public").touch()


def license_check():
    # Evaluate Gentoo's license expressions without personal package.license overrides.
    import portage
    from portage.package.ebuild._config.LicenseManager import LicenseManager
    managers = []
    for exceptions in ("", " linux-fw-redistributable no-source-code"):
        manager = LicenseManager(portage.settings._locations_manager, user_config=False)
        manager.set_accept_license_str("-* @FREE" + exceptions)
        managers.append(manager)

    def missing(cpv, metadata):
        firmware = cpv.startswith("sys-kernel/linux-firmware-")
        return managers[firmware].getMissingLicenses(
            cpv, metadata.get("USE", ""), metadata["LICENSE"],
            metadata.get("SLOT", "0"), metadata.get("repository", metadata.get("REPO", "gentoo")))
    return missing


def rejection(cpv, metadata, missing):
    license = metadata.get("LICENSE", "").strip()
    # Gentoo intentionally leaves LICENSE empty for account/virtual metapackages.
    if not license and cpv.split("/", 1)[0] not in ("acct-user", "acct-group", "virtual"):
        return "missing license metadata"
    if any(cpv.startswith(atom + "-") for atom in EXTRAS):
        return "optional proprietary application"
    if "bindist" in metadata.get("RESTRICT", "").split():
        return "RESTRICT=bindist"
    if not license:
        return None
    licenses = missing(cpv, metadata)
    return "unaccepted licenses: " + " ".join(licenses) if licenses else None


def audit(root, missing):
    packages, failures = [], []
    for package in sorted((root / "var/db/pkg").glob("*/*")):
        if not package.is_dir():
            continue
        metadata = {p.name: p.read_text().strip() for p in package.iterdir()
                    if p.name in ("LICENSE", "RESTRICT", "USE", "SLOT", "repository")}
        cpv = str(package.relative_to(root / "var/db/pkg"))
        reason = rejection(cpv, metadata, missing)
        if reason:
            failures.append(f"{cpv}: {reason}")
        packages.append({"CPV": cpv, **metadata})
    if not packages:
        raise ValueError("No installed package metadata found")
    if failures:
        raise ValueError("Public image audit failed:\n" + "\n".join(failures))
    return packages


def binhost(source, destination, missing):
    blocks = (source / "Packages").read_text().strip().split("\n\n")
    accepted, excluded = [], []
    if destination is not None:
        destination.mkdir(parents=True, exist_ok=True)
    files = []
    for block in blocks[1:]:
        metadata = dict(line.split(": ", 1) for line in block.splitlines() if ": " in line)
        cpv = metadata["CPV"]
        reason = rejection(cpv, metadata, missing)
        path = PurePosixPath(metadata["PATH"])
        if path.is_absolute() or ".." in path.parts or str(path) == ".":
            raise ValueError(f"Unsafe package path: {path}")
        if reason:
            if destination is None:
                raise ValueError(f"Public binhost audit failed: {cpv}: {reason}")
            excluded.append({"CPV": cpv, "reason": reason})
            continue
        original = source / str(path)
        with original.open("rb") as stream:
            digest = hashlib.file_digest(stream, "md5").hexdigest()
        if original.stat().st_size != int(metadata["SIZE"]) or digest != metadata["MD5"]:
            raise ValueError(f"Package checksum mismatch: {path}")
        files.append(str(path))
        if destination is None:
            accepted.append(block)
            continue
        target = destination / str(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        # Staging uses its own copy; personal cache maintenance cannot mutate a release.
        if not target.exists():
            partial = target.with_name(target.name + ".new")
            shutil.copy2(original, partial)
            partial.replace(target)
        else:
            with target.open("rb") as stream:
                staged_digest = hashlib.file_digest(stream, "md5").hexdigest()
            if target.stat().st_size != original.stat().st_size or staged_digest != metadata["MD5"]:
                raise ValueError(f"Existing staged package differs: {path}")
        accepted.append(block)
    if not accepted:
        raise ValueError("Refusing to publish an empty package index")
    if destination is None:
        return {"published": len(accepted), "files": files}
    header = []
    for line in blocks[0].splitlines():
        if line.startswith("PACKAGES:"):
            line = f"PACKAGES: {len(accepted)}"
        if not line.startswith(("URI:", "ACCEPT_LICENSE:", "ACCEPT_RESTRICT:")):
            header.append(line)
    temporary = destination / "Packages.new"
    temporary.write_text("\n\n".join(["\n".join(header), *accepted]) + "\n\n")
    temporary.replace(destination / "Packages")
    (destination / "excluded-packages.json").write_text(json.dumps(excluded, indent=2) + "\n")
    return {"published": len(accepted), "excluded": excluded}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("configure", "audit", "binhost", "audit-binhost"))
    parser.add_argument("root", type=Path)
    parser.add_argument("destination", type=Path, nargs="?")
    args = parser.parse_args()
    try:
        if args.operation == "configure":
            configure(args.root)
            return
        missing = license_check()
        if args.operation == "audit":
            result = audit(args.root, missing)
        elif args.operation == "audit-binhost":
            result = binhost(args.root, None, missing)
        else:
            if args.destination is None or args.destination.resolve() == args.root.resolve():
                raise ValueError("A separate staging destination is required")
            result = binhost(args.root, args.destination, missing)
        print(json.dumps(result, indent=2))
    except (OSError, ValueError) as exc:
        parser.exit(1, f"{exc}\n")


if __name__ == "__main__":
    main()
