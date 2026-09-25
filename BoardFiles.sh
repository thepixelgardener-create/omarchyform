#!/usr/bin/env bash
# Local filesystem operations. Paths are data, never shell source.
set -euo pipefail

# Refuse traversal and symlink components below base, including dangling
# symlinks. Base itself may be a symlink (e.g. a boards folder kept in a
# dotfiles repo): it is where the user chose to keep their data.
confined() {
  local base=$1 relative=$2 component current
  local -a components
  [[ -d $base && -n $relative && $relative != /* ]] || return 1
  [[ ! $relative =~ [[:cntrl:]] ]] || return 1
  current=$base
  IFS=/ read -ra components <<< "$relative"
  for component in "${components[@]}"; do
    [[ -n $component && $component != . && $component != .. && ! $component =~ [[:cntrl:]] ]] || return 1
    current=$current/$component
    [[ ! -L $current ]] || return 1
  done
  [[ $relative != */ ]]
}

operation=$1
shift
case "$operation" in
  export)
    staged=$1 destination=$2 private_root=$3
    [[ -f $staged && ! -L $destination ]]
    resolved=$(realpath -m -- "$destination")
    private_root=$(realpath -m -- "$private_root")
    [[ $resolved != "$private_root" && $resolved != "$private_root/"* ]]
    temporary=$(mktemp -- "$(dirname -- "$destination")/.omarchyform-export-XXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    cp -T -- "$staged" "$temporary"
    mv -fT -- "$temporary" "$destination"
    rm -- "$staged"
    ;;
  publish)
    # Publish a complete staged board to a unique name without overwriting.
    board_root=$1 base_name=$2 staged=$3
    [[ $base_name != */* ]]
    confined "$board_root" "$base_name.json"
    [[ -f $staged && ! -L $staged ]]
    number=1
    candidate=$base_name.json
    while ! ln -T -- "$staged" "$board_root/$candidate" 2>/dev/null; do
      [[ -e $board_root/$candidate || -L $board_root/$candidate ]] || exit 1
      number=$((number + 1))
      candidate=$base_name-$number.json
    done
    rm -- "$staged"
    printf '%s' "$candidate"
    ;;
  move)
    source_root=$1 source_name=$2 target_root=$3 target_name=$4
    confined "$source_root" "$source_name"
    confined "$target_root" "$target_name"
    source_path=$source_root/$source_name target_path=$target_root/$target_name
    [[ -e $source_path && ! -e $target_path && ! -L $target_path ]]
    mkdir -p -- "$(dirname -- "$target_path")"
    # -T prevents nesting into a directory; -n protects an intervening creation.
    mv -nT -- "$source_path" "$target_path"
    [[ ! -e $source_path && ! -L $source_path ]]
    ;;
  clipimage)
    # The clipboard picks the format; this picks the name and the folder, so
    # nothing the clipboard says can steer where the bytes land. Exit 4 means
    # there is no image on it, which is the caller's cue to try text instead.
    images_root=$1 base_name=$2
    [[ $base_name != */* && $base_name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
    mime=$(timeout 5 wl-paste --list-types 2>/dev/null | grep -m1 -E '^image/(png|jpeg|webp|gif|bmp)$' || true)
    [[ -n $mime ]] || exit 4
    case "$mime" in
      image/png) extension=png ;;
      image/jpeg) extension=jpg ;;
      image/webp) extension=webp ;;
      image/gif) extension=gif ;;
      *) extension=bmp ;;
    esac
    confined "$images_root" "$base_name.$extension"
    temporary=$(mktemp -- "$images_root/.omarchyform-paste-XXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    timeout 10 wl-paste --no-newline --type "$mime" > "$temporary" || exit 4
    [[ -s $temporary ]] || exit 4
    mv -nT -- "$temporary" "$images_root/$base_name.$extension"
    printf '%s' "$base_name.$extension"
    ;;
  importimage)
    # A dropped path is untrusted: it names a file to read, never where bytes
    # land or what they are called. The type comes from the content rather than
    # the name, and a file too big to sit on a board is refused before it is
    # copied. Exit 4 means "not an image this can take", 5 means "too large".
    images_root=$1 base_name=$2 source_path=$3
    [[ $base_name != */* && $base_name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
    [[ -f $source_path ]] || exit 4
    size=$(stat -Lc %s -- "$source_path") || exit 4
    (( size > 0 )) || exit 4
    (( size <= 33554432 )) || exit 5
    case "$(file -bL --mime-type -- "$source_path")" in
      image/png) extension=png ;;
      image/jpeg) extension=jpg ;;
      image/webp) extension=webp ;;
      image/gif) extension=gif ;;
      image/bmp) extension=bmp ;;
      *) exit 4 ;;
    esac
    confined "$images_root" "$base_name.$extension"
    temporary=$(mktemp -- "$images_root/.omarchyform-drop-XXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    cp -- "$source_path" "$temporary"
    mv -nT -- "$temporary" "$images_root/$base_name.$extension"
    printf '%s' "$base_name.$extension"
    ;;
  check)
    # Loading asks first, so a board that could never be saved is not opened.
    confined "$1" "$2" || exit 3
    ;;
  mkdir)
    confined "$1" "$2"
    mkdir -- "$1/$2"
    ;;
  purge)
    [[ $2 != */* ]]
    confined "$1" "$2"
    rm -rf -- "$1/$2"
    ;;
  backup)
    board=$1 backup=$2 root=${3:-} backup_root=${4:-}
    # Exit 3 marks a refused path, so the caller can say why nothing was saved.
    if [[ -n $root ]]; then
      [[ $board == "$root/"* ]] || exit 3
      confined "$root" "${board#"$root/"}" || exit 3
    fi
    if [[ -n $backup_root ]]; then
      [[ $backup == "$backup_root/"* ]] || exit 3
      confined "$backup_root" "${backup#"$backup_root/"}" || exit 3
    fi
    [[ ! -L $board && ! -L $backup && ! -L $backup.tmp ]] || exit 3
    mkdir -p -- "$(dirname -- "$backup")"
    if [[ -e $board ]]; then
      cp -T -- "$board" "$backup.tmp"
      mv -fT -- "$backup.tmp" "$backup"
    fi
    ;;
  *) exit 2 ;;
esac
