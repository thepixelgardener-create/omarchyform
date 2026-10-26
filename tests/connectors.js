#!/usr/bin/env node
// What connectors cost while a board is in use: panned, zoomed, selected
// through and dragged, at 300, 3,000 and 20,000 connectors. Measure here
// before and after changing how connectors are drawn; test:hostile only
// times a board opening.
//
//   node tests/connectors.js                    every board
//   node tests/connectors.js max-links          the ones named
//   node tests/connectors.js --frames 20        steps per phase (default 12)
//   node tests/connectors.js --json             one JSON line per board
//   node tests/connectors.js --pan              a small board panned, at scale 1 and 2
//
// Offscreen with Qt's software renderer, like test:hostile, so it opens
// nothing on the desktop and runs while the displays are off. The connector
// canvas is rasterised by QPainter on the CPU on the desktop as well, so the
// split between script and raster carries over; whole frame times do not.
//
// A diagnostic, not a pass/fail gate, and not in npm test or CI: a run takes
// minutes, and the numbers are this machine's. Compare runs made back to back.
// See docs/performance.md for what it measured and the targets proposed.
const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')
const S = require('../bin/store').loadStore()
const { provenance } = require('./machine')

const runner = process.env.QMLTESTRUNNER || '/usr/lib/qt6/bin/qmltestrunner'
const generated = path.join(__dirname, 'connectors/generated')

const note = (id, x, y) => ({ id, kind: 'note', x, y, w: 200, h: 150, tint: 'foreground',
  text: 'note ' + id, pinned: false, src: '' })
const board = (items, links) => JSON.stringify({ kind: 'omarchyform.board', version: 5,
  nextId: items.length + 1, items, links }) + '\n'
const spread = count => {
  const cols = Math.ceil(Math.sqrt(count))
  return Array.from({ length: count }, (_, i) => note(i + 1, (i % cols) * 260, Math.floor(i / cols) * 200))
}
// Each note to the next: a board of steps, a few connectors in view at 100%.
const chain = count => {
  const items = spread(count)
  return board(items, items.slice(1).map(n => ({ from: n.id - 1, to: n.id })))
}

const boards = [
  { name: 'chain-300', text: () => chain(300) },
  { name: 'chain-3000', text: () => chain(3000) },
  // The most connectors on the most items, each note joined to the ones right,
  // below and diagonally below it, then two along, until the limit: most of
  // them off screen at 100%, a few thousand in view at 20%.
  { name: 'mesh-20000', text: () => {
    const items = spread(S.MAX_ITEMS)
    const cols = Math.ceil(Math.sqrt(S.MAX_ITEMS))
    const links = []
    const join = (a, b) => { if (links.length < S.MAX_LINKS) links.push({ from: a + 1, to: b + 1 }) }
    for (const offset of [[1, 0], [0, 1], [1, 1], [-1, 1], [2, 0]])
      for (let i = 0; i < S.MAX_ITEMS; i++) {
        const x = i % cols + offset[0], y = Math.floor(i / cols) + offset[1]
        if (x >= 0 && x < cols && y * cols + x < S.MAX_ITEMS) join(i, y * cols + x)
      }
    return board(items, links)
  } },
  // Every pair of 201 notes packed on one screen, as tests/hostile-fixtures.js
  // has it: the limit, all of it in view at once.
  { name: 'max-links', text: () => require('./hostile-fixtures').fixtures.find(f => f.name === 'max-links').text() }
]

const args = process.argv.slice(2)
const json = args.includes('--json')

// --pan: a small board panned instead, at scale 1 and 2 (tests/connectors/
// tst_panning.qml). A canvas costs its pixels, not what is on it, so this is
// the window size and the scale rather than the board.
if (args.includes('--pan')) {
  let failed = false
  if (!json) {
    for (const [label, value] of provenance(false)) console.log(`${label.padEnd(15)}  ${value}`)
    console.log('\nms, median/worst of 20 steps; paints: canvases drawn during them\n')
  }
  for (const scale of ['1', '2']) {
    const result = spawnSync(runner, ['-input', path.join(__dirname, 'connectors/tst_panning.qml')], {
      encoding: 'utf8', timeout: 600000,
      env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: '', QT_QUICK_BACKEND: 'software',
        QT_QUICK_CONTROLS_STYLE: 'Basic', QT_SCALE_FACTOR: scale } })
    const output = (result.stdout || '') + (result.stderr || '')
    const line = output.split('\n').find(l => l.includes('PANNING '))
    if (!line || result.status !== 0) {
      console.error(`scale ${scale}: the run failed\n` + output.split('\n').slice(-30).join('\n'))
      failed = true
      continue
    }
    for (const row of JSON.parse(line.slice(line.indexOf('PANNING ') + 8))) {
      if (json) { console.log(JSON.stringify(row)); continue }
      const cell = v => `${v.median}/${v.worst} (${v.paints})`.padEnd(16)
      console.log(`scale ${row.scale}, ${row.width}×${row.height}: camera only ${cell(row.camera)}` +
        `both drawn ${cell(row.drawn)}panned ${cell(row.panned)}`)
    }
  }
  process.exit(failed ? 1 : 0)
}
const framesAt = args.indexOf('--frames')
const frames = framesAt >= 0 ? Number(args[framesAt + 1]) : 12
if (!(frames >= 2)) { console.error('--frames needs a number of at least 2'); process.exit(2) }
const named = args.filter((a, i) => !a.startsWith('--') && (framesAt < 0 || i !== framesAt + 1))
const unknown = named.filter(n => !boards.some(b => b.name === n))
if (unknown.length) { console.error('no such board: ' + unknown.join(', ')); process.exit(2) }
const plan = named.length ? boards.filter(b => named.includes(b.name)) : boards

function measure(fixture) {
  const text = fixture.text()
  const data = JSON.parse(text)
  fs.rmSync(generated, { recursive: true, force: true })
  fs.mkdirSync(generated, { recursive: true })
  try {
    fs.writeFileSync(path.join(generated, 'board.json'), text)
    fs.writeFileSync(path.join(generated, 'plan.json'), JSON.stringify({ name: fixture.name,
      items: data.items.length, links: data.links.length, frames }))
    const result = spawnSync(runner, ['-input', path.join(__dirname, 'connectors/tst_connectors.qml')], {
      encoding: 'utf8', timeout: 1800000, maxBuffer: 1 << 26,
      env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: '', QT_QUICK_BACKEND: 'software',
        QT_QUICK_CONTROLS_STYLE: 'Basic', QML_XHR_ALLOW_FILE_READ: '1' } })
    const output = (result.stdout || '') + (result.stderr || '')
    const line = output.split('\n').find(l => l.includes('CONNECTORS '))
    if (!line || result.status !== 0) {
      console.error(`${fixture.name}: the run failed\n` + output.split('\n').slice(-30).join('\n'))
      return null
    }
    return JSON.parse(line.slice(line.indexOf('CONNECTORS ') + 11))
  } finally { fs.rmSync(generated, { recursive: true, force: true }) }
}

if (!json) {
  const facts = provenance(false)
  facts.push(['Renderer', 'offscreen, software, 1100×700'], ['Steps per phase', String(frames)])
  const width = Math.max(...facts.map(f => f[0].length))
  for (const [label, value] of facts) console.log(`${label.padEnd(width)}  ${value}`)
  console.log('\nms. frame and raster: median/worst of the steps. geometry and paths: one paint\'s script, timed apart\n')
}

let failed = false
for (const fixture of plan) {
  const r = measure(fixture)
  if (!r) { failed = true; continue }
  if (json) { console.log(JSON.stringify(r)); continue }
  console.log(`${r.name}: ${r.items} items, ${r.links} connectors`)
  for (const [label, view] of [['100%', r.near], ['20%', r.far]]) {
    const s = view.script
    console.log(`  at ${label}, ${s.shown} shown: geometry ${s.geometry}, paths ${s.paths}, idle frame ${view.idle.median}`)
    console.log('    phase   frame        raster')
    for (const phase of ['pan', 'zoom', 'select', 'drag']) {
      const cell = v => `${v.median}/${v.worst}`.padEnd(13)
      console.log(`    ${phase.padEnd(8)}${cell(view[phase].frame)}${cell(view[phase].raster)}`)
    }
  }
}
process.exit(failed ? 1 : 0)
