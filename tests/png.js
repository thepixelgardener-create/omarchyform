// Just enough PNG to look at a picture the plugin produced. Node ships zlib,
// so this needs nothing installed, which is the property the rest of the suite
// is built on.
//
// It exists because "the export succeeded" and "the export has the board in
// it" are different claims, and only the first one was ever checked. An item
// that draws itself as nothing still exports at the right size.
const fs = require('fs')
const zlib = require('zlib')

const CHANNELS = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }

function read(file) {
  const data = fs.readFileSync(file)
  if (data.readUInt32BE(0) !== 0x89504e47) throw new Error(file + ' is not a PNG')
  let at = 8
  let header = null
  const parts = []
  while (at < data.length) {
    const length = data.readUInt32BE(at)
    const type = data.toString('ascii', at + 4, at + 8)
    if (type === 'IHDR') {
      header = { width: data.readUInt32BE(at + 8), height: data.readUInt32BE(at + 12),
                 depth: data[at + 16], colorType: data[at + 17] }
    } else if (type === 'IDAT') parts.push(data.subarray(at + 8, at + 8 + length))
    at += 12 + length
  }
  if (!header) throw new Error(file + ' has no header')
  if (header.depth !== 8) throw new Error(file + ' is not 8 bits per channel')
  const channels = CHANNELS[header.colorType]
  if (!channels) throw new Error(file + ' has an unsupported colour type')

  // Undo the per-row filters. Straight from the spec; the only surprise is
  // that byte `a` is the pixel to the left, not the byte to the left.
  const raw = zlib.inflateSync(Buffer.concat(parts))
  const stride = header.width * channels
  const out = Buffer.alloc(stride * header.height)
  let source = 0
  for (let y = 0; y < header.height; y++) {
    const filter = raw[source++]
    const row = y * stride
    const above = row - stride
    for (let x = 0; x < stride; x++) {
      const value = raw[source + x]
      const a = x >= channels ? out[row + x - channels] : 0
      const b = y > 0 ? out[above + x] : 0
      const c = x >= channels && y > 0 ? out[above + x - channels] : 0
      let add = 0
      if (filter === 1) add = a
      else if (filter === 2) add = b
      else if (filter === 3) add = (a + b) >> 1
      else if (filter === 4) {
        const p = a + b - c
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c)
        add = pa <= pb && pa <= pc ? a : pb <= pc ? b : c
      }
      out[row + x] = (value + add) & 255
    }
    source += stride
  }
  return { width: header.width, height: header.height, channels, pixels: out }
}

function rgb(image, x, y) {
  const i = (y * image.width + x) * image.channels
  return (image.pixels[i] << 16) | (image.pixels[i + 1] << 8) | image.pixels[i + 2]
}

// The colour the canvas was painted, taken as the commonest in the whole
// picture: an export is the board's bounds plus padding on every side, so the
// canvas outnumbers anything drawn on it, and reading it from the picture
// rather than naming one keeps this working in any theme.
//
// Deliberately not the corner, even though the corner is canvas too. A check
// that the padding carries no ink cannot define the canvas as the colour of
// the padding — it would be asking whether the corner matches itself, and a
// picture whose frame has slipped far enough for the items to spill into the
// corner would sail through it. tests/export.js has that case.
function canvasColour(source) {
  const image = typeof source === 'string' ? read(source) : source
  const counts = new Map()
  for (let i = 0; i < image.pixels.length; i += image.channels) {
    const key = (image.pixels[i] << 16) | (image.pixels[i + 1] << 8) | image.pixels[i + 2]
    counts.set(key, (counts.get(key) || 0) + 1)
  }
  let colour = 0
  let commonest = 0
  for (const [key, n] of counts) if (n > commonest) { commonest = n; colour = key }
  return colour
}

// What the picture came out on, as it would be written down — which is the
// one thing a palette changes that no count of ink can see, since the same
// board covers the same fraction of the frame whatever it is drawn in.
//
// The corner rather than the commonest colour, because this is also asked of
// a picture framed around a single item, where the commonest colour is that
// item's own fill. A corner of the padding is the page by construction. Read
// as the commonest colour in a small block so one stray edge pixel cannot
// answer for it.
function paper(source, inset) {
  const image = typeof source === 'string' ? read(source) : source
  const span = Math.max(1, Math.min(inset === undefined ? 12 : inset, image.width, image.height))
  const counts = new Map()
  for (let y = 0; y < span; y++)
    for (let x = 0; x < span; x++) {
      const key = rgb(image, x, y)
      counts.set(key, (counts.get(key) || 0) + 1)
    }
  let colour = 0
  let commonest = 0
  for (const [key, n] of counts) if (n > commonest) { commonest = n; colour = key }
  return '#' + colour.toString(16).padStart(6, '0')
}

// The fraction of one rectangle that is not the background colour. Asked about
// the rectangle an item occupies this is close to all or nothing, because a
// note fills its own rectangle with its tint blended into the canvas: an item
// that drew reads ~1 and an item culled out of the picture reads 0, with no
// threshold in between to tune. Asked about a rectangle nothing should have
// drawn into, it says whether the measurement means anything at all.
//
// The rectangle is in pixels and is clipped to the picture; a rectangle that
// falls entirely outside it has nothing to measure and reads 0.
function inked(image, rect, colour) {
  const x0 = Math.max(0, Math.round(rect.x))
  const y0 = Math.max(0, Math.round(rect.y))
  const x1 = Math.min(image.width, Math.round(rect.x + rect.w))
  const y1 = Math.min(image.height, Math.round(rect.y + rect.h))
  let on = 0
  let total = 0
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      total++
      if (rgb(image, x, y) !== colour) on++
    }
  }
  return total ? on / total : 0
}

module.exports = { read, canvasColour, paper, inked }
