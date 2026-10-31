#!/bin/bash
# Verify the official Fedora repositories used by the Classic installer.
#
# Exit codes:
#   0  all configured repositories are reachable and consistent
#   1  configuration error (wrong URL, HTTP 404, invalid metadata, drift)
#   2  transient network failure (DNS, connection, timeout, HTTP 5xx/429)
#
# CI uses the distinction: a pull-request validation may warn and skip on 2,
# but an ISO build must not publish an unverified image.

set -uo pipefail
export LC_ALL=C

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=repo-urls.sh
# shellcheck disable=SC1091
source "$REPO_ROOT/build_files/repo-urls.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

CONFIG_ERROR=0
NETWORK_ERROR=0

config_error() {
    printf 'ERROR: %s\n' "$*" >&2
    CONFIG_ERROR=1
}

network_error() {
    printf 'WARNING: %s\n' "$*" >&2
    NETWORK_ERROR=1
}

# Translate a curl exit code into 0 (ok), 1 (configuration) or 2 (network).
classify_curl() {
    case $1 in
        6|7|28|35|52|56) return 2 ;;
        60|77) return 1 ;;  # TLS/certificate failures are not "temporary"
        *) return 2 ;;
    esac
}

# Fetch a URL into a file.  Sets HTTP_CODE and CURL_RC.
fetch_url() {
    local url=$1 out=$2
    HTTP_CODE=$(curl -sS -L --connect-timeout 10 --max-time 60 \
        --retry 2 --retry-delay 2 -o "$out" -w '%{http_code}' "$url" 2>"$TMP/curl.err")
    CURL_RC=$?
}

# Check a URL that should return a small document.
check_http() {
    local label=$1 url=$2 out=$3 code
    fetch_url "$url" "$out"

    if ((CURL_RC != 0)); then
        classify_curl "$CURL_RC"
        code=$?
        if ((code == 1)); then
            config_error "$label: TLS/certificate failure for $url: $(tr '\n' ' ' < "$TMP/curl.err")"
        else
            network_error "$label: cannot reach $url (curl exit $CURL_RC): $(tr '\n' ' ' < "$TMP/curl.err")"
        fi
        return 1
    fi

    case $HTTP_CODE in
        200) return 0 ;;
        403|404|410)
            config_error "$label: HTTP $HTTP_CODE for $url"
            return 1
            ;;
        429|5??)
            network_error "$label: HTTP $HTTP_CODE for $url"
            return 1
            ;;
        *)
            config_error "$label: unexpected HTTP $HTTP_CODE for $url"
            return 1
            ;;
    esac
}

# Check a metadata artifact with HEAD, falling back to a one-byte range request.
check_artifact() {
    local label=$1 url=$2 expected_size=$3
    local headers="$TMP/${label}.headers" code length

    code=$(curl -sSI -L --connect-timeout 10 --max-time 30 \
        --retry 2 --retry-delay 2 -o "$headers" -w '%{http_code}' "$url" 2>"$TMP/curl.err")
    local rc=$?

    if ((rc == 0)) && [[ $code == 405 ]]; then
        # Some mirrors reject HEAD.  Ask for one byte instead.
        code=$(curl -sS -L -r 0-0 --connect-timeout 10 --max-time 30 \
            -o /dev/null -w '%{http_code}' "$url" 2>"$TMP/curl.err")
        rc=$?
        headers=
    fi

    if ((rc != 0)); then
        classify_curl "$rc"
        local cls=$?
        if ((cls == 1)); then
            config_error "$label: TLS/certificate failure for $url: $(tr '\n' ' ' < "$TMP/curl.err")"
        else
            network_error "$label: cannot reach $url (curl exit $rc): $(tr '\n' ' ' < "$TMP/curl.err")"
        fi
        return 1
    fi

    case $code in
        200|206) ;;
        403|404|410)
            config_error "$label: HTTP $code for $url"
            return 1
            ;;
        429|5??)
            network_error "$label: HTTP $code for $url"
            return 1
            ;;
        *)
            config_error "$label: unexpected HTTP $code for $url"
            return 1
            ;;
    esac

    if [[ -n $headers && -n $expected_size ]]; then
        length=$(awk 'BEGIN { IGNORECASE = 1 } /^content-length:/ { gsub("\r", "", $2); print $2 }' \
            "$headers" | tail -1)
        if [[ -n $length && $length != "$expected_size" ]]; then
            config_error "$label: size mismatch: repomd says $expected_size, server says $length ($url)"
            return 1
        fi
    fi
}

# Read repomd.xml and write "type<TAB>href<TAB>size" for primary/group data.
parse_repomd() {
    local file=$1 out=$2
    python3 - "$file" > "$out" <<'PY'
import sys
import xml.etree.ElementTree as ET

try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception as exc:  # noqa: BLE001 - report any parse failure
    print(f"invalid XML: {exc}", file=sys.stderr)
    sys.exit(1)

NS = "{http://linux.duke.edu/metadata/repo}"


def children(element, name):
    found = element.find(NS + name)
    if found is not None:
        return found
    return next((item for item in element if item.tag.endswith(name)), None)


datas = root.findall(NS + "data")
if not datas:
    datas = [item for item in root.iter() if item.tag.endswith("data")]

for data in datas:
    kind = data.get("type", "")
    location = children(data, "location")
    if location is None or not location.get("href"):
        continue
    size = children(data, "size")
    print(f"{kind}\t{location.get('href')}\t{size.text if size is not None else ''}")
PY
}

check_repomd() {
    local label=$1 base=$2
    local url="${base}repodata/repomd.xml"
    local out="$TMP/${label}-repomd.xml"
    local artifacts="$TMP/${label}-artifacts.txt"
    local kind href size
    local found_primary=0 found_group=0

    if ! check_http "$label repomd.xml" "$url" "$out"; then
        return 1
    fi

    if ! parse_repomd "$out" "$artifacts"; then
        config_error "$label: repomd.xml is not valid XML"
        return 1
    fi

    while IFS=$'\t' read -r kind href size; do
        case $kind in
            primary) found_primary=1 ;;
            group) found_group=1 ;;
            *) continue ;;
        esac
        check_artifact "$label $kind" "${base}${href}" "$size" || true
    done < "$artifacts"

    if (( ! found_primary )); then
        config_error "$label: repomd.xml has no primary metadata"
    fi
    if (( ! found_group )); then
        config_error "$label: repomd.xml has no group (comps) metadata"
    fi
}

check_treeinfo() {
    local url="${FEDORA_RELEASE_URL}.treeinfo"
    local out="$TMP/treeinfo"

    if ! check_http "release .treeinfo" "$url" "$out"; then
        return 1
    fi
    if ! grep -q "^version = ${FEDORA_VERSION}$" "$out"; then
        config_error "release .treeinfo does not declare version ${FEDORA_VERSION}"
    fi
    if ! grep -q "^arch = ${ARCH}$" "$out"; then
        config_error "release .treeinfo does not declare architecture ${ARCH}"
    fi
}

check_kickstart_urls() {
    local ks_dir="$TMP/kickstarts"
    local ks release updates

    if ! bash "$REPO_ROOT/build_files/generate-kickstarts.sh" "$ks_dir" both >/dev/null; then
        config_error "could not generate the Classic kickstarts"
        return 1
    fi

    for ks in "$ks_dir"/*.ks; do
        release=$(sed -n 's/^url --url="\(.*\)"$/\1/p' "$ks" | head -1)
        updates=$(sed -n 's/^repo --name="fedora-updates" --baseurl="\(.*\)"$/\1/p' "$ks" | head -1)

        if [[ $release != "$FEDORA_RELEASE_URL" ]]; then
            config_error "$(basename "$ks"): url is '$release', expected '$FEDORA_RELEASE_URL'"
        fi
        if [[ $updates != "$FEDORA_UPDATES_URL" ]]; then
            config_error "$(basename "$ks"): updates baseurl is '$updates', expected '$FEDORA_UPDATES_URL'"
        fi
        if [[ $(grep -c '^url --url=' "$ks") -ne 1 ]]; then
            config_error "$(basename "$ks"): expected exactly one url command"
        fi
        if [[ $(grep -c '^repo --name="fedora-updates"' "$ks") -ne 1 ]]; then
            config_error "$(basename "$ks"): expected exactly one fedora-updates repo"
        fi
        if grep -qE '^repo .*(metalink=|mirrorlist=|--install)' "$ks"; then
            config_error "$(basename "$ks"): installer repo must use baseurl and must not be --install"
        fi
        if grep -qE '^(url|repo) .*(mirrors\.fedoraproject\.org|download\.fedoraproject\.org)' "$ks"; then
            config_error "$(basename "$ks"): installer must use dl.fedoraproject.org, not a metalink host"
        fi
        if ! grep -q '^network --bootproto=dhcp --device=link --activate --onboot=on$' "$ks"; then
            config_error "$(basename "$ks"): missing the standard network command"
        fi
        if ! grep -q '^%packages --retries=5 --timeout=60$' "$ks"; then
            config_error "$(basename "$ks"): missing package download retries/timeout"
        fi
    done
}

printf 'checking Fedora %s %s installer repositories\n' "$FEDORA_VERSION" "$ARCH"
check_kickstart_urls
check_repomd "release" "$FEDORA_RELEASE_URL"
check_repomd "updates" "$FEDORA_UPDATES_URL"
check_treeinfo

if ((CONFIG_ERROR)); then
    printf '\nrepository check FAILED: project configuration is wrong\n' >&2
    exit 1
fi

if ((NETWORK_ERROR)); then
    printf '\nrepository check INCOMPLETE: Fedora hosts are temporarily unreachable\n' >&2
    exit 2
fi

printf '\nrepository check OK: %s and %s\n' "$FEDORA_RELEASE_URL" "$FEDORA_UPDATES_URL"
