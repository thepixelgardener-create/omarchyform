// Real compact PNGs with correct CRCs and raster streams, generated without
// ever asking Qt/the shared shell to decode an over-budget board.
const zlib = require('zlib')
function chunk(type, data) {
  const name = Buffer.from(type), body = Buffer.concat([name, data])
  let crc = 0xffffffff
  for (const byte of body) {
    crc ^= byte
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0)
  }
  const size = Buffer.alloc(4), check = Buffer.alloc(4)
  size.writeUInt32BE(data.length); check.writeUInt32BE((crc ^ 0xffffffff) >>> 0)
  return Buffer.concat([size, body, check])
}
function solidPng(width, height) {
  const header = Buffer.alloc(13)
  header.writeUInt32BE(width); header.writeUInt32BE(height, 4)
  header[8] = 1 // one-bit grayscale, expanded by Qt when drawn
  return Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', header),
    chunk('IDAT', zlib.deflateSync(Buffer.alloc((Math.ceil(width / 8) + 1) * height))), chunk('IEND', Buffer.alloc(0))])
}
function withChunk(type, data) {
  const png = solidPng(1, 1)
  return Buffer.concat([png.subarray(0, 33), chunk(type, data), png.subarray(33)])
}
module.exports = { solidPng, withChunk }
