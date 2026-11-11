"""Build the publish archive, then test its public API outside the checkout."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path


def main() -> None:
    repository = Path(__file__).resolve().parents[1]
    moon = os.environ.get("MBMOT_MOON", "moon")

    def run(*arguments: str, cwd: Path = repository) -> None:
        print(f"{cwd}: moon {' '.join(arguments)}", flush=True)
        subprocess.run([moon, *arguments], cwd=cwd, check=True)

    manifest = (repository / "moon.mod").read_text(encoding="utf-8")
    version_match = re.search(r'^version\s*=\s*"([^"]+)"', manifest, re.MULTILINE)
    assert version_match is not None, "moon.mod must declare a version"
    version = version_match.group(1)
    run("package")
    archive = repository / "_build" / "publish" / f"python123-ops-mbmot-{version}.zip"
    with tempfile.TemporaryDirectory(prefix="mbmot-package-") as temporary:
        root = Path(temporary)
        package = root / "package"
        with zipfile.ZipFile(archive) as contents:
            names = contents.namelist()
            assert "moon.mod" in names
            assert any(name.replace("\\", "/") == "src/replay/main.mbt" for name in names)
            contents.extractall(package)
        run("check", "--target", "all", "--deny-warn", cwd=package)
        run("build", "--target", "all", "--deny-warn", cwd=package)
        run("test", "--target", "all", "--deny-warn", cwd=package)
        replay = subprocess.run(
            [moon, "run", "src/replay", "--target", "native"],
            cwd=package,
            input=(package / "examples" / "replay.ndjson").read_text(encoding="utf-8"),
            text=True,
            encoding="utf-8",
            capture_output=True,
            check=True,
        )
        assert replay.stdout == (package / "examples" / "replay.expected.ndjson").read_text(encoding="utf-8")

        consumer = root / "consumer"
        consumer.mkdir()
        for name in ("moon.mod", "moon.pkg", "consumer_test.mbt"):
            shutil.copyfile(repository / "examples" / "consumer" / name, consumer / name)
        consumer_manifest = consumer / "moon.mod"
        consumer_manifest.write_text(
            consumer_manifest.read_text(encoding="utf-8").replace("mbmot@0.3.0", f"mbmot@{version}"),
            encoding="utf-8",
        )
        # Only the extracted archive is a workspace member. The checkout cannot
        # satisfy imports, and the candidate need not already be published.
        run("work", "init", "package", "consumer", cwd=root)
        run("-C", "consumer", "test", "--target", "all", "--deny-warn", cwd=root)
    print(f"Candidate archive {version}: all backends and public API consumer passed", flush=True)


if __name__ == "__main__":
    main()
