#!/usr/bin/env bash
# Install or remove the launcher entry, the board file type, and the small
# command the two of them call. Nothing else.
#
# All three land in directories shared with every other application, so a file
# there is only replaced or removed once it has been established to be one of
# ours and unmodified since we wrote it. Anything else is a concrete conflict,
# reported and left alone until the user says otherwise with --force.
#
# Every file is checked before any file is written: a run that would conflict
# on the second one does not install the first and leave half a feature behind.
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
# Not a standard variable, but the de-facto directory, and the tests need to
# point this somewhere harmless.
bin_home="${XDG_BIN_HOME:-$HOME/.local/bin}"

# source name, where it goes, and the mode it wants.
targets=(
  "omarchyform.desktop|$data_home/applications/omarchyform.desktop|644"
  "omarchyform.xml|$data_home/mime/packages/omarchyform.xml|644"
  "omarchyform-open|$bin_home/omarchyform-open|755"
)

force=false
uninstall=false
for argument in "$@"; do
  case "$argument" in
    --force) force=true ;;
    --uninstall) uninstall=true ;;
    *) printf 'usage: %s [--uninstall] [--force]\n' "${BASH_SOURCE[0]}" >&2; exit 2 ;;
  esac
done

# Ownership is a key in the file rather than a path or a timestamp: a path says
# nothing about who wrote it, and a timestamp changes for reasons of its own.
# The three files are three formats, so the key is a line in each rather than
# the whole of one.
managed() { grep -q 'X-Omarchyform-Managed=true' -- "$1"; }
entry_version() { sed -n 's/.*X-Omarchyform-Entry-Version=//p' -- "$1" | head -1; }

# A file we wrote, edited since by hand. Distinguished from one we wrote for an
# older version of this plugin, which is an upgrade rather than a conflict:
# that one differs too, but its declared version is behind ours.
locally_modified() {
  [[ $(entry_version "$2") == "$(entry_version "$1")" ]] && ! cmp -s -- "$1" "$2"
}

# Say what is in the way, without touching anything. Prints nothing and
# answers 0 when the file is ours to write; otherwise answers with the exit
# code the whole run should end on.
inspect() {
  local source=$1 target=$2
  [[ -e $target || -L $target ]] || return 0
  if [[ -L $target || ! -f $target ]]; then
    printf 'Refusing to replace %s: it is not a regular file.\n' "$target" >&2
    return 3
  fi
  if [[ $force == false ]] && ! managed "$target"; then
    printf 'Refusing to replace %s: something else is already there.\nInspect it, then pass --force to replace it.\n' "$target" >&2
    return 3
  fi
  if [[ $force == false ]] && locally_modified "$source" "$target"; then
    printf 'Refusing to replace %s: it has local edits.\nKeep them, or pass --force to take the shipped file.\n' "$target" >&2
    return 4
  fi
  return 0
}

# The caches that make a launcher entry appear in a menu and a file type known
# to a file manager. Best effort on purpose: a missing tool is a stale menu,
# not a failed install, and neither command exists in a container.
refresh_caches() {
  command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database -q "$data_home/applications" 2>/dev/null || true
  command -v update-mime-database >/dev/null 2>&1 &&
    update-mime-database "$data_home/mime" 2>/dev/null || true
}

if [[ $uninstall == true ]]; then
  present=false
  status=0
  for row in "${targets[@]}"; do
    IFS='|' read -r name target _ <<< "$row"
    [[ -e $target || -L $target ]] || continue
    present=true
    if [[ -L $target || ! -f $target ]] || ! managed "$target"; then
      printf 'Left alone: %s was not written by this installer.\n' "$target" >&2
      status=3
      continue
    fi
    if [[ $force == false ]] && locally_modified "$source_dir/$name" "$target"; then
      printf 'Left alone: %s has local edits. Remove it yourself, or pass --force.\n' "$target" >&2
      status=4
      continue
    fi
    rm -f -- "$target"
    printf 'Removed %s\n' "$target"
  done
  if [[ $present == false ]]; then
    printf 'Nothing to remove.\n'
    exit 0
  fi
  refresh_caches
  exit "$status"
fi

# Every file inspected before any file is written.
status=0
for row in "${targets[@]}"; do
  IFS='|' read -r name target _ <<< "$row"
  inspect "$source_dir/$name" "$target" || status=$?
done
[[ $status -eq 0 ]] || exit "$status"

for row in "${targets[@]}"; do
  IFS='|' read -r name target mode <<< "$row"
  install -Dm"$mode" -- "$source_dir/$name" "$target"
  printf 'Installed %s\n' "$target"
done
refresh_caches
