// Is the board in the picture? "The export succeeded" and "the export has the
// board in it" are different claims, and an item culled by mistake draws
// nothing while still exporting at exactly the right size, so neither the file
// existing nor its dimensions would notice.
//
// This asks of each item's own rectangle rather than of the whole frame. A note
// fills its rectangle with its tint blended into the canvas, so a note that
// drew reads ~100% and a note that was culled reads 0%, with no threshold in
// between to tune — and the frame those rectangles sit in may be any size. A
// fraction of the whole frame cannot do that: the frame is the board's bounds
// plus padding, so how much of it two notes cover depends on how far apart they
// are, and the gate that measured it was really measuring the screen the test
// happened to run on.
//
// Takes a decoded picture and a parsed board rather than two paths, so the
// cases below can be built in memory without a desktop or a PNG encoder.
const { canvasColour, inked } = require('./png')

function bounds(items) {
  const b = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity }
  for (const item of items) {
    b.minX = Math.min(b.minX, item.x)
    b.minY = Math.min(b.minY, item.y)
    b.maxX = Math.max(b.maxX, item.x + item.w)
    b.maxY = Math.max(b.maxY, item.y + item.h)
  }
  return b
}

// The board written to disk is the board the picture was rendered from, so the
// rectangles to look in are read from it rather than repeated here: there is
// nothing to keep in step.
//
// BoardImage frames the bounds with 32px of padding and scales the result down
// to fit 4096, and the grab then scales again by the display's device pixel
// ratio. Neither factor is knowable from here and neither needs to be: the
// picture's size over the frame's size is their product.
function checkExport(picture, board) {
  const items = (board && board.items) || []
  if (!items.length) return ['the exported board has no items to look for']
  const { minX, minY, maxX, maxY } = bounds(items)
  const frameW = maxX - minX + 64
  const frameH = maxY - minY + 64
  const scaleX = picture.width / frameW
  const scaleY = picture.height / frameH
  // Rounding up to whole pixels twice moves these apart by a fraction of a
  // percent. Further apart than that and the frame is not the board's bounds,
  // so every rectangle below would be looking in the wrong place and saying so
  // about the items would name the wrong fault.
  if (Math.abs(scaleX - scaleY) / scaleX > 0.01)
    return [`exported PNG is ${picture.width}x${picture.height} for a ${frameW}x${frameH} `
      + 'frame: that is not the board\'s bounds plus padding']

  const box = (x, y, w, h) => ({ x: (x - minX + 32) * scaleX, y: (y - minY + 32) * scaleY,
                                 w: w * scaleX, h: h * scaleY })
  const canvas = canvasColour(picture)
  const problems = []

  for (const item of items) {
    const filled = inked(picture, box(item.x, item.y, item.w, item.h), canvas)
    if (filled < 0.9)
      problems.push(`item ${item.id} is ${(filled * 100).toFixed(1)}% inked inside its own `
        + 'rectangle: it did not render into the export')
  }

  // A connector is a 1.5px line, so this asks whether anything is there at all
  // rather than how much. The board is placed with a gap between the two notes,
  // so the halfway point between their centres is open canvas and nothing but
  // the line can account for ink there.
  const byId = {}
  for (const item of items) byId[item.id] = item
  for (const link of board.links || []) {
    const a = byId[link.from]
    const b = byId[link.to]
    if (!a || !b) { problems.push(`connector ${link.from}->${link.to} has no items`); continue }
    const midX = (a.x + a.w / 2 + b.x + b.w / 2) / 2
    const midY = (a.y + a.h / 2 + b.y + b.h / 2) / 2
    if (inked(picture, box(midX - 20, midY - 20, 40, 40), canvas) <= 0)
      problems.push(`nothing is drawn between items ${link.from} and ${link.to}: `
        + 'the connector did not render into the export')
  }

  // And a corner of the padding, which is outside the board's bounds by
  // construction. Ink there means the frame is offset or the canvas was
  // repainted, and "not the background colour" was never about the items.
  const corner = inked(picture, { x: 0, y: 0, w: 24 * scaleX, h: 24 * scaleY }, canvas)
  if (corner > 0.02)
    problems.push(`${(corner * 100).toFixed(1)}% of the export's padding is inked: `
      + 'the frame does not line up with the board')

  return problems
}

module.exports = { checkExport }
