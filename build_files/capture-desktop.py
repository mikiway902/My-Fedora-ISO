#!/usr/bin/env python3
"""Read-only host capture: explicit desktop preferences and reviewed extension assets."""

import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


PREFERENCES = {
    "org/gnome/desktop/interface": """
        color-scheme enable-animations show-battery-percentage clock-format
        clock-show-date clock-show-seconds clock-show-weekday gtk-theme icon-theme
        cursor-theme cursor-size font-name document-font-name monospace-font-name
        text-scaling-factor gtk-enable-primary-paste
    """.split(),
    "org/gnome/desktop/input-sources": ["sources", "xkb-options"],
    "org/gnome/desktop/wm/preferences": """
        button-layout focus-mode focus-new-windows auto-raise auto-raise-delay
        action-double-click-titlebar action-middle-click-titlebar
        action-right-click-titlebar resize-with-right-button num-workspaces
    """.split(),
    "org/gnome/mutter": ["dynamic-workspaces", "workspaces-only-on-primary", "edge-tiling"],
    "org/gnome/shell": ["favorite-apps"],
    "org/gnome/shell/extensions/dash-to-dock": """
        dock-fixed intellihide autohide extend-height
        dash-max-icon-size height-fraction multi-monitor show-trash
        show-mounts show-show-apps-button show-running show-favorites
        background-opacity
        running-indicator-style
    """.split(),
    "org/gnome/shell/extensions/just-perfection": """
        panel panel-size panel-in-overview dash dash-icon-size
        activities-button app-menu clock-menu keyboard-layout accessibility-menu
        quick-settings workspace-switcher workspace-switcher-size
        window-demands-attention-focus window-picker-icon
        startup-status animation notification-banner-position
    """.split(),
}
RPM_EXTENSIONS = {
    "dash-to-dock@micxgx.gmail.com",
    "appindicatorsupport@rgcjonas.gmail.com",
    "caffeine@patapon.info",
}
# Exact reviewed paths, not a recursive suffix filter that could admit history.js.
EXTENSIONS = {
    "ResourceBuzzLite@hridoybuzz.dev": """
        extension.js prefs.js prefs.ui LICENSE icons/ram-symbolic.svg
        icons/cpu-symbolic.svg schemas/org.gnome.shell.extensions.resourcebuzz-lite.gschema.xml
    """,
    "add-to-desktop@tommimon.github.com": "extension.js shortcutMaker.js LICENSE",
    "clipboard-indicator@tudmotu.com": """
        compat.js confirmDialog.js constants.js extension.js keyboard.js prefs.js
        registry.js stylesheet.css LICENSE.rst
        schemas/org.gnome.shell.extensions.clipboard-indicator.gschema.xml
    """,
    "just-perfection-desktop@just-perfection": """
        extension.js prefs.js stylesheet.css LICENSE lib/API.js lib/Manager.js
        lib/SupportNotifier.js lib/Prefs/Prefs.js lib/Prefs/PrefsKeys.js
        schemas/org.gnome.shell.extensions.just-perfection.gschema.xml resources.gresource
    """,
    "oneclickbios@sao.studio": "extension.js LICENSE",
    "tailscale-gnome-qs@tailscale-qs.github.io": """
        extension.js mullvad.js tailscale.js icons/tailscale-symbolic.svg
    """,
    "screencast.extra.feature@wissle.me": """
        extension.js prefs.js parts/partquickstop.js parts/partbase.js
        parts/partindicator.js parts/partaudio.js parts/partadjust.js
        prefsParts/partpipeline.js prefsParts/arrayliststore.js prefsParts/partgeneral.js
        schemas/org.gnome.shell.extensions.screencastExtraFeature.gschema.xml
        ui/preferencePipeline.ui ui/preferencePipelineButtons.ui
        ui/preferencePipelineButtons46.ui ui/preferencePipelineConfigureRow.ui
        ui/preferencePipelineConfigureDialog.ui ui/preferenceGeneral.ui
        icons/screenshot-ui-mic-symbolic.svg icons/screenshot-ui-speaker-symbolic.svg
        icons/prefs-pipeline.svg icons/settings-symbolic.svg icons/controls-symbolic.svg
        icons/arrow-circular-top-right-symbolic.svg icons/check-round-outline-symbolic.svg
    """,
    "weatherpanel@attentivecoder": """
        extension.js controller.js prefs.js stylesheet.css LICENSE
        preferences/settingsPage.js preferences/locationsPage.js
        providers/openMeteo.js providers/yrNo.js providers/baseProvider.js
        services/geolocation.js ui/Forecast.js ui/PanelButton.js utils/compat.js
        utils/insights.js utils/http.js utils/format.js utils/units.js
        schemas/org.gnome.shell.extensions.weatherpanel.gschema.xml
        media/status/weather-windy-symbolic.svg media/status/weather-tornado-symbolic.svg
        media/status/weather-severe-alert-symbolic.svg media/status/weather-showers-symbolic.svg
        media/status/weather-freezing-rain-symbolic.svg media/status/weather-fog-symbolic.svg
        media/status/weather-clear-symbolic.svg media/status/weather-snow-symbolic.svg
        media/status/weather-storm-symbolic.svg media/status/daytime-sunrise-symbolic.svg
        media/status/weather-few-clouds-symbolic.svg media/status/weather-overcast-symbolic.svg
        media/status/daytime-sunset-symbolic.svg media/status/weather-clear-night-symbolic.svg
        media/status/weather-showers-scattered-symbolic.svg
        media/status/weather-few-clouds-night-symbolic.svg
    """,
}
JUST_PERFECTION = "just-perfection-desktop@just-perfection"
# Inventoried through GLib's resource API: only preferences UI/CSS and public SVGs.
PUBLIC_RESOURCE = {
    "path": "resources.gresource",
    "sha256": "3f238b591a2bd0accc5f17abcf76de4ac7a339fd25e49a50a7db0cfe869b1f85",
    "inventory": [
        "/org/gnome/Shell/Extensions/justperfection/" + path for path in (
            "css/prefs.css", "imgs/donation.svg", "imgs/qr-bitcoin-cash.svg",
            "imgs/qr-bitcoin.svg", "imgs/qr-bnb.svg", "imgs/qr-cardano.svg",
            "imgs/qr-dogecoin.svg", "imgs/qr-ethereum.svg", "imgs/qr-lbry.svg",
            "imgs/qr-ltc.svg", "imgs/qr-monero.svg", "imgs/qr-shiba-inu.svg",
            "imgs/qr-solana.svg", "imgs/qr-usdc.svg", "imgs/qr-usdt.svg",
            "imgs/qr-xlm.svg", "imgs/qr-xrp.svg", "ui/menu.ui",
            "ui/pages/behavior.ui", "ui/pages/customize.ui",
            "ui/pages/profile.ui", "ui/pages/visibility.ui",
        )
    ],
}
PROFILE = "system_files/etc/dconf/db/local.d/10-desktop-profile"
USER_PROFILE = "system_files/etc/dconf/profile/user"
BUNDLE = "system_files/etc/skel/.local/share/gnome-shell/extensions"
MANIFEST = "docs/desktop-snapshot.json"
OPENCODE = "system_files/etc/skel/.config/opencode"
OPENCODE_DOCUMENTS = (
    "AGENTS.md", "agents/lead.md", "agents/deepseek-coder.md",
    "agents/deepseek-hard.md", "agents/reviewer.md",
    "commands/dev.md", "commands/review.md",
)
PUBLIC_COMMANDS = {
    "git status *", "git diff *", "git log *", "git show *", "ls *", "find *",
    "find *-delete*", "find *-exec*", "*",
    "grep *", "rg *", "pytest *", "python -m pytest *", "python3 -m pytest *",
    "npm test *", "npm run test *", "pnpm test *", "cargo test *", "cargo check *",
    "go test *", "git push *", "git reset --hard *", "sudo *", "rm -rf *",
    "rm -fr *", "rm -r -f *", "rm -f -r *", "rm --recursive --force *",
    "docker system prune *", "docker volume rm *", "kubectl delete *",
    "terraform destroy *",
}


def command(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True,
                          timeout=20).stdout.strip()


def regular_file(path):
    return path.is_file() and not any(p.is_symlink() for p in (path, *path.parents))


def strings(value):
    result = ast.literal_eval(value.removeprefix("@as "))
    if not isinstance(result, list) or not all(isinstance(x, str) for x in result):
        raise ValueError("expected a string array")
    return result


def opencode_files():
    source = Path.home() / ".config/opencode"
    path = source / "opencode.jsonc"
    if not path.exists():
        return {}
    if not regular_file(path):
        raise ValueError("OpenCode config must be a regular file")
    original = json.loads(path.read_text())
    config = {"$schema": "https://opencode.ai/config.json"}
    if original.get("default_agent") in {"lead", "build", "plan"}:
        config["default_agent"] = original["default_agent"]
    config["plugins"] = [p for p in original.get("plugins", [])
                         if p == "@dietrichgebert/ponytail"]
    for key in ("permissions", "policies"):
        config[key] = []
        for rule in original.get(key, []):
            if not isinstance(rule, dict) or set(rule) != {"action", "resource", "effect"}:
                continue
            if rule["effect"] not in {"allow", "deny", "ask"}:
                continue
            action, resource = rule["action"], rule["resource"]
            valid = (action == "shell" and resource in PUBLIC_COMMANDS)
            valid |= (action == "tool.use" and resource in {f"shell:{c}" for c in PUBLIC_COMMANDS})
            valid |= (action == "external_directory" and resource == "*" and rule["effect"] != "allow")
            if valid:
                effect = "deny" if key == "policies" and rule["effect"] == "ask" else rule["effect"]
                config[key].append({**rule, "effect": effect})
    servers = original.get("mcp", {})
    servers = servers.get("servers", servers)
    config["mcp"] = {"servers": {}}
    for name in ("rea", "context7"):
        if name not in servers:
            continue
        server = servers[name]
        if not isinstance(server, dict):
            raise ValueError(f"invalid public MCP: {name}")
        allowed = {"type", "enabled", "command"} if name == "rea" else {"type", "enabled", "url"}
        if set(server) - allowed or type(server.get("enabled", True)) is not bool:
            raise ValueError(f"unexpected or credential-bearing MCP fields: {name}")
        if name == "rea":
            args = server.get("command")
            if (server.get("type") != "local" or not isinstance(args, list) or len(args) != 4
                    or args[:2] != ["npx", "-y"] or args[3] != "mcp"
                    or not isinstance(args[2], str)
                    or not re.fullmatch(r"rea-agents@\d+\.\d+\.\d+", args[2])):
                raise ValueError("REA command is not a pinned public npx package")
        elif (server.get("type") != "remote"
              or server.get("url") != "https://mcp.context7.com/mcp"):
            raise ValueError("Context7 URL is not the public credential-free endpoint")
        config["mcp"]["servers"][name] = server
    files = {f"{OPENCODE}/opencode.json":
             (json.dumps(config, indent=2, sort_keys=True) + "\n").encode()}
    cli_path = source / "cli.json"
    if regular_file(cli_path):
        original_cli = json.loads(cli_path.read_text())
        cli = {"$schema": "https://opencode.ai/v2/cli.json"}
        if type(original_cli.get("animations")) is bool:
            cli["animations"] = original_cli["animations"]
        for group, keys in {
            "session": {"scrollbar": (True, False), "thinking": ("show", "hide"),
                        "permissions": ("prompt",)},
            "attention": {"notifications": (True, False)},
        }.items():
            values = {}
            for key, choices in keys.items():
                value = original_cli.get(group, {}).get(key)
                if any(type(value) is type(choice) and value == choice for choice in choices):
                    values[key] = value
            if values:
                cli[group] = values
        files[f"{OPENCODE}/cli.json"] = (json.dumps(cli, indent=2, sort_keys=True) + "\n").encode()
    for relative in OPENCODE_DOCUMENTS:
        path = source / relative
        if not regular_file(path):
            raise ValueError(f"missing regular OpenCode document: {relative}")
        text = path.read_text()
        if re.search(
            r"(?i)(\{(?:env|file):|/home/|/run/user/|https?://[^/\s]+:[^/\s]+@|"
            r"(?:api[_-]?key|password|secret|access[_-]?token)\s*[:=]\s*[\"']?[\w-]{8,})",
            text,
        ):
            raise ValueError(f"nonportable or secret-like OpenCode document: {relative}")
        files[f"{OPENCODE}/{relative}"] = text.encode()
    return files


def capture(root):
    major = re.search(r"GNOME Shell (\d+)", command("gnome-shell", "--version"))
    if not major:
        raise ValueError("cannot determine GNOME Shell version")
    major = major[1]
    files = opencode_files()
    included = {}
    excluded = {}
    source = Path.home() / ".local/share/gnome-shell/extensions"
    for uuid, paths in sorted(EXTENSIONS.items()):
        directory = source / uuid
        metadata_path = directory / "metadata.json"
        if not regular_file(metadata_path):
            excluded[uuid] = "not installed as regular files"
            continue
        metadata = json.loads(metadata_path.read_text())
        if metadata.get("uuid") != uuid:
            raise ValueError(f"metadata UUID mismatch: {uuid}")
        versions = metadata.get("shell-version", [])
        if major not in versions:
            excluded[uuid] = f"does not declare GNOME {major} support"
            continue
        if not regular_file(directory / "extension.js"):
            excluded[uuid] = "missing regular extension.js"
            continue
        public_metadata = {k: v for k, v in metadata.items() if k in {
            "uuid", "name", "description", "shell-version", "url", "version",
            "version-name", "settings-schema", "gettext-domain"
        }}
        prefix = f"{BUNDLE}/{uuid}"
        files[f"{prefix}/metadata.json"] = (
            json.dumps(public_metadata, indent=2, sort_keys=True) + "\n").encode()
        for relative in sorted(paths.split()):
            path = directory / relative
            if uuid == JUST_PERFECTION and relative == PUBLIC_RESOURCE["path"]:
                if (not regular_file(path)
                        or hashlib.sha256(path.read_bytes()).hexdigest() != PUBLIC_RESOURCE["sha256"]):
                    raise ValueError("Just Perfection resource missing or changed; review its inventory before updating the pinned SHA256")
            if regular_file(path):
                files[f"{prefix}/{relative}"] = path.read_bytes()
        included[uuid] = {
            "version": metadata.get("version"), "url": metadata.get("url"),
            "shell-version": versions,
        }

    enabled_on_host = strings(command("gsettings", "get", "org.gnome.shell", "enabled-extensions"))
    enabled = sorted(set(enabled_on_host) & (set(included) | RPM_EXTENSIONS))
    sections = {}
    for section, keys in sorted(PREFERENCES.items()):
        values = {}
        schema = section.replace("/", ".")
        available = set()
        if "/extensions/" not in section:
            available = set(command("gsettings", "list-keys", schema).splitlines())
        for key in sorted(keys):
            value = command("dconf", "read", f"/{section}/{key}")
            if not value and key in available:
                value = command("gsettings", "get", schema, key)
            if not value:
                continue
            if "\n" in value or "\r" in value:
                raise ValueError(f"multiline preference rejected: {section}/{key}")
            if "/extensions/" in section:
                if not re.fullmatch(r"(true|false|-?\d+|(?:\d+\.\d+))", value):
                    raise ValueError(f"non-numeric extension preference: {key}")
            values[key] = value
        if values:
            sections[section] = values
    sections.setdefault("org/gnome/shell", {})["enabled-extensions"] = repr(enabled)
    text = "# Generated by build_files/capture-desktop.py; explicit allowlist only.\n"
    for section, values in sorted(sections.items()):
        text += f"\n[{section}]\n"
        text += "".join(f"{k}={v}\n" for k, v in sorted(values.items()))
    files[PROFILE] = text.encode()
    files[USER_PROFILE] = b"user-db:user\nsystem-db:local\n"
    manifest = {
        "format": 1, "gnome-shell-major": major, "extensions": included,
        "excluded-extensions": excluded, "enabled-extensions": enabled,
        "rpm-provided-extensions": sorted(RPM_EXTENSIONS),
        "preference-allowlist": PREFERENCES,
        "public-resource-exceptions": {JUST_PERFECTION: PUBLIC_RESOURCE} if JUST_PERFECTION in included else {},
        "exclusions": [
            "No home/dconf dump, environment, SSH keys, tokens, cookies or application settings.",
            "No MRU sources, weather locations, IPs, devices, clipboard history or extension state.",
            "Only exact reviewed source paths; no symlinks, caches, arbitrary JSON, compiled schemas or translations.",
            "ResourceBuzzLite excluded on GNOME 51; global version validation is never disabled.",
            "Only Just Perfection's SHA256-pinned, inventoried public preferences resource is allowed as a compiled resource.",
            "OpenCode skills, provider configuration, credentials, service state, backups and history are not copied.",
            "OpenCode preserves permission allow/deny/ask; malformed policy ask effects become deny.",
        ],
        "files": {p: hashlib.sha256(data).hexdigest() for p, data in sorted(files.items())},
    }
    files[MANIFEST] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()

    # Only previously generated, unchanged files may be replaced or removed.
    previous = {}
    old_manifest = root / MANIFEST
    if old_manifest.exists():
        if not regular_file(old_manifest):
            raise ValueError("refusing symlink manifest")
        previous = json.loads(old_manifest.read_text())["files"]
    allowed = {PROFILE, USER_PROFILE, f"{OPENCODE}/opencode.json", f"{OPENCODE}/cli.json"}
    allowed.update(f"{OPENCODE}/{p}" for p in OPENCODE_DOCUMENTS)
    for relative in set(previous) | set(files):
        if Path(relative).is_absolute() or ".." in Path(relative).parts:
            raise ValueError("unsafe generated path")
        if relative != MANIFEST and relative not in allowed and not relative.startswith(BUNDLE + "/"):
            raise ValueError("unexpected generated path")
        path = root / relative
        if any(p.is_symlink() for p in (path, *path.parents)):
            raise ValueError("refusing symlink output path")
        if path.exists() and relative != MANIFEST:
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if previous.get(relative) != digest:
                legacy = (relative == f"{OPENCODE}/opencode.json" and not previous
                          and json.loads(path.read_text()) == {
                              "$schema": "https://opencode.ai/config.json", "permission": "allow"})
                if not legacy:
                    raise ValueError(f"refusing to overwrite unowned or changed file: {relative}")
    bundle = root / BUNDLE
    if bundle.exists():
        for path in bundle.rglob("*"):
            if path.is_symlink() or (path.is_file() and str(path.relative_to(root)) not in previous):
                raise ValueError("refusing unowned extension output")
    for relative in sorted(set(previous) - set(files)):
        path = root / relative
        if path.exists():
            path.unlink()
    for relative, data in sorted(files.items()):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        path.chmod(0o644)
    print(f"Captured {len(included)} extensions, {len(enabled)} enabled, {len(files)} files.")
    for uuid, reason in excluded.items():
        print(f"Excluded {uuid}: {reason}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path,
                        default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        capture(args.output_root.absolute())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(f"Capture failed: {error}")


if __name__ == "__main__":
    main()
