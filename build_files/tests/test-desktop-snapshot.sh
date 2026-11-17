#!/usr/bin/env bash
set -euo pipefail
export TMPDIR="${TMPDIR:-/tmp/opencode}"
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
python3 - "$repo" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

script = Path(sys.argv[1]) / "build_files/capture-desktop.py"
with tempfile.TemporaryDirectory(prefix="desktop-snapshot-") as temp:
    root = Path(temp)
    home = root / "home"
    extensions = home / ".local/share/gnome-shell/extensions"
    good = "clipboard-indicator@tudmotu.com"
    bad = "ResourceBuzzLite@hridoybuzz.dev"
    just = "just-perfection-desktop@just-perfection"
    for uuid, versions in ((good, ["51"]), (bad, ["50"]), (just, ["51"])):
        directory = extensions / uuid
        directory.mkdir(parents=True)
        (directory / "metadata.json").write_text(json.dumps({
            "uuid": uuid, "shell-version": versions, "url": "https://example.org/source"
        }))
        (directory / "extension.js").write_text("// public extension code\n")
    resource_fixture = Path(sys.argv[1]) / (
        "system_files/etc/skel/.local/share/gnome-shell/extensions/"
        + just + "/resources.gresource")
    assert resource_fixture.is_file(), "Just Perfection must include its reviewed preferences resource"
    resource_bytes = resource_fixture.read_bytes()
    (extensions / just / "resources.gresource").write_bytes(resource_bytes)
    (extensions / good / "resources.gresource").write_bytes(b"PRIVATE_SENTINEL")
    (extensions / just / "private.gresource").write_bytes(b"PRIVATE_SENTINEL")
    for name in (".env", "token.json", "cookies", "clipboard.db", "history.js"):
        (extensions / good / name).write_text("PRIVATE_SENTINEL")
    (extensions / good / "linked.js").symlink_to(home / ".ssh/id_ed25519")
    (extensions / good / "cache").mkdir()
    (extensions / good / "cache/secret.js").write_text("PRIVATE_SENTINEL")
    (home / ".ssh").mkdir()
    (home / ".ssh/id_ed25519").write_text("PRIVATE_SENTINEL")
    config = home / ".config/opencode"
    config.mkdir(parents=True)
    (config / "opencode.jsonc").write_text(json.dumps({
        "default_agent": "lead",
        "providers": {"private": {"apiKey": "PRIVATE_SENTINEL"}},
        "plugins": ["@dietrichgebert/ponytail", "/home/private/plugin.js"],
        "permissions": [
            {"action": "shell", "resource": "git status *", "effect": "allow"},
            {"action": "shell", "resource": "*", "effect": "ask"},
        ],
        "policies": [
            {"action": "tool.use", "resource": "shell:sudo *", "effect": "deny"},
            {"action": "tool.use", "resource": "shell:git push *", "effect": "ask"},
        ],
        "mcp": {
            "rea": {"type": "local", "command": ["npx", "-y", "rea-agents@6.8.0", "mcp"], "enabled": True},
            "context7": {"type": "remote", "url": "https://mcp.context7.com/mcp", "enabled": True},
            "private": {"password": "PRIVATE_SENTINEL"},
        },
    }))
    (config / "cli.json").write_text(json.dumps({
        "animations": True, "session": {"thinking": "hide", "password": "PRIVATE_SENTINEL"},
        "attention": {"notifications": True, "sounds": {"done": "/private/file.wav"}},
        "service": {"password": "PRIVATE_SENTINEL"},
    }))
    (config / "service.json").write_text('{"password":"PRIVATE_SENTINEL"}')
    (config / "AGENTS.md").write_text("# Generic engineering instructions\n")
    for relative in ("agents/lead.md", "agents/deepseek-coder.md", "agents/deepseek-hard.md",
                     "agents/reviewer.md", "commands/dev.md", "commands/review.md"):
        path = config / relative
        path.parent.mkdir(exist_ok=True)
        path.write_text("---\ndescription: Generic workflow\n---\nNo credentials.\n")
    bin_dir = root / "bin"
    bin_dir.mkdir()
    stub = """#!/usr/bin/env python3
import os, sys
from pathlib import Path
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(' '.join(sys.argv) + '\\n')
name = Path(sys.argv[0]).name
if name == 'gnome-shell':
    print('GNOME Shell 51.1')
elif name == 'gsettings':
    if sys.argv[1] == 'list-keys':
        print('clock-show-date' if sys.argv[2] == 'org.gnome.desktop.interface' else '')
    elif sys.argv[1:] == ['get', 'org.gnome.desktop.interface', 'clock-show-date']:
        print('true')
    else:
        assert sys.argv[1:] == ['get', 'org.gnome.shell', 'enabled-extensions']
        print("['clipboard-indicator@tudmotu.com', 'ResourceBuzzLite@hridoybuzz.dev', 'missing@example.org', 'dash-to-dock@micxgx.gmail.com']")
elif name == 'dconf':
    assert sys.argv[1] == 'read'
    values = {
        '/org/gnome/desktop/interface/color-scheme': "'prefer-dark'",
        '/org/gnome/desktop/input-sources/sources': "[('xkb', 'us')]",
        '/org/gnome/shell/favorite-apps': "['org.gnome.Nautilus.desktop']",
        '/org/gnome/shell/extensions/dash-to-dock/dock-fixed': 'true',
    }
    print(values.get(sys.argv[2], ''))
"""
    for name in ("gsettings", "dconf", "gnome-shell"):
        path = bin_dir / name
        path.write_text(stub)
        path.chmod(0o755)
    log = root / "calls"
    env = dict(os.environ, HOME=str(home), PATH=f"{bin_dir}:{os.environ['PATH']}",
               CALL_LOG=str(log), PRIVATE_TOKEN="PRIVATE_SENTINEL")
    output = root / "output"
    def capture():
        subprocess.run([sys.executable, str(script), "--output-root", str(output)],
                       env=env, check=True)
        return {str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in output.rglob("*") if p.is_file()}
    first = capture()
    assert first == capture(), "capture must be byte-for-byte deterministic"
    profile = (output / "system_files/etc/dconf/db/local.d/10-desktop-profile").read_text()
    assert "color-scheme='prefer-dark'" in profile
    assert "clock-show-date=true" in profile
    assert "dock-fixed=true" in profile
    assert good in profile and bad not in profile and "missing@example.org" not in profile
    assert "disable-extension-version-validation" not in profile
    bundle = output / "system_files/etc/skel/.local/share/gnome-shell/extensions"
    assert (bundle / good / "extension.js").is_file()
    assert not (bundle / bad).exists()
    assert (bundle / just / "resources.gresource").read_bytes() == resource_bytes
    assert sorted(str(p.relative_to(bundle)) for p in bundle.rglob("*.gresource")) == [
        just + "/resources.gresource"]
    snapshot = json.loads((output / "docs/desktop-snapshot.json").read_text())
    resource_path = str((bundle / just / "resources.gresource").relative_to(output))
    assert snapshot["files"][resource_path] == hashlib.sha256(resource_bytes).hexdigest()
    assert snapshot["public-resource-exceptions"][just]["inventory"]
    portable = json.loads((output / "system_files/etc/skel/.config/opencode/opencode.json").read_text())
    assert portable["default_agent"] == "lead"
    assert portable["plugins"] == ["@dietrichgebert/ponytail"]
    assert "providers" not in portable
    assert portable["permissions"] == [
        {"action": "shell", "resource": "git status *", "effect": "allow"},
        {"action": "shell", "resource": "*", "effect": "ask"},
    ]
    assert portable["policies"] == [
        {"action": "tool.use", "resource": "shell:sudo *", "effect": "deny"},
        {"action": "tool.use", "resource": "shell:git push *", "effect": "deny"},
    ]
    assert set(portable["mcp"]["servers"]) == {"rea", "context7"}
    assert (output / "system_files/etc/skel/.config/opencode/agents/lead.md").exists()
    # Reject a credential-bearing known MCP instead of copying its safe-looking URL.
    original = json.loads((config / "opencode.jsonc").read_text())
    poisoned = json.loads(json.dumps(original))
    poisoned["mcp"]["context7"]["headers"] = {"Authorization": "PRIVATE_SENTINEL"}
    (config / "opencode.jsonc").write_text(json.dumps(poisoned))
    result = subprocess.run([sys.executable, str(script), "--output-root", str(output)],
                            env=env, capture_output=True)
    assert result.returncode != 0
    (config / "opencode.jsonc").write_text(json.dumps(original))
    # An added payload, even under the sole allowed resource filename, needs review.
    (extensions / just / "resources.gresource").write_bytes(resource_bytes + b"PRIVATE_SENTINEL")
    result = subprocess.run([sys.executable, str(script), "--output-root", str(output)],
                            env=env, capture_output=True)
    assert result.returncode != 0
    assert (bundle / just / "resources.gresource").read_bytes() == resource_bytes
    (extensions / just / "resources.gresource").write_bytes(resource_bytes)
    for p in output.rglob("*"):
        assert not p.is_symlink()
        if p.is_file():
            assert b"PRIVATE_SENTINEL" not in p.read_bytes(), p
    calls = log.read_text()
    for forbidden in ("dump", "mru-sources", "/city", "/devices", "/tokens", "disable-extension-version-validation"):
        assert forbidden not in calls, forbidden
    # Refuse to overwrite unrelated files in the generated extension directory.
    (bundle / good / "unowned.js").write_text("// user work")
    result = subprocess.run([sys.executable, str(script), "--output-root", str(output)],
                            env=env, capture_output=True)
    assert result.returncode != 0
    assert (bundle / good / "unowned.js").read_text() == "// user work"
print("PASS: private data, providers/service/password, MCP validation, symlinks/caches, compatibility, allowlist, determinism, overwrite guard")
PY
