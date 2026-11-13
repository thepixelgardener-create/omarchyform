#!/usr/bin/env node
// `omarchyform render`: a picture of a board from the command line, read back
// pixel by pixel. "It answered ok" was the one thing an export that drew
// nothing always said, so the file is what is checked.
//
// What it refuses needs nothing but node and is checked everywhere. Drawing
// needs Quickshell, which an Omarchy machine has and a plain container does
// not: without it that half says it was skipped, and under OMARCHYFORM_STRICT
// its absence fails.
const fs = require('fs')
const os = require('os')
const path = require('path')
const assert = require('assert/strict')
const { spawnSync } = require('child_process')
const { read, write } = require('./png')
const S = require('../bin/store').loadStore()

const cli = path.join(__dirname, '..', 'bin', 'omarchyform')
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-render-'))
const home = path.join(dir, 'home')
const library = path.join(home, '.local/share/omarchyform')
const env = { ...process.env, HOME: home }

function run(args, withEnv) {
  const out = spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8', input: '', env: withEnv || env, timeout: 120000 })
  let parsed = null
  try { parsed = JSON.parse(out.stdout) } catch { /* reported by the caller */ }
  return { status: out.status, out: parsed, raw: out.stdout + out.stderr }
}
const item = (id, kind, x, y, extra) => Object.assign({ id, kind, x, y, w: 220, h: 160,
  tint: 'foreground', text: '', pinned: false, src: '' }, extra)
function boardFile(name, items, links) {
  const file = path.join(dir, name)
  fs.writeFileSync(file, JSON.stringify({ kind: 'omarchyform.board', version: 5, nextId: items.length + 1, items, links: links || [] }))
  return file
}
const hex = colour => parseInt(colour.slice(1), 16)
function pixel(image, x, y) {
  const i = (y * image.width + x) * image.channels
  return (image.pixels[i] << 16) | (image.pixels[i + 1] << 8) | image.pixels[i + 2]
}
function refused(what, args, error, withEnv) {
  const out = run(args, withEnv)
  assert.equal(out.status, 1, what + ' exits 1: ' + out.raw)
  assert.ok(out.out && out.out.ok === false, what + ' answers with JSON: ' + out.raw)
  assert.match(out.out.error, error, what)
}

// `--hostile`: every board tests/hostile-fixtures.js makes, each at a bound a
// board is held to or just past it, drawn from the command line. One the
// board opens has to come out as a picture within the time; one it opens
// empty and read-only, or cannot read, has to be refused. The scene runs in a
// process of its own, so nothing here can hold the shell: what this guards is
// a command that never answers, and a stage left behind when it does not.
// Part of `npm run test:hostile`. The slowest, 5,000 notes with long
// previews, took 24 seconds when this was written (2026-11-13).
function hostile() {
  const { fixtures } = require('./hostile-fixtures')
  const limit = 60000 * Number(process.env.OMARCHYFORM_HOSTILE_SCALE || 1)
  const over = []
  for (const f of fixtures) {
    const file = path.join(dir, f.name + '.json'), picture = path.join(dir, f.name + '.png')
    fs.writeFileSync(file, f.text())
    const started = Date.now()
    const out = run(['render', file, picture])
    const took = Date.now() - started
    if (f.opens) {
      assert.equal(out.status, 0, f.name + ' is drawn: ' + out.raw.slice(0, 300))
      const image = read(picture)
      assert.ok(image.width >= 1 && image.width <= 4096 && image.height >= 1 && image.height <= 4096,
        `${f.name}: a picture is at most 4096 on a side, not ${image.width} by ${image.height}`)
      if (took > limit) over.push(`${f.name} took ${took} ms`)
    } else {
      assert.equal(out.status, 1, f.name + ' is refused')
      assert.ok(out.out && out.out.ok === false, f.name + ' is refused as JSON: ' + out.raw.slice(0, 300))
      assert.equal(fs.existsSync(picture), false, f.name + ' leaves no picture')
    }
    assert.deepEqual(fs.readdirSync(path.join(library, 'render')), [], f.name + ' leaves nothing staged')
    fs.rmSync(file); fs.rmSync(picture, { force: true })
    console.log(`  ${f.name}: ${f.opens ? 'drawn' : 'refused'} in ${took} ms`)
  }
  assert.deepEqual(over, [], `drawn, but slower than ${limit} ms`)
  console.log(`ok — render: ${fixtures.length} hostile boards drawn or refused, none left staged`)
}

try {
  fs.mkdirSync(home)
  if (process.argv.includes('--hostile')) {
    if (spawnSync('qs', ['--version'], { encoding: 'utf8' }).error) { console.error('quickshell (qs) is required here'); process.exit(1) }
    hostile()
    process.exit(0)
  }
  // Two boxes in a row, an accent and an urgent one, joined; the frame an
  // export puts round a board is its bounds and 32 pixels on every side.
  const two = boardFile('two.json', [item(1, 'rect', 0, 0, { tint: 'accent' }), item(2, 'rect', 400, 0, { tint: 'urgent' })],
    [{ from: 1, to: 2 }])
  const picture = path.join(dir, 'two.png')

  {
    refused('no picture named', ['render', two], /needs a board and a picture/)
    refused('no board named', ['render'], /needs a board and a picture/)
    refused('a picture that is not a PNG', ['render', two, path.join(dir, 'two.jpg')], /is a PNG/)
    refused('the board as its own picture', ['render', path.join(dir, 'board.png'), path.join(dir, 'board.png')], /over the board/)
    refused('a palette there is not', ['render', two, picture, '--colors', 'sepia'], /no palette sepia/)
    refused('a palette left out', ['render', two, picture, '--colors'], /needs a palette/)
    refused('an item there is not', ['render', two, picture, '--only', '7'], /no item 7/)
    refused('an id that is not one', ['render', two, picture, '--only', '1,x'], /takes ids/)
    refused('a flag there is not', ['render', two, picture, '--colours', 'dark'], /no flag --colours/)
    refused('a board with nothing on it', ['render', boardFile('empty.json', []), picture], /nothing on the board/)
    refused('a file that is not a board', ['render', cli, picture], /not a board/)
    // A board the plugin opens empty and read-only is not drawn from here.
    const crowd = []
    for (let i = 0; i <= S.MAX_ITEMS; i++) crowd.push(item(i + 1, 'note', i * 10, 0))
    refused('a board past the item limit', ['render', boardFile('crowd.json', crowd), picture], /has more than 5,000 items/)
    fs.writeFileSync(picture, 'mine')
    refused('a picture already there', ['render', two, picture], /exists/)
    assert.equal(fs.readFileSync(picture, 'utf8'), 'mine', 'and it is left as it was')
    fs.rmSync(picture)
    assert.equal(fs.existsSync(path.join(library, 'render')), false, 'a refusal stages nothing')

    // Without Quickshell the answer is still JSON and says what is missing.
    const bare = fs.mkdtempSync(path.join(dir, 'path-'))
    for (const tool of ['python3', 'bash', 'stat']) {
      const found = spawnSync('which', [tool], { encoding: 'utf8' }).stdout.trim()
      if (found) fs.symlinkSync(found, path.join(bare, tool))
    }
    refused('a machine without Quickshell', ['render', two, picture], /quickshell \(qs\) not found/, { ...env, PATH: bare })
    assert.equal(fs.existsSync(picture), false, 'nothing is written')
    assert.deepEqual(fs.readdirSync(path.join(library, 'render')), [], 'and the staging folder is empty again')
    console.log('ok — render: what it will not draw is refused by name, as JSON, with nothing written')
  }

  const qs = spawnSync('qs', ['--version'], { encoding: 'utf8' })
  if (qs.error) {
    if (process.env.OMARCHYFORM_STRICT) { console.error('quickshell (qs) is required here'); process.exit(1) }
    console.log('skipped: drawing a picture needs quickshell (qs)')
  } else {
    const light = S.EXPORT_PALETTES.light, dark = S.EXPORT_PALETTES.dark
    {
      const out = run(['render', two, picture])
      assert.equal(out.status, 0, out.raw)
      assert.deepEqual([out.out.file, out.out.width, out.out.height, out.out.colors, out.out.items],
        [picture, 620 + 64, 160 + 64, 'light', 2])
      const image = read(picture)
      assert.deepEqual([image.width, image.height], [684, 224], 'the file is the size it was said to be')
      assert.equal(pixel(image, 4, 4), hex(light.background), 'the page')
      assert.equal(pixel(image, 32 + 110, 32 + 80), hex(light.fills.accent), 'the first box, in its role')
      assert.equal(pixel(image, 32 + 400 + 110, 32 + 80), hex(light.fills.urgent), 'the second')
      // The connector runs level between them, at the height of their middles.
      const span = []
      for (let y = 32 + 70; y < 32 + 90; y++) span.push(pixel(image, 32 + 300, y))
      assert.ok(span.some(colour => colour !== hex(light.background)), 'and the connector between them')
      assert.equal(fs.statSync(path.join(library, 'render')).mode & 0o777, 0o700, 'the staging folder is private')
      assert.deepEqual(fs.readdirSync(path.join(library, 'render')), [], 'and empty once the picture is out')
      console.log('ok — render: a board is drawn to the file, in its roles, with its connector')
    }
    {
      const again = run(['render', two, picture, '--force', '--colors', 'dark', '--only', '2'])
      assert.equal(again.status, 0, again.raw)
      assert.deepEqual([again.out.width, again.out.height, again.out.items], [220 + 64, 160 + 64, 1])
      const image = read(picture)
      assert.equal(pixel(image, 4, 4), hex(dark.background), 'another palette')
      assert.equal(pixel(image, 32 + 110, 32 + 80), hex(dark.fills.urgent), 'and only the item asked for, framed on its own')
      console.log('ok — render: --colors and --only choose the palette and what is in the frame')
    }
    {
      // Pictures are opened only once the helper has found them fit, as in the
      // shell: one that is there is drawn, and one that is missing or reached
      // through a link is named with the reason and drawn as a missing one.
      const images = path.join(library, 'images')
      fs.mkdirSync(images, { recursive: true })
      write(path.join(images, 'red.png'), 200, 150, 0xd02828)
      fs.symlinkSync(path.join(images, 'red.png'), path.join(images, 'link.png'))
      const pictures = boardFile('pictures.json', [
        item(1, 'image', 0, 0, { w: 200, h: 150, src: 'red.png' }),
        item(2, 'image', 300, 0, { w: 200, h: 150, src: 'gone.png' }),
        item(3, 'image', 600, 0, { w: 200, h: 150, src: 'link.png' })])
      const out = run(['render', pictures, picture, '--force'])
      assert.equal(out.status, 0, out.raw)
      assert.deepEqual(out.out.picturesLeftOut, [
        { name: 'gone.png', why: 'missing' },
        { name: 'link.png', why: 'is a link, which a board does not follow' }])
      const image = read(picture)
      const red = pixel(image, 32 + 100, 32 + 75)
      assert.ok((red >> 16) > 180 && (red >> 8 & 255) < 80 && (red & 255) < 80, 'the picture that is there is in the file, not ' + red.toString(16))
      for (const x of [300, 600]) {
        const left = pixel(image, 32 + x + 100, 32 + 20)
        assert.ok(!((left >> 16) > 180 && (left >> 8 & 255) < 80), 'and one not found fit is not opened')
      }
      console.log('ok — render: a picture is drawn once checked, and one left out is named with the reason')
    }
    {
      // A run killed before it cleared up leaves its stage; the next run
      // clears one too old to be a run still going, and leaves a fresh one.
      const stale = path.join(library, 'render', 'job-stale'), fresh = path.join(library, 'render', 'job-fresh')
      fs.mkdirSync(stale); fs.mkdirSync(fresh)
      fs.writeFileSync(path.join(stale, 'board.json'), 'left behind')
      const long = new Date(Date.now() - 3600 * 1000)
      fs.utimesSync(stale, long, long)
      assert.equal(run(['render', two, picture, '--force']).status, 0)
      assert.deepEqual(fs.readdirSync(path.join(library, 'render')), ['job-fresh'])
      console.log('ok — render: a stage left by a run that was killed is cleared by the next')
    }
  }
} finally {
  fs.rmSync(dir, { recursive: true, force: true })
}
