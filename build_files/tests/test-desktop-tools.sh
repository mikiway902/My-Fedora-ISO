#!/bin/bash
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

repo = Path(sys.argv[1])
helper = (repo / "system_files/usr/libexec/my-fedora-install-tools").read_text()
assert "python3.14 -m venv /usr/share/my-fedora/python-tools" in helper
assert "sha256sum -c -" in helper
assert "--nogpgcheck" not in helper
assert not re.search(r"systemctl\s+(enable|start)", helper)
for forbidden in (".ssh", ".kube", "tailscale up", "authkey", ".env", "sunshine_state"):
    assert forbidden not in helper, forbidden
for line in (repo / "system_files/usr/share/my-fedora/python-requirements.txt").read_text().splitlines():
    assert re.fullmatch(r"[A-Za-z0-9_.-]+==[A-Za-z0-9_.+-]+", line), line
    assert line.split("==")[0].lower() != "omniroute"
for name in ("chatgpt", "tailscale", "google-chrome"):
    config = (repo / f"system_files/etc/yum.repos.d/{name}.repo").read_text()
    assert "gpgcheck=1" in config
    assert "baseurl=https://" in config
print("desktop tools: OK")
PY
