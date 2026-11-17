#!/bin/bash
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
node - "$REPO/.github/workflows/build-classic.yml" <<'JS'
const fs = require("node:fs");
const assert = require("node:assert/strict");
const workflow = fs.readFileSync(process.argv[2], "utf8");
const expressions = {};
for (const key of ["variant", "hardware_profile"]) {
  const match = workflow.match(new RegExp(`^        ${key}: \\$\\{\\{ (.+) \\}\\}$`, "m"));
  assert.ok(match, `missing matrix ${key}`);
  expressions[key] = match[1];
}
// Evaluate only this repository's fixed matrix expressions, with no host I/O.
function matrix(event, ref, inputs = {}) {
  const github = {event_name: event, ref};
  return Object.fromEntries(Object.entries(expressions).map(([key, expression]) =>
    [key, new Function("github", "inputs", "fromJSON", `return (${expression});`)(github, inputs, JSON.parse)]));
}
assert.deepEqual(matrix("push", "refs/heads/main"), {
  variant: ["gnome"], hardware_profile: ["generic", "desktop-nvidia"]
});
assert.deepEqual(matrix("schedule", "refs/heads/main"), {
  variant: ["gnome", "driftwm"], hardware_profile: ["generic"]
});
assert.deepEqual(matrix("push", "refs/tags/v1"), {
  variant: ["gnome", "driftwm"], hardware_profile: ["generic"]
});
assert.deepEqual(matrix("workflow_dispatch", "refs/heads/main",
  {variant: "both", hardware_profile: "desktop-nvidia"}), {
    variant: ["gnome"], hardware_profile: ["desktop-nvidia"]
});
assert.deepEqual(matrix("workflow_dispatch", "refs/heads/main",
  {variant: "driftwm", hardware_profile: "generic"}), {
    variant: ["driftwm"], hardware_profile: ["generic"]
});
assert.match(workflow, /push:\n    branches:\n      - main/);
assert.match(workflow, /HARDWARE_PROFILE: \$\{\{ matrix.hardware_profile \}\}/);
console.log("classic workflow matrix: OK");
JS
