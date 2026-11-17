# Desktop snapshot

Refresh intentionally from the desktop user's session, without sudo:

```sh
bash build_files/tests/test-desktop-snapshot.sh
python3 build_files/capture-desktop.py
```

`--output-root DIRECTORY` writes the same repository-relative paths elsewhere.
Capture reads the current user's `HOME` (not arbitrary XDG paths), GNOME version,
explicitly named dconf keys, and effective GSettings defaults for the core desktop
allowlist. It does not modify the host's settings, installed programs or home.
Output is deterministic for unchanged inputs. Existing generated files must still
match their recorded SHA256 before replacement; unrelated or edited files are
refused. The one initial migration exception is the repository's original
`{"$schema":"https://opencode.ai/config.json","permission":"allow"}` template.

## Installed defaults

- `system_files/etc/dconf/profile/user`: user DB over the local system DB.
- `system_files/etc/dconf/db/local.d/10-desktop-profile`: preferences and filtered
  enabled extensions. No locks: users may override these defaults.
- `system_files/etc/skel/.local/share/gnome-shell/extensions/`: seven compatible
  user extensions from exact reviewed program-file paths.
- `system_files/etc/skel/.config/opencode/`: four agents, two commands, generic
  `AGENTS.md`, reconstructed `opencode.json`, and selected `cli.json` preferences.
- `docs/desktop-snapshot.json`: extension versions, upstream URLs, shell
  compatibility, preference allowlist, exclusions, and output SHA256 inventory.
  No capture timestamp or host username is recorded.

The host snapshot is GNOME 51. ResourceBuzzLite declares support only through
GNOME 50 and is excluded, even though its UUID remains in the host's enabled list.
Missing/unbundled enabled UUIDs are also removed. AppIndicator, Dash to Dock and
Caffeine are supplied by the image's RPM package list rather than copied from
the user's home. Global extension-version validation is never disabled.

## Build integration and limitations

Image/install hooks must run `dconf update` and `glib-compile-schemas` on each
bundled extension's `schemas/` directory. Compiled schema files must be generated
in the installed payload, not committed. New users receive the skel extensions;
existing users' home directories are not migrated.

Just Perfection includes its required `resources.gresource` as the sole compiled
resource exception. Its inventory was enumerated with GLib's resource API (the
host has no `gresource` CLI): 22 public preferences UI/CSS/SVG assets, no user
state. The complete inventory and SHA256 are recorded in the manifest; capture
requires that exact pinned SHA256. Changed or missing resources fail capture
until reviewed, rather than silently producing an incomplete extension. No other
extension or resource filename receives this exception. Translations are omitted.
No VM/login or graphical preferences check was run.

Extension copies are locally installed public source identified by metadata and
the exact source-path allowlist; their bytes have not been independently matched
to an upstream signed release. Refreshing source still requires code review.

## Privacy boundary

No whole dconf dump or home copy is performed. Input-source MRU, weather locations,
device lists/IPs, tokens, clipboard history, caches, symlinks, compiled schemas,
arbitrary JSON, and application state are excluded. Only core desktop keys and
named boolean/numeric Dash to Dock/Just Perfection keys are read.

OpenCode never imports provider configuration, API keys, environment/file
substitution, service registration, databases, history, backups or skills.
Only the public Ponytail package name is retained; local plugin paths/options
are dropped. REA must be a pinned `npx -y rea-agents@X.Y.Z mcp` command and Context7
must use exactly `https://mcp.context7.com/mcp`; extra server fields (including
headers/environment/credentials) cause capture to fail. The six known Markdown
files plus generic instructions are read individually and checked for
nonportable paths and common credential assignments, not recursively copied.

Recognized public-command permission rules preserve native `allow`/`deny`/`ask`
effects. Policies have only `allow`/`deny`: malformed policy `ask` effects become
`deny`, retaining safety guards without blocking ordinary permission prompts.
CLI permission mode is only
copied when set to `prompt`. Provider authentication and any private/custom
provider setup must be configured separately by each new user. Agent model names
are preserved, but provider configuration is not.

## Test evidence

The initial test run failed because `build_files/capture-desktop.py` did not yet
exist. After implementation, `bash build_files/tests/test-desktop-snapshot.sh` passed with
fake HOME and mocked dconf/GSettings/GNOME commands:

- Private environment/SSH/provider/service/password sentinel never appears.
- Arbitrary JSON, clipboard DB, cache code, unreviewed `history.js` and symlinks
  are not copied.
- Incompatible and missing extensions are not enabled.
- A core GSettings default is captured when no dconf override exists.
- Credential-bearing known MCP definitions fail before writing output.
- Repeated captures have identical file hashes.
- An unowned output extension file blocks recapture without being overwritten.
- Native permission `ask` is preserved; malformed policy `ask` becomes `deny`.
- Only Just Perfection's pinned public preferences resource is copied; modified
  resources fail before writing and arbitrary compiled resources remain excluded.

Also checked: shell syntax, Python compilation, generated dconf compilation,
generated extension schema compilation, snapshot hashes, and `git diff --check`.
Coverage percentage and end-to-end fresh-user/login behavior were not measured.
