#!/usr/bin/env bash
# Local filesystem operations. Paths are data, never shell source.
set -euo pipefail

# Refuse traversal and symlink components below base, including dangling
# symlinks. Base itself may be a symlink (e.g. a boards folder kept in a
# dotfiles repo): it is where the user chose to keep their data.
# Put a finished temporary file at its final name, and never over a name that
# is already taken: callers generate unique ones, so a collision is worth
# reporting. The check is explicit because mv -n's exit status for an existing
# destination differs between coreutils versions. Exit 6 says the name was taken.
place_new() {
  local temporary=$1 destination=$2
  [[ ! -e $destination && ! -L $destination ]] || exit 6
  mv -T -- "$temporary" "$destination"
}

# A picture bigger than this has no business on a board, whichever way it
# arrived: dropped, pasted, or carried inside a shared copy.
max_image_bytes=33554432

# The type comes from the bytes, never from the name: a dropped path and a
# shared board are both somebody else's idea of what a file is called. Exit 4
# is "not an image this can take", which every caller reports as such.
image_extension() {
  case "$(file -bL --mime-type -- "$1")" in
    image/png) printf png ;;
    image/jpeg) printf jpg ;;
    image/webp) printf webp ;;
    image/gif) printf gif ;;
    image/bmp) printf bmp ;;
    *) return 4 ;;
  esac
}

# What a board looked like when someone last read it: size, inode and the
# modification time to the nanosecond. Empty means the file was not there,
# which is a revision like any other — "nothing was here yet".
revision_of() {
  [[ -f $1 ]] || return 0
  # No trailing newline: this is compared against what a caller kept from the
  # last answer, and a newline on one side of that comparison is a false
  # conflict every time.
  printf '%s' "$(stat -Lc '%s|%i|%y' -- "$1" | tr -d ' ')"
}

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
    # The same limit a dropped file gets. A picture is a picture however it
    # arrived, and the clipboard can hold a screenshot of a 4K desktop.
    size=$(stat -Lc %s -- "$temporary") || exit 4
    (( size <= max_image_bytes )) || exit 5
    place_new "$temporary" "$images_root/$base_name.$extension"
    printf '%s' "$base_name.$extension"
    ;;
  clipcopy)
    # wl-copy forks and keeps serving the clipboard for as long as it owns it,
    # so this is deliberately not wrapped in a timeout: killing it would take
    # the clipboard contents with it.
    wl-copy -- "$1"
    ;;
  clipcopyimage)
    # The name comes out of a board file, so it is validated the same way
    # loading one is, and the type is read from the bytes rather than the name.
    images_root=$1 picture=$2
    confined "$images_root" "$picture"
    case "$(file -bL --mime-type -- "$images_root/$picture")" in
      image/*) ;;
      *) exit 4 ;;
    esac
    wl-copy --type "$(file -bL --mime-type -- "$images_root/$picture")" < "$images_root/$picture"
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
    (( size <= max_image_bytes )) || exit 5
    extension=$(image_extension "$source_path") || exit 4
    confined "$images_root" "$base_name.$extension"
    temporary=$(mktemp -- "$images_root/.omarchyform-drop-XXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    cp -- "$source_path" "$temporary"
    place_new "$temporary" "$images_root/$base_name.$extension"
    printf '%s' "$base_name.$extension"
    ;;
  bundleimages)
    # The bytes of every picture on a board, so a copy of it makes sense on a
    # machine that has never seen this one's images folder. base64, because it
    # has to sit inside a JSON file; one line per picture, because assembling
    # JSON in a shell is how a filename becomes a syntax error. A picture that
    # is not there is reported rather than skipped: the board says it has one.
    #
    # The sizes are totalled before anything is encoded, so the answer is either
    # the whole set or none of it. Half a board's pictures is not something the
    # person saving the copy could act on.
    images_root=$1 budget=$2
    shift 2
    total=0
    for name in "$@"; do
      if confined "$images_root" "$name" && [[ -f $images_root/$name && ! -L $images_root/$name ]]; then
        size=$(stat -Lc %s -- "$images_root/$name") || exit 1
        total=$((total + size))
      fi
    done
    if (( total > budget )); then printf '!toolarge\t%s\n' "$total"; exit 0; fi
    for name in "$@"; do
      if confined "$images_root" "$name" && [[ -f $images_root/$name && ! -L $images_root/$name ]]; then
        printf '%s\t' "$name"
        base64 -w0 -- "$images_root/$name"
        printf '\n'
      else
        printf '%s\t!missing\n' "$name"
      fi
    done
    ;;
  unbundleimage)
    # A picture that arrived inside a board. The name it came with is not used
    # for anything: the caller picks the name, the type comes from the decoded
    # bytes, and the size is held to the same limit a dropped file is. Exit 4
    # means the bytes are not a picture, 5 that they are too big for a board.
    images_root=$1 staged=$2 base_name=$3
    [[ $base_name != */* && $base_name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
    [[ -f $staged && ! -L $staged ]]
    temporary=$(mktemp -- "$images_root/.omarchyform-shared-XXXXXX")
    trap 'rm -f -- "$temporary" "$staged"' EXIT
    base64 -d -- "$staged" > "$temporary" 2>/dev/null || exit 4
    size=$(stat -Lc %s -- "$temporary") || exit 4
    (( size > 0 )) || exit 4
    (( size <= max_image_bytes )) || exit 5
    extension=$(image_extension "$temporary") || exit 4
    confined "$images_root" "$base_name.$extension"
    place_new "$temporary" "$images_root/$base_name.$extension"
    printf '%s' "$base_name.$extension"
    ;;
  check)
    # Loading asks first, so a board that could never be saved is not opened.
    # The revision comes back with the answer: what is read now is what the
    # next write will expect to still be there.
    confined "$1" "$2" || exit 3
    revision_of "$1/$2"
    ;;
  revision)
    revision_of "$1"
    ;;
  commit)
    # The one write both ends of a board go through, with the board itself on
    # stdin. Under a lock, and only if the file is still the revision the
    # writer last saw — so two writers that both read the same version cannot
    # both believe they are updating it, and the second is told rather than
    # winning by arriving later.
    #
    # Exit 7 means the file moved underneath, and prints what is there now. The
    # caller still holds what it meant to write; this refuses to guess which of
    # the two versions a person wanted.
    board=$1 backup=$2 lock=$3 expected=$4 root=${5:-} backup_root=${6:-}
    if [[ -n $root ]]; then
      [[ $board == "$root/"* ]] || exit 3
      confined "$root" "${board#"$root/"}" || exit 3
    fi
    if [[ -n $backup_root ]]; then
      [[ $backup == "$backup_root/"* ]] || exit 3
      confined "$backup_root" "${backup#"$backup_root/"}" || exit 3
    fi
    [[ ! -L $board && ! -L $backup && ! -L $backup.tmp ]] || exit 3
    # Staged beside the board it will become: a rename is only atomic within
    # one filesystem, and a boards folder may be a symlink to another.
    mkdir -p -- "$(dirname -- "$board")"
    staged=$(mktemp -- "$(dirname -- "$board")/.omarchyform-XXXXXX")
    # However this ends, the half-written board does not stay in the folder
    # people are invited to read. The caller still holds what it sent.
    trap 'rm -f -- "$staged"' EXIT
    cat > "$staged"
    mkdir -p -- "$(dirname -- "$lock")"
    exec 9>"$lock"
    flock 9
    current=$(revision_of "$board")
    if [[ $expected != "-" && $expected != "$current" ]]; then
      printf '%s' "$current"
      exit 7
    fi
    mkdir -p -- "$(dirname -- "$backup")"
    # The version about to be replaced is kept first, whoever is replacing it.
    if [[ -e $board ]]; then
      cp -T -- "$board" "$backup.tmp"
      mv -fT -- "$backup.tmp" "$backup"
    fi
    mv -fT -- "$staged" "$board"
    revision_of "$board"
    ;;
  check)
    # Loading asks first, so a board that could never be saved is not opened.
    # The revision comes back with the answer: what is read now is what the
    # next write will expect to still be there.
    confined "$1" "$2" || exit 3
    revision_of "$1/$2"
    ;;
  revision)
    revision_of "$1"
    ;;
  commit)
    # The one write both ends of a board go through. Under a lock, and only if
    # the file is still the revision the writer last saw — so two writers that
    # both read the same version cannot both believe they are updating it, and
    # the second one is told rather than winning by arriving later.
    #
    # Exit 7 means the file moved underneath, and prints what is there now. The
    # caller still holds what it meant to write; this refuses to guess which of
    # the two a person wanted.
    board=$1 backup=$2 staged=$3 lock=$4 expected=$5 root=${6:-} backup_root=${7:-}
    [[ -f $staged && ! -L $staged ]]
    if [[ -n $root ]]; then
      [[ $board == "$root/"* ]] || exit 3
      confined "$root" "${board#"$root/"}" || exit 3
    fi
    if [[ -n $backup_root ]]; then
      [[ $backup == "$backup_root/"* ]] || exit 3
      confined "$backup_root" "${backup#"$backup_root/"}" || exit 3
    fi
    [[ ! -L $board && ! -L $backup && ! -L $backup.tmp ]] || exit 3
    # However this ends, the staged content does not stay in the boards folder.
    # The caller still holds it in memory; a half-finished write left lying
    # next to a board is litter in a directory people are invited to read.
    trap 'rm -f -- "$staged"' EXIT
    mkdir -p -- "$(dirname -- "$lock")"
    exec 9>"$lock"
    flock 9
    current=$(revision_of "$board")
    if [[ $expected != "-" && $expected != "$current" ]]; then
      printf '%s' "$current"
      exit 7
    fi
    mkdir -p -- "$(dirname -- "$backup")"
    # The version about to be replaced is kept first, whoever is replacing it.
    if [[ -e $board ]]; then
      cp -T -- "$board" "$backup.tmp"
      mv -fT -- "$backup.tmp" "$backup"
    fi
    # Staged beside the board, so this is a rename on one filesystem: nothing
    # can read half of it, and a reader either sees the old one or the new one.
    mv -fT -- "$staged" "$board"
    revision_of "$board"
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
