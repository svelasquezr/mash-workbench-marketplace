#!/usr/bin/env bash
# Convention: a SKILL.md that points to a "Heading" in its reference.md names a heading that exists there,
# so renaming a heading cannot leave a dangling pointer.
set -euo pipefail
cd "$(dirname "$0")/.."
source tests/lib.sh

# Prints each name SKILL.md points to ("<Heading>" in … or "<Heading>" of …) on a line that points to a reference (the word "reference", or the `<ref>`
# shorthand for it) that is not a heading of the skill's reference.md, nor of another skill's reference.md that the
# same line names (`../<skill>/reference.md`).
dangling_pointers() {
  local skill_file=$1 reference_file=$2 line name other headings_files
  grep -iE 'reference|<ref>' "$skill_file" | while IFS= read -r line; do
    headings_files=("$reference_file")
    while IFS= read -r other; do
      [[ -n "$other" ]] && headings_files+=("$(dirname "$skill_file")/$other/reference.md")
    done < <(grep -oE '\.\./[a-z0-9-]+/reference\.md' <<< "$line" | sed -E 's|/reference\.md$||' || true)
    { grep -oE '"[^"]+" (in|of) ' <<< "$line" || true; } | sed -E 's/^"(.*)" (in|of) $/\1/' | while IFS= read -r name; do
      cat "${headings_files[@]}" 2>/dev/null | grep -qxE "#{1,6} ${name}" \
        || echo "$skill_file: no heading \"$name\" in $reference_file"
    done
  done
}

# The check catches a dangling pointer.
scratch=$(mktemp -d); trap 'rm -rf "$scratch"' EXIT
printf '# Ref\n\n## Real one\n' > "$scratch/reference.md"
printf 'see "Real one" in the reference.\nsee "Gone" in the reference.\n' > "$scratch/SKILL.md"
assert_eq "$(dangling_pointers "$scratch/SKILL.md" "$scratch/reference.md")" "$scratch/SKILL.md: no heading \"Gone\" in $scratch/reference.md"
# The <ref> shorthand counts, and so does a heading of another skill's reference.md that the line names.
mkdir -p "$scratch/a" "$scratch/b"
printf '# Ref\n\n## Mine\n' > "$scratch/a/reference.md"
printf '# Ref\n\n## Theirs\n' > "$scratch/b/reference.md"
# shellcheck disable=SC2016  # the backticks are literal Markdown
printf 'see "Mine" in `<ref>`.\nsee "Theirs" in `../b/reference.md`.\nsee "Nowhere" in `<ref>`.\n' > "$scratch/a/SKILL.md"
assert_eq "$(dangling_pointers "$scratch/a/SKILL.md" "$scratch/a/reference.md")" "$scratch/a/SKILL.md: no heading \"Nowhere\" in $scratch/a/reference.md"
# A line that names no heading is fine.
printf 'nothing quoted near the reference here.\n' > "$scratch/a/SKILL.md"
assert_eq "$(dangling_pointers "$scratch/a/SKILL.md" "$scratch/a/reference.md")" ""

# Every skill with a reference.md points only to headings that exist.
problems=""
for reference_file in plugins/*/skills/*/reference.md; do
  problems+=$(dangling_pointers "$(dirname "$reference_file")/SKILL.md" "$reference_file")
done
assert_eq "$problems" ""
