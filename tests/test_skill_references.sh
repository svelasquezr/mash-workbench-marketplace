#!/usr/bin/env bash
# Convention: a SKILL.md that points to a "Heading" in a reference.md names a heading that exists there, so renaming a
# heading cannot leave a dangling pointer. The reference files of a skill are its own reference.md and every
# ../<skill>/reference.md it names; a quoted name next to the word "reference" must be a heading of one of them.
set -euo pipefail
cd "$(dirname "$0")/.."
source tests/lib.sh

# reference_files <SKILL.md>: its own reference.md, when it exists, and each ../<skill>/reference.md it names.
reference_files() {
  local skill_file=$1 folder relative
  folder=$(dirname "$skill_file")
  [[ ! -f "$folder/reference.md" ]] || echo "$folder/reference.md"
  { grep -o '\.\./[a-z0-9-]*/reference\.md' "$skill_file" || true; } | sort -u | while IFS= read -r relative; do
    echo "$folder/$relative"
  done
}

# dangling_pointers <SKILL.md>: each quoted name on a line with the word "reference" that is no heading of its files.
dangling_pointers() {
  local skill_file=$1 name reference_file found
  local -a files=()
  while IFS= read -r reference_file; do files+=("$reference_file"); done < <(reference_files "$skill_file")
  [[ ${#files[@]} -gt 0 ]] || return 0
  for reference_file in "${files[@]}"; do
    [[ -f "$reference_file" ]] || echo "$skill_file: no such file $reference_file"
  done
  grep -i 'reference' "$skill_file" | grep -o '"[^"]*"' | tr -d '"' | while IFS= read -r name; do
    found=no
    for reference_file in "${files[@]}"; do
      [[ -f "$reference_file" ]] && grep -qxE "#{1,6} ${name}" "$reference_file" && found=yes
    done
    [[ "$found" == yes ]] || echo "$skill_file: no heading \"$name\" in ${files[*]}"
  done
}

# The check catches a dangling pointer, follows a ../<skill>/reference.md pointer, and catches a missing one.
scratch=$(mktemp -d); trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/a" "$scratch/b" "$scratch/c"
printf '# Ref\n\n## Real one\n' > "$scratch/a/reference.md"
printf 'see "Real one" in the reference.\nsee "Gone" in the reference.\n' > "$scratch/a/SKILL.md"
assert_eq "$(dangling_pointers "$scratch/a/SKILL.md")" "$scratch/a/SKILL.md: no heading \"Gone\" in $scratch/a/reference.md"
# shellcheck disable=SC2016  # the backticks are text in the fixture
printf 'see "Real one" in `../a/reference.md`.\nsee "Gone" in that reference.\n' > "$scratch/b/SKILL.md"
assert_eq "$(dangling_pointers "$scratch/b/SKILL.md")" "$scratch/b/SKILL.md: no heading \"Gone\" in $scratch/b/../a/reference.md"
# shellcheck disable=SC2016  # the backticks are text in the fixture
printf 'see "Real one" in `../none/reference.md`.\n' > "$scratch/c/SKILL.md"
assert_contains "$(dangling_pointers "$scratch/c/SKILL.md")" "no such file $scratch/c/../none/reference.md"

# Every skill points only to headings that exist.
problems=""
for skill_file in plugins/*/skills/*/SKILL.md; do
  problems+=$(dangling_pointers "$skill_file")
done
assert_eq "$problems" ""
