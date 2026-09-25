#!/usr/bin/env bash
# Install or remove the launcher entry, and nothing else. The destination is a
# shared directory, so a file there is only replaced or removed once it has
# been established to be one of ours and unmodified since we wrote it. Anything
# else is a concrete conflict, reported and left alone until the user says
# otherwise with --force.
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
entry="$source_dir/omarchyform.desktop"
target="${XDG_DATA_HOME:-$HOME/.local/share}/applications/omarchyform.desktop"

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
managed() { grep -qx 'X-Omarchyform-Managed=true' -- "$1"; }
entry_version() { sed -n 's/^X-Omarchyform-Entry-Version=//p' -- "$1" | head -1; }

# An entry we wrote, edited since by hand. Distinguished from an entry we wrote
# for an older version of this plugin, which is an upgrade rather than a
# conflict: that one differs too, but its declared version is behind ours.
locally_modified() {
  [[ $(entry_version "$target") == "$(entry_version "$entry")" ]] &&
    ! cmp -s -- "$entry" "$target"
}

if [[ $uninstall == true ]]; then
  if [[ ! -e $target && ! -L $target ]]; then
    printf 'Nothing to remove: %s\n' "$target"
    exit 0
  fi
  if [[ -L $target || ! -f $target ]] || ! managed "$target"; then
    printf 'Left alone: %s was not written by this installer.\n' "$target" >&2
    exit 3
  fi
  if [[ $force == false ]] && locally_modified; then
    printf 'Left alone: %s has local edits. Remove it yourself, or pass --force.\n' "$target" >&2
    exit 4
  fi
  rm -f -- "$target"
  printf 'Removed %s\n' "$target"
  exit 0
fi

if [[ -e $target || -L $target ]]; then
  if [[ -L $target || ! -f $target ]]; then
    printf 'Refusing to replace %s: it is not a regular file.\n' "$target" >&2
    exit 3
  fi
  if [[ $force == false ]] && ! managed "$target"; then
    printf 'Refusing to replace %s: another launcher entry already lives there.\nInspect it, then pass --force to replace it.\n' "$target" >&2
    exit 3
  fi
  if [[ $force == false ]] && locally_modified; then
    printf 'Refusing to replace %s: it has local edits.\nKeep them, or pass --force to take the shipped entry.\n' "$target" >&2
    exit 4
  fi
fi

install -Dm644 -- "$entry" "$target"
printf 'Installed %s\n' "$target"
