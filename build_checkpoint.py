#!/usr/bin/env python3
"""Select an unfinished target build on shared storage, regardless of run ID."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


PHASES = ("bootstrap", "kernel", "quirks")


def check_world_resume(build):
    if not (build / "world.started").exists() or (build / "world.done").exists():
        return
    try:
        saved = json.loads((build / "var-cache/edb/mtimedb").read_text())
        pending = saved.get("resume", {}).get("mergelist")
    except (OSError, ValueError, AttributeError) as exc:
        raise ValueError(f"Unreadable Portage checkpoint in {build}; refusing to restart @world") from exc
    if not isinstance(pending, list) or not pending:
        raise ValueError(f"No pending Portage resume list in {build}; refusing to restart @world")


def select_checkpoint(storage, target, run_id, signature, revision, fresh=False, adopt=None):
    if not re.fullmatch(r"[A-Za-z0-9_-]+", target) or not re.fullmatch(r"[0-9]+", run_id):
        raise ValueError("Invalid target or run ID")
    storage = storage.resolve()
    control = storage / ".checkpoints" / target
    control.mkdir(parents=True, exist_ok=True)
    active = control / "active"
    previous = None
    if not fresh and (active.exists() or active.is_symlink()):
        previous = active.resolve(strict=True)
    if adopt is not None:
        build = adopt.resolve(strict=True)
        if previous is not None and previous != build:
            raise ValueError(f"An active checkpoint already exists at {previous}")
        if not (build / "stage3.ready").exists() or not (build / "world.started").exists():
            raise ValueError("Only a legacy build that reached @world can be adopted")
        config = (build / "stage4/config.yml").read_text()
        if not re.search(rf"^hostname:\s*{re.escape(target)}\s*$", config, re.M):
            raise ValueError("Legacy build target does not match")
    elif previous is not None and not (previous / "published.done").exists():
        build = previous
    else:
        build = storage / target / run_id
    if not build.is_relative_to(storage):
        raise ValueError("Checkpoint must be inside shared build storage")

    metadata_path = build / "checkpoint.json"
    if metadata_path.exists():
        metadata = json.loads(metadata_path.read_text())
        if not isinstance(metadata, dict) or metadata.get("target") != target or metadata.get("inputs") != signature:
            raise ValueError(f"Build inputs changed for {build}; checkpoint preserved. Use an explicit fresh build if intended.")
    else:
        if build.exists() and any(build.iterdir()) and adopt is None:
            raise ValueError(f"Missing checkpoint metadata in {build}; refusing to overwrite saved state")
        build.mkdir(parents=True, exist_ok=True)

    if (build / "stage3.ready").exists() and not (build / "stage4/bin/bash").is_file():
        raise ValueError(f"Checkpoint filesystem is missing in {build}")
    check_world_resume(build)
    if adopt is not None:
        # The legacy workflow entered @world only after these stages succeeded.
        if not any((build / "stage4").glob("kernel-*.tgz")):
            raise ValueError("Legacy kernel archive is missing")
        for phase in PHASES:
            (build / f"{phase}.done").touch()
    if (build / "world.started").exists() and any(not (build / f"{p}.done").exists() for p in PHASES):
        raise ValueError("Incomplete stage markers; refusing to overwrite Portage's saved resume list")

    if not metadata_path.exists():
        temporary = build / "checkpoint.json.new"
        with temporary.open("w") as stream:
            json.dump({"target": target, "inputs": signature, "registered_from_commit": revision, "registered_by_run": run_id}, stream)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(metadata_path)
    if previous != build:
        temporary = control / f"active.new-{run_id}"
        temporary.unlink(missing_ok=True)
        temporary.symlink_to(build)
        temporary.replace(active)
    return build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target")
    parser.add_argument("run_id")
    parser.add_argument("--storage", type=Path, default=Path("/scratch/builds"))
    parser.add_argument("--fresh", action="store_true", help="Start a new build; retain the old checkpoint")
    parser.add_argument("--adopt", type=Path, help="Register a legacy build that already reached @world")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent
    inputs = subprocess.check_output([
        "git", "ls-tree", "-r", "HEAD", "--", "config.yml", "make.conf.j2",
        "files/common", f"files/{args.target}", "packages",
    ], cwd=repo)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    try:
        build = select_checkpoint(args.storage, args.target, args.run_id,
                                  hashlib.sha256(inputs).hexdigest(), revision, args.fresh, args.adopt)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Checkpoint error: {exc}\n")
    print(build)


if __name__ == "__main__":
    main()
