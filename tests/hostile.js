// Every board in tests/hostile-fixtures.js, opened by both engines that read
// one and held to a time: offscreen by the real Board (tests/hostile/), and by
// bin/omarchyform. A fixture past its budget, or one that never finishes, fails.
//
//   node tests/hostile.js [name...]   only the fixtures named
//
// The budgets are wall time on a software-rendered offscreen window, set
// below; docs/performance.md has what they were measured at.
// OMARCHYFORM_HOSTILE_SCALE multiplies every one, for a slower machine than
// the one that set them.
const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')
const { fixtures } = require('./hostile-fixtures')

const runner = process.env.QMLTESTRUNNER || '/usr/lib/qt6/bin/qmltestrunner'
const scale = Number(process.env.OMARCHYFORM_HOSTILE_SCALE || 1)
const cli = path.join(__dirname, '..', 'bin', 'omarchyform')
const generated = path.join(__dirname, 'hostile', 'generated')

// What a board may cost to open, draw and open again, in ms of wall time. A
// fixture listed in KNOWN is a stall still there: its ceiling is about half as
// much again as measured on 2026-10-16 (Qt 6.12, offscreen, software), so it
// cannot get worse unnoticed, and fixing it means lowering or deleting it.
// Twenty frames alone take about 350ms.
const BUDGET = { qml: 2000, cli: 2000 }
const KNOWN = {
  // Every item's delegate is built at once on the shell's thread, about 1.7ms
  // each, so a board at MAX_ITEMS holds it 8 to 11s from a 0.6 MB file.
  'max-items-stacked': 15000, 'max-items-grid': 15000, 'max-items-shapes': 15000, 'max-id': 15000,
  'duplicate-ids': 15000, 'extreme-geometry': 16000, 'odd-values': 15000, 'pictures-missing': 16000,
  // The same, with each delegate laying out a 4,000-character preview: 28s.
  'max-items-previews': 40000,
  // 20,000 connectors on screen at once: a 20s first frame, not in any step
  // this times, so most likely the connector canvas (unconfirmed).
  'max-links': 30000,
  // Emoji joined into sequences: 13 notes, 5s, mostly in the first frame.
  'notes-emoji-zwj': 8000,
  // jsonFits walks a text it cannot settle by counting: 1.2 to 1.4s at 32 MB.
  'escaped-quotes': 3000, 'old-history': 3000
}
const budget = name => ({ qml: KNOWN[name] || BUDGET.qml, cli: BUDGET.cli })
// A process still running after this has stalled for good: opening, drawing
// and opening again, each at the largest ceiling, and then some.
const KILL_MS = 4 * Math.max(...Object.values(KNOWN)) * scale

const wanted = process.argv.slice(2)
const unknown = wanted.filter(w => !fixtures.some(f => f.name === w))
if (unknown.length) {
  console.error('no such fixture: ' + unknown.join(' '))
  process.exit(2)
}
const chosen = wanted.length ? fixtures.filter(f => wanted.includes(f.name)) : fixtures

fs.rmSync(generated, { recursive: true, force: true })
fs.mkdirSync(generated)
const failures = []
try {
  const manifest = chosen.map(f => {
    const file = f.name + '.omarchyform.json'
    fs.writeFileSync(path.join(generated, file), f.bytes())
    return { name: f.name, file, opens: f.opens }
  })
  fs.writeFileSync(path.join(generated, 'manifest.json'), JSON.stringify(manifest))

  for (const f of manifest) {
    const limit = budget(f.name)
    // The board, in a window.
    const started = Date.now()
    const qml = spawnSync(runner, ['-input', path.join(__dirname, 'hostile', 'tst_hostile.qml'),
      'HostileBoards::test_open:' + f.name], {
      encoding: 'utf8', timeout: KILL_MS, maxBuffer: 64 * 1024 * 1024,
      env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: '', QT_QUICK_BACKEND: 'software',
        QT_QUICK_CONTROLS_STYLE: 'Basic', QML_XHR_ALLOW_FILE_READ: '1' }
    })
    const output = (qml.stdout || '') + (qml.stderr || '')
    const line = output.split('\n').find(l => l.includes('HOSTILE {'))
    const seen = line ? JSON.parse(line.slice(line.indexOf('{'))) : null
    const cost = seen ? Math.max(seen.open.ms, seen.whole.ms, seen.again.ms) : Date.now() - started
    const qmlOk = qml.status === 0 && !qml.error && seen && cost <= limit.qml * scale
      && !/TypeError|ReferenceError|Binding loop/.test(output)

    // The board, from the command line.
    const t0 = Date.now()
    const run = spawnSync(process.execPath, [cli, 'validate', path.join(generated, f.file)],
      { encoding: 'utf8', timeout: KILL_MS, maxBuffer: 64 * 1024 * 1024 })
    const cliMs = Date.now() - t0
    let answer = null
    try { answer = JSON.parse(run.stdout) } catch { /* reported below */ }
    const cliOk = !run.error && answer !== null && cliMs <= limit.cli * scale

    const shown = seen
      ? `open ${seen.open.ms}ms (frame ${seen.open.frame}) whole ${seen.whole.ms}ms (frame ${seen.whole.frame}) ` +
        `again ${seen.again.ms}ms, ${seen.items} items ${seen.links} links ${JSON.stringify(seen.steps)}`
      : qml.error ? `killed after ${KILL_MS}ms` : 'no report'
    console.log(`${qmlOk && cliOk ? 'ok  ' : 'FAIL'} ${f.name.padEnd(20)} ${shown}; cli ${cliMs}ms`)
    if (!qmlOk) failures.push(f.name + ' (board)' + (seen ? '' : '\n' + output.slice(-4000)))
    if (!cliOk) failures.push(f.name + ' (cli): ' + (run.error ? run.error.message : (run.stdout + run.stderr).slice(0, 400)))
  }
} finally { fs.rmSync(generated, { recursive: true, force: true }) }

if (failures.length) {
  console.error('\nOver budget or broken:\n  ' + failures.join('\n  '))
  process.exit(1)
}
console.log(`ok — ${chosen.length} hostile boards within budget`)
