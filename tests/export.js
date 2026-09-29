// What the export gate is supposed to catch, on pictures built here rather than
// on a desktop: the live smoke test needs a compositor, so until now the only
// thing ever demonstrated about that gate was that it passed. The gate it
// replaces measured ink over the whole exported frame, which two notes fill
// less of the further apart they are — so it failed on a large screen and
// nobody could have told that from watching it pass on a small one.
const assert = require('assert')
const { checkExport } = require('./picture')

// A picture in the shape `read` returns, so the checker cannot tell these from
// a decoded PNG and there is no encoder in the way.
function picture(width, height, canvas) {
  const pixels = Buffer.alloc(width * height * 4)
  for (let i = 0; i < pixels.length; i += 4) {
    pixels[i] = canvas >> 16 & 255
    pixels[i + 1] = canvas >> 8 & 255
    pixels[i + 2] = canvas & 255
    pixels[i + 3] = 255
  }
  return { width, height, channels: 4, pixels }
}

function paint(image, x, y, w, h, colour) {
  for (let py = Math.max(0, Math.round(y)); py < Math.min(image.height, Math.round(y + h)); py++) {
    for (let px = Math.max(0, Math.round(x)); px < Math.min(image.width, Math.round(x + w)); px++) {
      const i = (py * image.width + px) * 4
      image.pixels[i] = colour >> 16 & 255
      image.pixels[i + 1] = colour >> 8 & 255
      image.pixels[i + 2] = colour & 255
    }
  }
}

const CANVAS = 0x0f141c
const TINT = 0x2a3550

// The board the live test exports: two notes in a row with a gap, one connector.
const board = {
  items: [{ id: 1, x: 0, y: 0, w: 240, h: 160 }, { id: 2, x: 400, y: 0, w: 300, h: 200 }],
  links: [{ from: 1, to: 2 }]
}
const FRAME = { w: 764, h: 264 }

// Renders that board the way BoardImage does, at a scale the caller picks, with
// each part optional so a part can be left out and the gate asked about it.
function render(scale, { items = [1, 2], connector = true, offset = 0 } = {}) {
  const image = picture(Math.ceil(FRAME.w * scale), Math.ceil(FRAME.h * scale), CANVAS)
  for (const item of board.items) {
    if (!items.includes(item.id)) continue
    paint(image, (item.x + 32 + offset) * scale, (item.y + 32 + offset) * scale,
          item.w * scale, item.h * scale, TINT)
  }
  if (connector) {
    // Centre to centre, a couple of pixels thick, like the canvas draws it.
    const a = board.items[0], b = board.items[1]
    const ax = a.x + a.w / 2, ay = a.y + a.h / 2, bx = b.x + b.w / 2, by = b.y + b.h / 2
    for (let t = 0; t <= 1; t += 0.001)
      paint(image, (ax + (bx - ax) * t + 32) * scale, (ay + (by - ay) * t + 32) * scale,
            1.5 * scale, 1.5 * scale, 0xe0e0e0)
  }
  return image
}

// A whole board, at three scales: 1, the 1.6 a fractional display scale
// produces, and the 0.3 the 4096 clamp produces for a very large board. The
// gate reads the scale back out of the picture, so none of them is special.
for (const scale of [1, 1.6, 0.3])
  assert.deepStrictEqual(checkExport(render(scale), board), [],
    `a complete export passes at scale ${scale}`)

// The fault the gate exists for: an item culled out of the picture. It draws
// nothing and the frame is still exactly the right size.
const culled = checkExport(render(1.6, { items: [1] }), board)
assert.strictEqual(culled.length, 1, `one fault for one missing note: ${culled}`)
// Not quite 0%: the connector is drawn centre to centre here, so it clips the
// corner of the rectangle it points at. Nowhere near the 90% a note that drew
// itself reads, which is the whole reason there is no threshold to argue about.
assert.match(culled[0], /item 2 is 0\.\d% inked/)

const neither = checkExport(render(1.6, { items: [] }), board)
assert.strictEqual(neither.length, 2, `a fault per missing note: ${neither}`)

// The connector is drawn by a Canvas the items know nothing about, so it can go
// missing on its own.
const unlinked = checkExport(render(1.6, { connector: false }), board)
assert.deepStrictEqual(unlinked.length, 1, `the missing connector, and only it: ${unlinked}`)
assert.match(unlinked[0], /nothing is drawn between items 1 and 2/)

// A frame that does not line up with the bounds it claims to be. Both notes
// drew, so nothing is missing; what is wrong is where the padding put them, and
// the rectangles no longer land on them. Shifted away from the origin the notes
// themselves report it; shifted towards it they spill into the padding, which is
// outside the board's bounds by construction and should never carry ink.
const shifted = checkExport(render(1.6, { offset: 40 }), board)
assert.strictEqual(shifted.length, 2, `an offset frame is caught: ${shifted}`)
assert.ok(shifted.every(p => /did not render/.test(p)), String(shifted))

const spilled = checkExport(render(1.6, { offset: -40 }), board)
assert.ok(spilled.some(p => /padding is inked/.test(p)), `ink outside the bounds is caught: ${spilled}`)

// And a picture whose aspect is not the frame's at all, which is named as the
// frame's fault rather than blamed on the items.
const wrong = checkExport(picture(400, 900, CANVAS), board)
assert.strictEqual(wrong.length, 1)
assert.match(wrong[0], /not the board's bounds plus padding/)

// The old gate, for the record: the same complete picture, scored the way it
// used to be. The board covers 49% of this frame, but the frame was the board's
// bounds and the second note landed at the centre of the view, so on the screen
// this test actually runs on the two notes fell 728px apart and the same
// complete export scored 16% against a threshold of 20%.
// The whole-frame score the old gate used, which is what `inked` says about
// the whole picture rather than about one item's rectangle. Kept as a
// measurement rather than as an API: nothing needs this number except the
// argument below for why it was the wrong one.
const { canvasColour, inked: ink } = require('./png')
const whole = image => ink(image, { x: 0, y: 0, w: image.width, h: image.height },
                           canvasColour(image))

const complete = whole(render(1.6))
assert.ok(complete > 0.2, 'the pinned board would pass even the old whole-frame gate')
const sparse = { items: [board.items[0], { id: 2, x: 2000, y: 1400, w: 300, h: 200 }], links: [] }
const wide = picture(Math.ceil((2300 + 64) * 1.6), Math.ceil((1600 + 64) * 1.6), CANVAS)
for (const item of sparse.items)
  paint(wide, (item.x + 32) * 1.6, (item.y + 32) * 1.6, item.w * 1.6, item.h * 1.6, TINT)
assert.ok(whole(wide) < 0.2,
  'a board spread out by a big screen fails a whole-frame threshold')
assert.deepStrictEqual(checkExport(wide, sparse), [],
  'and passes this one, because where the notes are is not what is being asked')

console.log('ok — exported picture gate (' + (complete * 100).toFixed(0) + '% of the pinned frame is inked)')
