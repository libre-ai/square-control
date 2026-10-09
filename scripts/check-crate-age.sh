#!/bin/sh
# Supply-chain age guard: every locked crates.io package must have been published at least
# MIN_DAYS days before the check (default 3). Prints the volume examined; a package whose
# date cannot be read is a failure, never a pass.
set -u
cd "$(git rev-parse --show-toplevel)"
min_days="${MIN_DAYS:-3}"
now=$(date -u +%s)
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cargo metadata --format-version 1 --locked --offline 2>/dev/null \
  | jq -r '.packages[] | select(.source != null) | "\(.name) \(.version)"' | sort -u > "$work/packages.txt"
total=$(wc -l < "$work/packages.txt" | tr -d ' ')
[ "$total" -gt 0 ] || { echo "UNREADABLE: no locked package"; exit 2; }
young=0
unreadable=0
youngest=""
youngest_age=999999
while read -r name version; do
  created=$(curl -s -m 20 -A "square-control-age-guard (local)" "https://crates.io/api/v1/crates/$name/$version" \
    | jq -r '.version.created_at // empty')
  if [ -z "$created" ]; then
    echo "UNREADABLE: $name $version"; unreadable=$((unreadable + 1)); continue
  fi
  published=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${created%%.*}" +%s 2>/dev/null)
  age_days=$(( (now - published) / 86400 ))
  [ "$age_days" -lt "$youngest_age" ] && { youngest_age=$age_days; youngest="$name $version ($created)"; }
  if [ "$age_days" -lt "$min_days" ]; then echo "TOO YOUNG: $name $version published $created"; young=$((young + 1)); fi
  sleep 1
done < "$work/packages.txt"
echo "examined=$total too_young=$young unreadable=$unreadable min_days=$min_days youngest=$youngest age_days=$youngest_age"
[ "$young" -eq 0 ] && [ "$unreadable" -eq 0 ]
