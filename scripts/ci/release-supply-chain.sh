#!/usr/bin/env bash
set -euo pipefail

# Trivy v0.75.0 pinned to its upstream release: https://github.com/aquasecurity/trivy/releases/tag/v0.75.0
TRIVY_IMAGE="aquasec/trivy:0.75.0"
OUTPUT_DIR="${1:-${RUNNER_TEMP:-/tmp}/playstead-release-evidence}"
ARCHIVE="${RELEASE_ARCHIVE:?RELEASE_ARCHIVE must name the smoke-tested docker archive}"
EXPECTED_SHA="${RELEASE_SHA256:?RELEASE_SHA256 is required}"
IMAGE_REF="${RELEASE_IMAGE_REF:?RELEASE_IMAGE_REF is required}"
mkdir -p "$OUTPUT_DIR"
RAW_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/playstead-trivy.XXXXXX")"
trap 'rm -rf "$RAW_DIR"' EXIT
export RAW_DIR
ACTUAL_SHA="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
test "$ACTUAL_SHA" = "$EXPECTED_SHA"
IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$IMAGE_REF")"
test -n "$IMAGE_ID"

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:/work:ro" -v "$RAW_DIR:/raw" "$TRIVY_IMAGE" image \
  --config /work/scripts/ci/trivy.yaml --scanners vuln --format json \
  --output /raw/image-trivy.json "$IMAGE_REF"
# The container vulnerability scan covers every installed image package.
# Restricted-license policy is scoped to Playstead's resolved source dependencies
# below; applying it to Debian's base-system packages incorrectly treated normal
# distro utilities as Playstead application dependencies.
docker run --rm -v "$PWD:/work:ro" -v "$RAW_DIR:/raw" "$TRIVY_IMAGE" fs \
  --config /work/scripts/ci/trivy.yaml --scanners vuln,license --format json \
  --output /raw/source-trivy.json /work/playstead-server
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:/work:ro" -v "$OUTPUT_DIR:/evidence" "$TRIVY_IMAGE" image \
  --config /work/scripts/ci/trivy.yaml --format cyclonedx --output /evidence/sbom.cdx.json "$IMAGE_REF"

python3 - "$OUTPUT_DIR" "$ACTUAL_SHA" "$IMAGE_ID" <<'PY'
import json, pathlib, sys
sys.dont_write_bytecode = True
import importlib.util
out, digest, image_id = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
raw = pathlib.Path(__import__('os').environ['RAW_DIR'])
spec = importlib.util.spec_from_file_location('release_evidence', 'scripts/ci/release-evidence.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
reports = {}
for label in ('source', 'image'):
    report = json.loads((raw / f'{label}-trivy.json').read_text())
    summary = validator.summarize_trivy(report, digest, image_id if label == 'image' else None)
    reports[label] = summary
    if summary['status'] != 'passed':
        safe = validator.safe_trivy_diagnostics(report)
        print(
            f"Trivy {label} scan failed (bounded findings): "
            + json.dumps(safe, sort_keys=True, separators=(',', ':')),
            file=sys.stderr,
        )
    elif summary['unfixed_high_critical']:
        safe = validator.safe_trivy_diagnostics(report)
        print(
            f"Trivy {label} scan passed with {summary['unfixed_high_critical']} high/critical findings without a published fix; "
            "these remain recorded in release evidence (bounded findings): "
            + json.dumps(safe, sort_keys=True, separators=(',', ':')),
            file=sys.stderr,
        )
sbom = json.loads((out / 'sbom.cdx.json').read_text())
component_count = validator.validate_cyclonedx(sbom)
evidence = {
  'schema_version': 1, 'mode': 'pull-request',
  'subject': {'archive_sha256': digest, 'image_id': image_id},
  'scans': reports,
  'sbom': {'format':'CycloneDX','status':'passed','subject_sha256':digest,'components':component_count},
  'parser_inventory': json.loads((out / 'parser-inventory.json').read_text()),
  'attestations': {'provenance':{'status':'not-issued','subject_sha256':None},'sbom':{'status':'not-issued','subject_sha256':None}},
  'handoff': {'consumer':'Phase 05 D-11','subject_sha256':digest,'retained_gates':['D-07','D-13']},
}
(out / 'evidence-input.json').write_text(json.dumps(evidence))
(out / 'scan-reports.json').write_text(json.dumps({'schema_version':1,'subject_sha256':digest,'scanner':'Trivy 0.75.0','reports':reports}, sort_keys=True, separators=(',',':')) + '\n')
PY
python3 scripts/ci/release-evidence.py --input "$OUTPUT_DIR/evidence-input.json" --output "$OUTPUT_DIR/evidence.json"
