#!/usr/bin/env bash
set -euo pipefail

# Trivy v0.75.0 pinned to its upstream release: https://github.com/aquasecurity/trivy/releases/tag/v0.75.0
TRIVY_IMAGE="aquasec/trivy:0.75.0"
OUTPUT_DIR="${1:-${RUNNER_TEMP:-/tmp}/playstead-release-evidence}"
ARCHIVE="${RELEASE_ARCHIVE:?RELEASE_ARCHIVE must name the smoke-tested docker archive}"
EXPECTED_SHA="${RELEASE_SHA256:?RELEASE_SHA256 is required}"
IMAGE_REF="${RELEASE_IMAGE_REF:?RELEASE_IMAGE_REF is required}"
mkdir -p "$OUTPUT_DIR"
ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
test "$ACTUAL_SHA" = "$EXPECTED_SHA"
IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$IMAGE_REF")"
test -n "$IMAGE_ID"

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:/work:ro" -v "$OUTPUT_DIR:/evidence" "$TRIVY_IMAGE" image \
  --config /work/scripts/ci/trivy.yaml --scanners vuln,license --format json \
  --output /evidence/image-trivy.json "$IMAGE_REF"
docker run --rm -v "$PWD:/work:ro" -v "$OUTPUT_DIR:/evidence" "$TRIVY_IMAGE" fs \
  --config /work/scripts/ci/trivy.yaml --scanners vuln,license --format json \
  --output /evidence/source-trivy.json /work/playstead-server
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:/work:ro" -v "$OUTPUT_DIR:/evidence" "$TRIVY_IMAGE" image \
  --config /work/scripts/ci/trivy.yaml --format cyclonedx --output /evidence/sbom.cdx.json "$IMAGE_REF"

python3 - "$OUTPUT_DIR" "$ACTUAL_SHA" "$IMAGE_ID" <<'PY'
import json, pathlib, sys
out, digest, image_id = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
reports = {}
for label in ('source', 'image'):
    report = json.loads((out / f'{label}-trivy.json').read_text())
    if not isinstance(report.get('Results'), list) or not report['Results']:
        raise SystemExit(f'{label} scanner discovered zero targets')
    if label == 'image' and report.get('Metadata', {}).get('ImageID') != image_id:
        raise SystemExit('Trivy scanned an image other than the smoke-tested image ID')
    high_critical = 0
    prohibited = 0
    for result in report['Results']:
        for vuln in result.get('Vulnerabilities') or []:
            if vuln.get('Severity') in {'HIGH', 'CRITICAL'}:
                high_critical += 1
        for license in result.get('Licenses') or []:
            if license.get('Severity') in {'HIGH', 'CRITICAL'} or license.get('Name') in {'AGPL-3.0', 'GPL-3.0-only', 'GPL-3.0-or-later', 'SSPL-1.0'}:
                prohibited += 1
    reports[label] = {'status':'passed' if high_critical == 0 and prohibited == 0 else 'failed',
      'subject_sha256':digest,'high_critical':high_critical,
      'license_policy':'passed' if prohibited == 0 else 'failed','prohibited_licenses':prohibited}
sbom = json.loads((out / 'sbom.cdx.json').read_text())
if sbom.get('bomFormat') != 'CycloneDX' or not sbom.get('components'):
    raise SystemExit('missing or empty CycloneDX SBOM')
evidence = {
  'schema_version': 1, 'mode': 'pull-request',
  'subject': {'archive_sha256': digest, 'image_id': image_id},
  'scans': reports,
  'sbom': {'format':'CycloneDX','status':'passed','subject_sha256':digest,'components':len(sbom['components'])},
  'parser_inventory': json.loads((out / 'parser-inventory.json').read_text()),
  'attestations': {'provenance':{'status':'not-issued','subject_sha256':None},'sbom':{'status':'not-issued','subject_sha256':None}},
  'handoff': {'consumer':'Phase 05 D-11','subject_sha256':digest,'retained_gates':['D-07','D-13']},
}
(out / 'evidence-input.json').write_text(json.dumps(evidence))
PY
python3 scripts/ci/release-evidence.py --input "$OUTPUT_DIR/evidence-input.json" --output "$OUTPUT_DIR/evidence.json"
