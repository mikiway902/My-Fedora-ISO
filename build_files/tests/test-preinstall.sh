#!/bin/bash
# All installation and download commands are stubs; only temporary files change.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" XDG_STATE_HOME="$work/state" TMPDIR="$work/tmp"
export FIXTURES="$work/fixtures" LOG="$work/commands"
mkdir -p "$work/bin" "$work/lists" "$TMPDIR" "$FIXTURES"
export PATH="$work/bin:$PATH"
sed -e "s|/usr/share/my-fedora|$work/lists|g" \
    -e "s|/var/lib/my-fedora|$XDG_STATE_HOME/my-fedora|g" \
    "$REPO/system_files/usr/libexec/my-fedora-preinstall" > "$work/preinstall"
cat > "$work/bin/curl" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'curl %s\n' "$*" >> "$LOG"
while (($#)); do
    case $1 in
        -o) output=$2; shift 2 ;;
        https://*) url=$1; shift ;;
        *) shift ;;
    esac
done
[[ ${FAIL_DOWNLOAD:-} != "${url##*/}" ]] || exit 1
cp "$FIXTURES/${url##*/}" "$output"
STUB
cat > "$work/bin/flatpak" <<'STUB'
#!/bin/bash
set -euo pipefail
printf 'flatpak %s\n' "$*" >> "$LOG"
if [[ ${*: -1} == *.flatpak ]]; then
    [[ $(cat "${*: -1}") != "${FAIL_PAYLOAD:-}" ]] || exit 1
elif [[ $1 == install && ${FAIL_FLATHUB:-0} == 1 ]]; then
    exit 1
fi
STUB
cat > "$work/bin/code" <<'STUB'
#!/bin/bash
printf 'code %s\n' "$*" >> "$LOG"
[[ ${FAIL_CODE:-0} != 1 ]]
STUB
chmod +x "$work/bin/"*
printf 'first\n' > "$FIXTURES/first.flatpak"
printf 'second\n' > "$FIXTURES/second.flatpak"
printf 'org.example.Flathub\n' > "$work/lists/flatpaks"
printf 'example.extension\n' > "$work/lists/vscode-extensions"
first_sha=$(sha256sum "$FIXTURES/first.flatpak" | cut -d ' ' -f 1)
second_sha=$(sha256sum "$FIXTURES/second.flatpak" | cut -d ' ' -f 1)
vendor_list() {
    printf 'org.example.First\t%s\thttps://example.org/first.flatpak\t%s\n' "$1" "$2"
    printf 'org.example.Second\t1.0\thttps://example.org/second.flatpak\t%s\n' "$second_sha"
}
vendor_list 1.0 "$first_sha" > "$work/lists/vendor-flatpaks.tsv"
state="$XDG_STATE_HOME/my-fedora"
run() { bash "$work/preinstall" "$@"; }
fail() { echo "preinstall: $*" >&2; exit 1; }

if FAIL_FLATHUB=1 run flatpaks; then fail "Flathub failure was ignored"; fi
[[ ! -s $state/flatpaks.done ]] || fail "failed Flathub install marked complete"
if FAIL_PAYLOAD=second run flatpaks; then fail "vendor failure was ignored"; fi
grep -Fxq org.example.Flathub "$state/flatpaks.done"
[[ $(wc -l < "$state/vendor-flatpaks.done") == 1 ]] || fail "partial completion lost"
grep -Fq org.example.First "$state/vendor-flatpaks.done"
before=$(grep -c '^curl ' "$LOG")
run flatpaks
[[ $(grep -c '^curl ' "$LOG") == $((before + 1)) ]] || fail "successful vendor was retried"
[[ $(wc -l < "$state/vendor-flatpaks.done") == 2 ]]
before=$(grep -c '^curl ' "$LOG")
run flatpaks
[[ $(grep -c '^curl ' "$LOG") == "$before" ]] || fail "removed apps would be reinstalled"

vendor_list 1.1 "$first_sha" > "$work/lists/vendor-flatpaks.tsv"
run flatpaks
[[ $(grep -c '^curl ' "$LOG") == $((before + 1)) ]] || fail "version change not installed"
printf 'changed\n' > "$FIXTURES/first.flatpak"
if run flatpaks; then :; else fail "unchanged pin should stay skipped"; fi
changed_sha=$(sha256sum "$FIXTURES/first.flatpak" | cut -d ' ' -f 1)
vendor_list 1.1 "$changed_sha" > "$work/lists/vendor-flatpaks.tsv"
run flatpaks
[[ $(grep -c '^curl ' "$LOG") == $((before + 2)) ]] || fail "hash change not installed"

vendor_list 1.2 "$first_sha" > "$work/lists/vendor-flatpaks.tsv"
completed=$(wc -l < "$state/vendor-flatpaks.done")
if run flatpaks; then fail "checksum mismatch accepted"; fi
[[ $(wc -l < "$state/vendor-flatpaks.done") == "$completed" ]]
vendor_list 1.2 "$changed_sha" > "$work/lists/vendor-flatpaks.tsv"
if FAIL_DOWNLOAD=first.flatpak run flatpaks; then fail "download failure ignored"; fi
[[ $(wc -l < "$state/vendor-flatpaks.done") == "$completed" ]]
run flatpaks
[[ $(wc -l < "$state/vendor-flatpaks.done") == $((completed + 1)) ]]
[[ -z $(find "$TMPDIR" -mindepth 1 -print -quit) ]] || fail "temporary bundles leaked"
vendor_list 1.3 invalid > "$work/lists/vendor-flatpaks.tsv"
before=$(grep -c '^curl ' "$LOG")
if run flatpaks; then fail "malformed checksum accepted"; fi
[[ $(grep -c '^curl ' "$LOG") == "$before" ]] || fail "invalid entry downloaded"

if FAIL_CODE=1 run vscode-extensions; then fail "extension failure ignored"; fi
[[ ! -s $state/vscode-extensions.done ]]
run vscode-extensions
run vscode-extensions
[[ $(grep -c '^code ' "$LOG") == 2 ]] || fail "completed extension reinstalled"
if run unknown; then fail "unknown mode accepted"; fi
if run; then fail "missing mode accepted"; fi
if grep -Eq -- '--(no-gpg-verify|reinstall)|gpg-verify=false' "$LOG"; then
    fail "verification disabled or destructive reinstall used"
fi
echo "preinstall: OK"
