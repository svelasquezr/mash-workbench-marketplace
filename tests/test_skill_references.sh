#!/usr/bin/env bash
# Convention: a SKILL.md that points to a "Heading" in its reference.md names a heading that exists there,
# so renaming a heading cannot leave a dangling pointer.
set -euo pipefail
cd "$(dirname "$0")/.."
source tests/lib.sh

# Prints each quoted name SKILL.md gives next to the word "reference" that is not a heading of reference.md.
dangling_pointers() {
  local skill_file=$1 reference_file=$2 name
  grep -i 'reference' "$skill_file" | grep -o '"[^"]*"' | tr -d '"' | while IFS= read -r name; do
    grep -qxE "#{1,6} ${name}" "$reference_file" || echo "$skill_file: no heading \"$name\" in $reference_file"
  done
}

# The check catches a dangling pointer.
scratch=$(mktemp -d); trap 'rm -rf "$scratch"' EXIT
printf '# Ref\n\n## Real one\n' > "$scratch/reference.md"
printf 'see "Real one" in the reference.\nsee "Gone" in the reference.\n' > "$scratch/SKILL.md"
assert_eq "$(dangling_pointers "$scratch/SKILL.md" "$scratch/reference.md")" "$scratch/SKILL.md: no heading \"Gone\" in $scratch/reference.md"

# Every skill with a reference.md points only to headings that exist.
problems=""
for reference_file in plugins/*/skills/*/reference.md; do
  problems+=$(dangling_pointers "$(dirname "$reference_file")/SKILL.md" "$reference_file")
done
assert_eq "$problems" ""
