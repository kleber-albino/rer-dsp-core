#!/bin/sh
# Picks the active operational file, or the versioned .example if it is missing.
# Usage:
#   select-runtime-config.sh pick <src_dir> <name> <dest_file>
#   select-runtime-config.sh about <src_dir> <dest_dir>
set -eu

die() {
  echo "select-runtime-config: $*" >&2
  exit 1
}

pick() {
  p_src="$1"
  p_name="$2"
  p_dest="$3"
  mkdir -p "$(dirname "$p_dest")"
  if [ -f "$p_src/$p_name" ]; then
    cp "$p_src/$p_name" "$p_dest"
  elif [ -f "$p_src/$p_name.example" ]; then
    cp "$p_src/$p_name.example" "$p_dest"
  else
    die "missing $p_name and $p_name.example in $p_src"
  fi
}

copy_about_markdown() {
  a_src="$1"
  a_dest="$2"
  file_name="$3"

  case "$file_name" in
    */* | "" | *"~"*) die "invalid about tab file name: $file_name" ;;
  esac
  base=$(basename "$file_name")
  if [ "$base" != "$file_name" ]; then
    die "invalid about tab file name: $file_name"
  fi

  if [ -f "$a_src/$base" ]; then
    cp "$a_src/$base" "$a_dest/$base"
    return 0
  fi

  example="$a_src/${base}.example"
  if [ -f "$example" ]; then
    case "$example" in
      *.quickstart.md.example) ;;
      *)
        cp "$example" "$a_dest/$base"
        return 0
        ;;
    esac
  fi

  die "missing $base (and ${base}.example) in $a_src for about-config.json tab"
}

sync_about() {
  a_src="$1"
  a_dest="$2"
  mkdir -p "$a_dest"
  pick "$a_src" "about-config.json" "$a_dest/about-config.json"

  if ! command -v jq >/dev/null 2>&1; then
    die "jq is required for the about command"
  fi

  while IFS= read -r file_name; do
    [ -n "$file_name" ] || continue
    copy_about_markdown "$a_src" "$a_dest" "$file_name"
  done <<EOF
$(jq -r '.tabs[]?.file // empty' "$a_dest/about-config.json")
EOF
}

cmd="${1:-}"
case "$cmd" in
  pick)
    [ "$#" -eq 4 ] || die "usage: pick <src_dir> <name> <dest_file>"
    pick "$2" "$3" "$4"
    ;;
  about)
    [ "$#" -eq 3 ] || die "usage: about <src_dir> <dest_dir>"
    sync_about "$2" "$3"
    ;;
  *)
    die "usage: pick <src_dir> <name> <dest_file> | about <src_dir> <dest_dir>"
    ;;
esac
