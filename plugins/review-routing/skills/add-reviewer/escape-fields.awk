# Read escape files (escape-add.sh writes them) and print one tab-separated line per file that has an area:
#   <file name> <date> <area> <class> <source> <first body line>
# The frontmatter is the block between a first line "---" and the next "---"; each line in it is "key: value", split at
# the first ":". A file without frontmatter or without an area prints nothing. The area loses a leading ./ and a
# trailing /, so a hand-edited file counts with the others. Used by escape-add.sh (--list, the source dedupe) and
# escapes-report.sh: awk -f escape-fields.awk <files>. POSIX awk (no ENDFILE), so it runs on macOS and Git Bash.
function flush() {
  if (file != "" && area != "") printf "%s\t%s\t%s\t%s\t%s\t%s\n", name, date, area, class, source, first
  file = ""; area = ""; date = ""; class = ""; source = ""; first = ""
}
FNR == 1 {
  flush()
  file = FILENAME; name = FILENAME; sub(/.*\//, "", name)
  state = 0
}
{ sub(/\r$/, "") }
state == 0 { state = ($0 == "---") ? 1 : 3; next }
state == 1 && $0 == "---" { state = 2; next }
state == 1 {
  split_at = index($0, ":")
  if (split_at == 0) next
  key = substr($0, 1, split_at - 1); value = substr($0, split_at + 1)
  gsub(/^[ \t]+|[ \t]+$/, "", key); gsub(/^[ \t]+|[ \t]+$/, "", value); gsub(/\t/, " ", value)
  if (key == "date") date = value
  else if (key == "area") { area = value; sub(/^(\.\/)+/, "", area); sub(/\/+$/, "", area) }
  else if (key == "class") class = value
  else if (key == "source") source = value
  next
}
state == 2 && first == "" && $0 !~ /^[ \t]*$/ { first = $0; gsub(/\t/, " ", first) }
END { flush() }
