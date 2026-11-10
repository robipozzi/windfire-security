"""Every shell script of the repository parses (bash -n), and passes shellcheck at error level when it is installed"""
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_DIR = Path(__file__).resolve().parents[2]
# Virtual environments and other folders that are not the repository's own scripts
SKIP_DIRS = {".git", "node_modules", "windfire-security-server", "windfire-security-test",
             "windfire-security-suite", "__pycache__"}


def shell_scripts():
    return sorted(
        path for path in REPO_DIR.rglob("*.sh")
        if not SKIP_DIRS.intersection(path.relative_to(REPO_DIR).parts)
    )


SCRIPTS = shell_scripts()


def test_scripts_found():
    assert len(SCRIPTS) > 10


@pytest.mark.parametrize("script", SCRIPTS, ids=lambda p: str(p.relative_to(REPO_DIR)))
def test_bash_syntax(script):
    result = subprocess.run(["bash", "-n", str(script)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


@pytest.mark.skipif(shutil.which("shellcheck") is None, reason="shellcheck not installed")
@pytest.mark.parametrize("script", SCRIPTS, ids=lambda p: str(p.relative_to(REPO_DIR)))
def test_shellcheck_errors(script):
    result = subprocess.run(["shellcheck", "--shell=bash", "-S", "error", "-x", str(script)],
                            capture_output=True, text=True, cwd=script.parent)
    assert result.returncode == 0, result.stdout
