#!/usr/bin/env bash
# Local filesystem operations. Paths are data, never shell source.
set -euo pipefail

# Everything this creates is private, whatever umask the shell was started
# with. Files already were — mktemp makes them 0600, and a backup copies that —
# but folders and locks took the umask, and under 000 a new boards folder was
# 0777: any user who could reach it could rename a board out of it or add one.
umask 077

# Put a finished temporary file at its final name, and never over a name that
# is already taken: callers generate unique ones, so a collision is worth
# reporting. The check is explicit because mv -n's exit status for an existing
# destination differs between coreutils versions. Exit 6 says the name was taken.
place_new() {
  local temporary=$1 destination=$2
  [[ ! -e $destination && ! -L $destination ]] || exit 6
  mv -nT -- "$temporary" "$destination"
  [[ ! -e $temporary ]] || exit 6
}

# A picture bigger than this has no business on a board, whichever way it
# arrived: dropped, pasted, or carried inside a shared copy.
max_image_bytes=33554432

# What a picture costs to draw is its pixels, not its bytes, and the two are not
# related: a PNG of one flat colour compresses to almost nothing and still asks
# for four bytes a pixel when it is decoded. Twelve thousand square is a hundred
# and thirty kilobytes on disk and half a gigabyte in memory — under every byte
# limit here, and small enough to travel inside a shared board. Qt's PNG reader
# does not do scaled reading, so nothing downstream can decline to allocate it.
#
# Forty megapixels is past any camera and any panorama worth putting on a board,
# and bounds a decode at about a hundred and sixty megabytes. The per-side limit
# is there because the area alone would let through a one-by-a-hundred-million
# strip.
max_image_pixels=40000000
max_image_side=20000
# Preserve the single-picture allowance, but share it across an import's
# image items. Encoded byte size and viewport visibility are not substitutes.
max_board_image_pixels=40000000
# Each Image also retains file metadata. Count encoded bytes once per item
# rather than once per distinct file; PNG compressed metadata is refused below.
max_board_image_bytes=33554432

# The dimensions, read out of the header. Not out of `file`'s description: that
# is prose, it differs per format, and a JPEG's mentions "density 1x1" before it
# mentions the size. PNG, GIF and BMP each put them at a fixed offset, which is
# exact and needs nothing installed.
#
# JPEG needs a marker walk; WebP puts the canvas in its first image header.
# No raster or compressed metadata is decoded here. Unknown/truncated headers
# answer nothing; the aggregate import check refuses them.
image_pixels() {
  local path=$1 kind=$2
  local -a b
  case "$kind" in
    jpg)
      # Walk length-delimited segments to SOF, never into entropy-coded data.
      # Consume the bounded file even after finding SOF to avoid SIGPIPE under
      # pipefail. Only a handful of header bytes are retained by awk.
      od -An -v -tu1 -w64 -- "$path" | awk '
        BEGIN { state = "ff" }
        { for (i = 1; i <= NF; i++) {
          b = $i + 0
          if (state == "done" || state == "bad") continue
          if (skip > 0) { skip--; continue }
          if (state == "ff") { state = b == 255 ? "marker" : "bad" }
          else if (state == "marker") {
            if (b == 255) continue
            if (b == 216 || b == 1 || (b >= 208 && b <= 215)) { state = "ff"; continue }
            if (b == 0 || b == 217 || b == 218) { state = "bad"; continue }
            sof = b >= 192 && b <= 207 && b != 196 && b != 200 && b != 204
            state = "length1"
          } else if (state == "length1") { size = b * 256; state = "length2" }
          else if (state == "length2") {
            size += b
            if (size < 2 || (sof && size < 8)) { state = "bad"; continue }
            if (sof) { got = 0; state = "frame" }
            else { skip = size - 2; state = "ff" }
          } else if (state == "frame") {
            h[got++] = b
            if (got == 5) { print h[3] * 256 + h[4], h[1] * 256 + h[2]; state = "done" }
          }
        } }'
      ;;
    webp)
      read -ra b < <(od -An -v -tu1 -N30 -- "$path" | tr '\n' ' ') || true
      (( ${#b[@]} >= 25 )) || return 1
      # VP8X extended canvas, VP8L lossless, or VP8 lossy key frame.
      if (( b[12] == 86 && b[13] == 80 && b[14] == 56 && b[15] == 88 && ${#b[@]} == 30 )); then
        printf '%s %s' $((1+b[24]+(b[25]<<8)+(b[26]<<16))) $((1+b[27]+(b[28]<<8)+(b[29]<<16)))
      elif (( b[12] == 86 && b[13] == 80 && b[14] == 56 && b[15] == 76 && b[20] == 47 )); then
        printf '%s %s' $((1+b[21]+((b[22]&63)<<8))) $((1+(b[22]>>6)+(b[23]<<2)+((b[24]&15)<<10)))
      elif (( ${#b[@]} == 30 && b[12] == 86 && b[13] == 80 && b[14] == 56 && b[15] == 32 && (b[20]&1) == 0 && b[23] == 157 && b[24] == 1 && b[25] == 42 )); then
        printf '%s %s' $((b[26]+((b[27]&63)<<8))) $((b[28]+((b[29]&63)<<8)))
      else return 1
      fi
      ;;
    png)
      # IHDR is the first chunk: width then height, big-endian, at offset 16.
      read -ra b < <(od -An -tu1 -j16 -N8 -- "$path" | tr -s ' ')
      (( ${#b[@]} == 8 )) || return 1
      printf '%s %s' $(( (b[0]<<24)|(b[1]<<16)|(b[2]<<8)|b[3] )) \
                     $(( (b[4]<<24)|(b[5]<<16)|(b[6]<<8)|b[7] ))
      ;;
    gif)
      # Logical screen descriptor: width then height, little-endian, offset 6.
      read -ra b < <(od -An -tu1 -j6 -N4 -- "$path" | tr -s ' ')
      (( ${#b[@]} == 4 )) || return 1
      printf '%s %s' $(( b[0]|(b[1]<<8) )) $(( b[2]|(b[3]<<8) ))
      ;;
    bmp)
      # BITMAPINFOHEADER: width then height, little-endian, offset 18. Height
      # is signed — a negative one means the rows are stored top-down — so its
      # two's-complement magnitude is used for top-down pictures.
      read -ra b < <(od -An -tu1 -j18 -N8 -- "$path" | tr -s ' ')
      (( ${#b[@]} == 8 )) || return 1
      printf '%s %s' $(( b[0]|(b[1]<<8)|(b[2]<<16)|(b[3]<<24) )) \
                     $(( (b[7] & 128) ? 4294967296 - (b[4]|(b[5]<<8)|(b[6]<<16)|(b[7]<<24)) : (b[4]|(b[5]<<8)|(b[6]<<16)|(b[7]<<24)) ))
      ;;
    *) return 1 ;;
  esac
}

# Exit 7 is "too many pixels", which is a different thing to say than exit 5 and
# needs saying: the file on disk may be tiny.
refuse_huge_pictures() {
  local dimensions width height
  dimensions=$(image_pixels "$1" "$2") || return 0
  read -r width height <<< "$dimensions"
  (( width > 0 && height > 0 )) || exit 7
  (( width <= max_image_side && height <= max_image_side )) || exit 7
  (( width * height <= max_image_pixels )) || exit 7
}

# What a PNG may ask its reader to inflate, which the pixel count says nothing
# about. Qt keeps the text of every zTXt and compressed iTXt chunk, and libpng
# inflates each to nearly 8 MB and keeps up to a thousand of them, before and
# after the image data: a PNG of a few megabytes, two pixels square, asks the
# shell for gigabytes before a pixel is decoded. Plain tEXt and uncompressed
# iTXt remain bounded by encoded bytes, counted per item during import. iCCP
# colour profiles are compressed too: refuse them (exit 11), rather than let
# tiny encoded profiles bypass that accounting on every repeated image node.
#
# A file without any of these names cannot hold one of these chunks, which is
# every ordinary picture, and that is all it costs. One with the name is walked
# chunk by chunk, so the same four bytes inside the image data are not taken
# for a chunk. The walk is one pass over the bytes, so what it costs is set by
# the file's size, which is already held to max_image_bytes, rather than by how
# many chunks someone packed into it. Exit 9 says the picture carries
# compressed text; a walk that does not reach IEND says the same.
refuse_compressed_text() {
  local path=$1 kind=$2 found=0 verdict
  [[ $kind == png ]] || return 0
  LC_ALL=C grep -q -a -F -e zTXt -e iTXt -e iCCP -- "$path" || found=$?
  (( found != 1 )) || return 0
  (( found == 0 )) || exit 9
  # After the signature: a 4-byte length, a 4-byte name, the data, a 4-byte CRC.
  verdict=$(timeout 30 od -An -v -tu1 -w64 -j8 -- "$path" | awk '
    function decide(answer) { print answer; decided = 1; exit }
    BEGIN { state = "head"; got = 0 }
    {
      for (i = 1; i <= NF; i++) {
        if (state == "skip") {
          # Whole lines at a time: this is where the image data goes by.
          if (skip >= NF - i + 1) { skip -= NF - i + 1; break }
          i += skip; skip = 0; state = "head"
          if (i > NF) break
        }
        b = $i + 0
        if (state == "head") {
          h[got++] = b
          if (got < 8) continue
          got = 0
          size = ((h[0] * 256 + h[1]) * 256 + h[2]) * 256 + h[3]
          name = h[4] " " h[5] " " h[6] " " h[7]
          if (name == "122 84 88 116") decide("compressed")      # zTXt
          if (name == "105 67 67 80") decide("profile")           # iCCP
          if (name == "73 69 78 68") decide("clean")             # IEND
          if (name == "105 84 88 116") { state = "keyword"; left = size; keyword = 0 }  # iTXt
          else { state = "skip"; skip = size + 4 }
        } else if (state == "keyword") {
          # An iTXt keyword is 1 to 79 bytes and a NUL; the flag after it says
          # whether the text is compressed.
          left--
          if (b == 0) { if (keyword < 1 || left < 1) decide("compressed"); state = "flag" }
          else if (++keyword > 79 || left < 1) decide("compressed")
        } else if (state == "flag") {
          left--
          if (b != 0) decide("compressed")
          state = "skip"; skip = left + 4
        }
      }
    }
    # Out of bytes before IEND: cut short, or cut off by the timeout.
    END { if (!decided) print "unfinished" }') || true
  [[ $verdict != profile ]] || exit 11
  [[ $verdict == clean ]] || exit 9
}

# The checks a picture is held to as it lands, for one already in the folder:
# its bytes, its type, its pixels and the compressed text Qt would inflate. In
# a subshell, so a refusal comes back as the answer rather than ending the
# caller, with the exit the landing routes refuse it with.
picture_verdict() (
  size=$(stat -Lc %s -- "$1") || exit 4
  (( size > 0 )) || exit 4
  (( size <= max_image_bytes )) || exit 5
  kind=$(image_extension "$1") || exit 4
  refuse_huge_pictures "$1" "$kind"
  refuse_compressed_text "$1" "$kind"
)

# A name for a picture about to be written, without its extension. The caller
# picks it, and it is still held to the names an image item may carry: no
# slash, no leading dot or dash, nothing a path could be built out of.
plain_name() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

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
# Compatibility entry point for CLI/tests; productive QML uses BoardFileProcess
# directly. Both paths call the same in-process filesystem implementation.
case "$operation" in
  export|publish|move|check|snapshot|revision|filesize|commit|mkdir|private|purge)
    { printf '%s\0' "$operation" "$#"; if (( $# )); then printf '%s\0' "$@"; fi; cat; } |
      python3 "${BASH_SOURCE[0]%/*}/BoardFiles.py"
    exit $?
    ;;
esac
case "$operation" in
  clipimage)
    # The clipboard picks the format; this picks the name and the folder, so
    # nothing the clipboard says can steer where the bytes land. Exit 4 means
    # there is no image on it, which is the caller's cue to try text instead;
    # 9 that the picture carries compressed text (refuse_compressed_text).
    images_root=$1 base_name=$2
    plain_name "$base_name"
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
    read_status=0
    timeout 10 wl-paste --no-newline --type "$mime" | head -c "$((max_image_bytes + 1))" > "$temporary" || read_status=$?
    [[ -s $temporary ]] || exit 4
    # The same limit a dropped file gets. A picture is a picture however it
    # arrived, and the clipboard can hold a screenshot of a 4K desktop.
    size=$(stat -Lc %s -- "$temporary") || exit 4
    (( size <= max_image_bytes )) || exit 5
    (( read_status == 0 )) || exit 8
    extension=$(image_extension "$temporary") || exit 8
    confined "$images_root" "$base_name.$extension"
    refuse_huge_pictures "$temporary" "$extension"
    refuse_compressed_text "$temporary" "$extension"
    place_new "$temporary" "$images_root/$base_name.$extension"
    printf '%s' "$base_name.$extension"
    ;;
  cliptext)
    # Bound the bytes before QML collects stdout. Never return a partial note.
    # Staged in a folder of this user's own, never the shared /tmp: what is on
    # the clipboard is somebody's private text until it is pasted.
    private_dir=$1
    [[ -d $private_dir && -O $private_dir && ! -L $private_dir ]] || exit 3
    temporary=$(mktemp -p "$private_dir" .omarchyform-clip-XXXXXX)
    trap 'rm -f -- "$temporary"' EXIT
    read_status=0
    timeout 3 wl-paste --no-newline --type text | head -c 1048577 > "$temporary" || read_status=$?
    size=$(stat -Lc %s -- "$temporary")
    (( size <= 1048576 )) || exit 5
    (( read_status == 0 )) || exit 4
    cat -- "$temporary"
    ;;
  clipcopy)
    # wl-copy forks and keeps serving the clipboard for as long as it owns it,
    # so this is deliberately not wrapped in a timeout: killing it would take
    # the clipboard contents with it.
    # Inherit the caller's stdin all the way to wl-copy. Neither process may
    # carry private note contents in its command-line arguments.
    (( $# == 0 )) || exit 2
    wl-copy
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
    # copied. Exit 4 means "not an image this can take", 5 means "too large",
    # 9 that it carries compressed text.
    images_root=$1 base_name=$2 source_path=$3
    plain_name "$base_name"
    [[ -f $source_path ]] || exit 4
    size=$(stat -Lc %s -- "$source_path") || exit 4
    (( size > 0 )) || exit 4
    (( size <= max_image_bytes )) || exit 5
    extension=$(image_extension "$source_path") || exit 4
    refuse_huge_pictures "$source_path" "$extension"
    confined "$images_root" "$base_name.$extension"
    temporary=$(mktemp -- "$images_root/.omarchyform-drop-XXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    head -c "$((max_image_bytes + 1))" -- "$source_path" > "$temporary"
    size=$(stat -Lc %s -- "$temporary")
    (( size <= max_image_bytes )) || exit 5
    extension=$(image_extension "$temporary") || exit 4
    confined "$images_root" "$base_name.$extension"
    refuse_huge_pictures "$temporary" "$extension"
    refuse_compressed_text "$temporary" "$extension"
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
    # means the bytes are not a picture, 5 that they are too big for a board,
    # 7 that they decode to more pixels than a board will draw, 9 that they
    # carry compressed text the shell would inflate.
    images_root=$1 staged=$2 base_name=$3
    plain_name "$base_name"
    [[ -f $staged && ! -L $staged ]]
    temporary=$(mktemp -- "$images_root/.omarchyform-shared-XXXXXX")
    trap 'rm -f -- "$temporary" "$staged"' EXIT
    base64 -d -- "$staged" > "$temporary" 2>/dev/null || exit 4
    size=$(stat -Lc %s -- "$temporary") || exit 4
    (( size > 0 )) || exit 4
    (( size <= max_image_bytes )) || exit 5
    extension=$(image_extension "$temporary") || exit 4
    # The path that matters most: this is a picture out of a board somebody
    # else made, and the only one that arrives without anybody choosing it.
    refuse_huge_pictures "$temporary" "$extension"
    refuse_compressed_text "$temporary" "$extension"
    confined "$images_root" "$base_name.$extension"
    place_new "$temporary" "$images_root/$base_name.$extension"
    printf '%s' "$base_name.$extension"
    ;;
  imagebudget)
    # A shared board must fit as a whole before it is published or any Node
    # can load it. Names arrive on stdin once per image ITEM: cache:false means
    # repeated references can retain repeated decodes. Header results are
    # cached only for this check, never the accounting. Foreign history is
    # discarded by the caller before building this list.
    images_root=$1 total=0 total_bytes=0
    declare -A costs=() sizes=()
    while IFS= read -r name || [[ -n $name ]]; do
      plain_name "$name" && confined "$images_root" "$name" || exit 4
      if [[ -z ${costs[$name]+set} ]]; then
        [[ -f $images_root/$name ]] || exit 4
        sizes[$name]=$(stat -Lc %s -- "$images_root/$name") || exit 4
        (( sizes[$name] > 0 && sizes[$name] <= max_image_bytes )) || exit 5
        kind=$(image_extension "$images_root/$name") || exit 4
        dimensions=$(image_pixels "$images_root/$name" "$kind") || exit 10
        read -r width height <<< "$dimensions"
        [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] || exit 10
        (( width > 0 && height > 0 && width <= max_image_side && height <= max_image_side )) || exit 7
        costs[$name]=$((width * height))
      fi
      total=$((total + costs[$name]))
      (( total <= max_board_image_pixels )) || exit 7
      total_bytes=$((total_bytes + sizes[$name]))
      (( total_bytes <= max_board_image_bytes )) || exit 12
    done
    ;;
  checkimages)
    # Pictures already in the folder, asked about before Qt is asked to draw
    # them. The landing routes check what comes in through them; this is for
    # what did not: a picture copied or synced in, or one that landed before
    # a check existed. Names come on stdin, one a line, each with the revision
    # it was last found fit at, if any, and one still at that revision is not
    # read again. Each is answered on a line of its own: the name, then ok,
    # missing, or the exit a landing route would refuse it with (3 for a name
    # or a link no board would draw through), then the revision it was found
    # at. A folder not made yet holds nothing: every name is missing. Nothing
    # is written.
    images_root=$1
    declare -a names=() knowns=() present=()
    declare -A revisions=()
    while IFS=$'\t' read -r name known || [[ -n $name ]]; do
      names+=("$name") knowns+=("$known")
      if plain_name "$name" && [[ ! -L $images_root/$name && -f $images_root/$name ]]; then
        present+=("$images_root/$name")
      fi
    done
    # Every revision in one stat: one process a picture costs more than the
    # check it saves when nothing has changed. A name cannot hold a tab. The
    # change time is in it as well as the modification time: a file rewritten
    # in place at the same size can have its modification time put back, but
    # not its change time.
    if (( ${#present[@]} > 0 )); then
      while IFS=$'\t' read -r path revision; do
        revisions[${path##*/}]=${revision// /}
      done < <(stat -Lc $'%n\t%s|%i|%y|%z' -- "${present[@]}" 2>/dev/null || true)
    fi
    for i in "${!names[@]}"; do
      name=${names[i]} known=${knowns[i]} verdict="" revision=""
      if ! plain_name "$name" || [[ -L $images_root/$name ]]; then verdict=3
      elif [[ -z ${revisions[$name]+set} ]]; then verdict=missing
      else
        revision=${revisions[$name]}
        if [[ -n $known && $known == "$revision" ]]; then verdict=ok
        elif picture_verdict "$images_root/$name"; then verdict=ok
        else verdict=$?
        fi
      fi
      printf '%s\t%s\t%s\n' "$name" "$verdict" "$revision"
    done
    ;;
  *) exit 2 ;;
esac
