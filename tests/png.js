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

// The fraction of the picture that is not its most common colour — how much
// of it has anything on it at all. Geometry rather than palette: how much of
// the frame the items cover barely moves between themes, while how many
// distinct colours they are drawn in moves a great deal.
function coverage(file) {
  const image = read(file)
  const counts = new Map()
  for (let i = 0; i < image.pixels.length; i += image.channels) {
    const key = (image.pixels[i] << 16) | (image.pixels[i + 1] << 8) | image.pixels[i + 2]
    counts.set(key, (counts.get(key) || 0) + 1)
  }
  let commonest = 0
  for (const n of counts.values()) if (n > commonest) commonest = n
  const total = image.width * image.height
  return total ? (total - commonest) / total : 0
}

module.exports = { read, coverage }
