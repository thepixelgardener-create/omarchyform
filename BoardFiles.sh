#!/usr/bin/env bash
# Local filesystem operations. Paths are data, never shell source.
set -euo pipefail

# Refuse traversal and symlink components, including dangling symlinks.
confined() {
  local base=$1 relative=$2 component current
  local -a components
  [[ -d $base && ! -L $base && -n $relative && $relative != /* ]] || return 1
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
    if [[ -n $root ]]; then
      [[ $board == "$root/"* ]]
      confined "$root" "${board#"$root/"}"
    fi
    if [[ -n $backup_root ]]; then
      [[ $backup == "$backup_root/"* ]]
      confined "$backup_root" "${backup#"$backup_root/"}"
    fi
    [[ ! -L $board && ! -L $backup && ! -L $backup.tmp ]]
    mkdir -p -- "$(dirname -- "$backup")"
    if [[ -e $board ]]; then
      cp -T -- "$board" "$backup.tmp"
      mv -fT -- "$backup.tmp" "$backup"
    fi
    ;;
  *) exit 2 ;;
esac
