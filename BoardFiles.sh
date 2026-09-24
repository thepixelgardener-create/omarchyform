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
