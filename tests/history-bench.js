#!/usr/bin/env node
// What keeping a board's history costs, against the budgets in
// docs/splitview-timeline-plan.md ("Resource gates"). Each fixture is a seeded
// session of edits: its size against the limits, what recording one edit
// costs, what opening a board with it costs, building the index a timeline
// seeks with, and seeking. Measured here in node, then the same file and the
// same fixtures in the engine the board runs in (tests/qml/bench_history.qml),
// because that engine is several times slower and is the one that counts.
// The save, with the copy of the version it replaces, goes through the real
// helper at the size limit.
//
//   node tests/history-bench.js            node and the board's engine
//   node tests/history-bench.js --node     node only
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const { loadStore } = require('../bin/store')
const { random, board, edit, MIXES } = require('./history-fixtures')

const repo = path.join(__dirname, '..')
const H = loadStore(fs.readFileSync(path.join(repo, 'BoardHistory.js'), 'utf8'))
const nodeOnly = process.argv.includes('--node')

const FIXTURES = [
  { name: '1000 items, 5000 mixed edits', items: 1000, edits: 5000, mix: 'mixed', seed: 11 },
  { name: '3000 items, 10000 moves', items: 3000, edits: 10000, mix: 'moves', seed: 12 },
  { name: '300 items, 5000 text edits', items: 300, edits: 5000, mix: 'text', seed: 13 },
  // Long notes to begin with: what a history at the size limit costs to read.
  { name: '3000 long notes, 3000 text edits', items: 3000, edits: 3000, mix: 'text', seed: 14, words: 1500 }
]

const now = () => Number(process.hrtime.bigint()) / 1e6
function stats(samples) {
  const s = samples.slice().sort((a, b) => a - b)
  const at = q => s[Math.min(s.length - 1, Math.floor(q * s.length))]
  return { p50: at(0.5), p95: at(0.95), max: s[s.length - 1] }
}
const ms = v => v.toFixed(1)
const mib = bytes => (bytes / 1048576).toFixed(2) + ' MiB'

function build(f) {
  const rnd = random(f.seed)
  let state = board(rnd, f.items, f.words)
  const base = H.copyState(state)
  const h = H.create(state, 1700000000000, 'bench-' + f.seed)
  const seen = [base]
  const diffs = []
  let bytes = H.utf8Length(JSON.stringify(Object.assign({}, h, { records: [] })))
  let full = ''
  for (let i = 0; i < f.edits; i++) {
    const made = edit(rnd, state, f.mix, seen)
    const t0 = now()
    const record = H.append(h, state, made.state, made.kind, 1700000000000 + i * 2000)
    diffs.push(now() - t0)
    if (record) {
      const fit = H.room(h, bytes, record)
      if (!fit.fits && !full) full = `${fit.why} limit reached at record ${h.records.length}`
      bytes = fit.bytes
    }
    if (seen.length < 4) seen.push(H.copyState(made.state))
    else { seen.shift(); seen.push(made.state) }
    state = made.state
  }
  return { h, final: state, diffs: stats(diffs), full }
}

console.log(`node ${process.version}, ${os.cpus()[0].model}`)
const results = []
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-history-'))
try {
  for (const f of FIXTURES) {
    const { h, final, diffs, full } = build(f)
    const historyText = JSON.stringify(h)
    const live = JSON.stringify({ kind: 'omarchyform.board', version: 6, nextId: final.nextId,
      items: final.items, links: final.links }, null, 2)
    const fileText = live.slice(0, -2) + ',\n  "history": ' + historyText + '\n}\n'
    const bytes = Buffer.byteLength(historyText)

    let t0 = now(); JSON.stringify(h); const stringify = now() - t0
    t0 = now(); const parsed = JSON.parse(fileText); const parse = now() - t0
    t0 = now(); const shape = H.checkShape(parsed.history); const shapeMs = now() - t0
    t0 = now(); const wrong = H.verify(parsed.history, final); const verify = now() - t0
    if (shape !== '' || wrong !== '') throw new Error(`${f.name}: ${shape || wrong}`)

    const ix = H.newIndex(parsed.history, 100)
    const slices = []
    t0 = now()
    while (true) {
      const s0 = now()
      const done = H.indexSome(ix, parsed.history, 200)
      slices.push(now() - s0)
      if (done) break
    }
    const indexMs = now() - t0
    const rnd = random(99)
    const seeks = []
    for (let i = 0; i < 200; i++) {
      const at = Math.floor(rnd() * (parsed.history.records.length + 1))
      const s0 = now()
      H.stateAt(ix, parsed.history, at)
      seeks.push(now() - s0)
    }
    results.push({ f, bytes, records: h.records.length, full, diffs, stringify, parse, shapeMs, verify, indexMs,
                   slice: stats(slices), seek: stats(seeks), checkpoints: ix.checkpoints.length })
    fs.writeFileSync(path.join(scratch, f.seed + '.json'), fileText)
  }

  console.log('\nnode, ms                       record p95/max  file      stringify  parse  verify  index (max slice)  seek p95/max')
  for (const r of results)
    console.log(`${r.f.name.padEnd(30)} ${(ms(r.diffs.p95) + '/' + ms(r.diffs.max)).padEnd(15)} ${mib(r.bytes).padEnd(9)} `
      + `${ms(r.stringify).padEnd(10)} ${ms(r.parse).padEnd(6)} ${ms(r.verify).padEnd(7)} `
      + `${(ms(r.indexMs) + ' (' + ms(r.slice.max) + ')').padEnd(18)} ${ms(r.seek.p95)}/${ms(r.seek.max)}`)
  for (const r of results)
    console.log(`  ${r.f.name}: ${r.records} records${r.full ? ', ' + r.full : ', within both limits'}`)

  // The write the plugin makes, through the helper it makes it with: a board
  // at the size limit, staged, locked, the old one copied to backups, renamed.
  const big = path.join(scratch, 'big.json')
  const target = path.join(scratch, 'boards', 'big.json')
  fs.mkdirSync(path.dirname(target), { recursive: true })
  const pad = 'x'.repeat(1024)
  const huge = JSON.stringify({ kind: 'omarchyform.board', version: 6, nextId: 1, items: [], links: [],
    history: { pad: Array.from({ length: 16 * 1024 }, () => pad) } })
  fs.writeFileSync(big, huge)
  fs.writeFileSync(target, huge)
  const saves = []
  for (let i = 0; i < 10; i++) {
    const t = now()
    const run = spawnSync('bash', [path.join(repo, 'BoardFiles.sh'), 'commit', target,
      path.join(scratch, 'backups', 'big.json.bak'), path.join(scratch, 'locks', 'big.lock'), '-'],
      { input: huge, encoding: 'utf8' })
    saves.push(now() - t)
    if (run.status !== 0) throw new Error('commit failed: ' + run.stderr)
  }
  const save = stats(saves)
  console.log(`\nsave through BoardFiles.sh at ${mib(huge.length)}, with backup: p50 ${ms(save.p50)}ms, p95 ${ms(save.p95)}ms`)

  if (!nodeOnly) {
    const qml = path.join(scratch, 'tst_bench_history.qml')
    const fill = (text, seeds, memory) => text.replace(/@REPO@/g, 'file://' + repo).replace(/@DIR@/g, scratch)
      .replace(/@SEEDS@/g, seeds || FIXTURES.map(f => f.seed).join(',')).replace(/@MEMORY@/g, memory || 'no')
    fs.writeFileSync(qml, fill(fs.readFileSync(path.join(__dirname, 'qml', 'bench_history.qml'), 'utf8')))
    fs.writeFileSync(path.join(scratch, 'history_worker.js'),
      fill(fs.readFileSync(path.join(__dirname, 'qml', 'history_worker.js'), 'utf8')))
    // The board's own worker, beside the codec it includes.
    for (const name of ['BoardHistoryWorker.js', 'BoardHistory.js'])
      fs.copyFileSync(path.join(repo, name), path.join(scratch, name))
    const run = spawnSync('/usr/lib/qt6/bin/qmltestrunner', ['-input', qml], {
      encoding: 'utf8', timeout: 600000,
      env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QML_XHR_ALLOW_FILE_READ: '1' }
    })
    const out = (run.stdout || '') + (run.stderr || '')
    const lines = out.split('\n').filter(l => /BENCH|FAIL|rror/.test(l))
    const qt = (/Using QtTest library ([\d.]+)/.exec(out) || [])[1] || '?'
    console.log('\nthe board\'s engine (Qt ' + qt + ', offscreen), ms')
    for (const l of lines) console.log('  ' + l.replace(/^.*BENCH /, ''))
    // Memory, one fresh process per fixture.
    for (const f of FIXTURES) {
      const one = path.join(scratch, 'tst_memory_' + f.seed + '.qml')
      fs.writeFileSync(one, fill(fs.readFileSync(path.join(__dirname, 'qml', 'bench_history.qml'), 'utf8'),
        String(f.seed), 'yes'))
      const mem = spawnSync('/usr/lib/qt6/bin/qmltestrunner', ['-input', one], {
        encoding: 'utf8', timeout: 600000,
        env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QML_XHR_ALLOW_FILE_READ: '1' } })
      for (const l of ((mem.stdout || '') + (mem.stderr || '')).split('\n').filter(x => /BENCH|FAIL|rror/.test(x)))
        console.log('  ' + l.replace(/^.*BENCH /, ''))
    }
  }
} finally {
  fs.rmSync(scratch, { recursive: true, force: true })
}
