#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
KEY_ARN="arn:aws:kms:us-east-1:123456789012:key/your-key-id-here"
# ──────────────────────────────────────────────────────────────────────────────

if [[ -z "$KEY_ARN" ]]; then
  echo "ERROR: KEY_ARN is not set." >&2
  exit 1
fi

echo "Fetching grants for key: $KEY_ARN"

grant_ids=()
marker=""

# Paginate through all grants
while true; do
  if [[ -n "$marker" ]]; then
    response=$(aws kms list-grants --key-id "$KEY_ARN" --marker "$marker")
  else
    response=$(aws kms list-grants --key-id "$KEY_ARN")
  fi

  # Extract grant IDs from this page
  page_ids=$(echo "$response" | jq -r '.Grants[].GrantId')
  while IFS= read -r id; do
    [[ -n "$id" ]] && grant_ids+=("$id")
  done <<< "$page_ids"

  # Check for next page
  marker=$(echo "$response" | jq -r '.NextMarker // empty')
  [[ -z "$marker" ]] && break
done

total=${#grant_ids[@]}

if [[ $total -eq 0 ]]; then
  echo "No grants found for this key."
  exit 0
fi

echo "Found $total grant(s). Revoking..."

revoked=0
failed=0

for grant_id in "${grant_ids[@]}"; do
  echo -n "  Revoking grant $grant_id ... "
  if aws kms revoke-grant --key-id "$KEY_ARN" --grant-id "$grant_id"; then
    echo "OK"
    (( revoked++ ))
  else
    echo "FAILED"
    (( failed++ ))
  fi
done

echo ""
echo "Done. Revoked: $revoked  Failed: $failed"
[[ $failed -gt 0 ]] && exit 1 || exit 0
