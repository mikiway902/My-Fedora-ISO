#!/bin/bash
# Generate an SPDX 2.3 package inventory for a locally built image.
# Usage: generate-sbom.sh IMAGE OUTPUT.json
# The inventory comes straight from the RPM database inside the image, so it
# needs neither network access nor a vulnerability database.
set -euo pipefail

image=${1:?usage: generate-sbom.sh IMAGE OUTPUT.json}
output=${2:?usage: generate-sbom.sh IMAGE OUTPUT.json}
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

podman run --rm --entrypoint /usr/bin/rpm "$image" \
    -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\t%{LICENSE}\n' >"$tmp"

python3 - "$tmp" "$output" "$image" <<'PY'
import datetime
import json
import sys
import uuid

tsv, out, image = sys.argv[1:4]

packages = []
with open(tsv, encoding="utf-8") as stream:
    for line in stream:
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 4:
            continue
        name, version, arch, license_name = parts
        packages.append(
            {
                "SPDXID": f"SPDXRef-Package-{len(packages) + 1}",
                "name": name,
                "versionInfo": version,
                "downloadLocation": "NOASSERTION",
                "filesAnalyzed": False,
                "licenseConcluded": "NOASSERTION",
                "licenseDeclared": license_name or "NOASSERTION",
                "supplier": "NOASSERTION",
                "externalRefs": [
                    {
                        "referenceCategory": "PACKAGE-MANAGER",
                        "referenceType": "purl",
                        "referenceLocator": f"pkg:rpm/fedora/{name}@{version}?arch={arch}",
                    }
                ],
            }
        )

document = {
    "spdxVersion": "SPDX-2.3",
    "dataLicense": "CC0-1.0",
    "SPDXID": "SPDXRef-DOCUMENT",
    "name": image,
    "documentNamespace": f"https://github.com/mikiway902/My-Fedora-ISO/sbom/{uuid.uuid4()}",
    "creationInfo": {
        "created": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "creators": ["Tool: my-fedora-generate-sbom"],
    },
    "documentDescribes": [package["SPDXID"] for package in packages],
    "packages": packages,
}

with open(out, "w", encoding="utf-8") as stream:
    json.dump(document, stream, indent=2, ensure_ascii=False)
    stream.write("\n")

print(f"saved {out}: {len(packages)} packages")
PY
