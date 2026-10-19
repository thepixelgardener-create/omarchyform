// Every board in tests/hostile-fixtures.js, opened by both engines that read
// one and held to a time: offscreen by the real Board (tests/hostile/), and by
// bin/omarchyform. A fixture past its budget, or one that never finishes, fails.
//
//   node tests/hostile.js [name...]   only the fixtures named
//
// The budgets are the worst frame on a software-rendered offscreen window,
// set below; docs/performance.md has what they were measured at.
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

// The longest a board may hold the shell up at once, in ms: the worst frame
// while it opens, is drawn zoomed out, and opens again. A fixture listed in
// KNOWN is a stall still there: its ceiling is about half as much again as
// measured on 2026-10-17 (Qt 6.12, offscreen, software), so it cannot get
// worse unnoticed, and fixing it means lowering or deleting it. The command
// line's budget is wall time.
const BUDGET = { qml: 2000, cli: 2000 }
const KNOWN = {
  // 20,000 connectors on screen at once: working out where each one goes and
  // stroking them, 2.5 to 3.8s. Round line caps made it 20s.
  'max-links': 6000,
  // jsonFits walks a text it cannot settle by counting: 1.3 to 2.5s at 32 MB.
  'escaped-quotes': 4000, 'old-history': 4000
}
const budget = name => ({ qml: KNOWN[name] || BUDGET.qml, cli: BUDGET.cli })
// A process still running after this has stalled for good, whatever its
// budget: a sliced fill of the largest board takes under a minute.
const KILL_MS = 300000 * scale

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
    return { name: f.name, file, opens: f.opens, cliWarning: f.cliWarning, cliError: f.cliError }
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
    const cost = seen ? Math.max(seen.open.frame, seen.whole.frame, seen.again.frame) : Date.now() - started
    const qmlOk = qml.status === 0 && !qml.error && seen && cost <= limit.qml * scale
      && !/TypeError|ReferenceError|Binding loop/.test(output)

    // The board, from the command line.
    const t0 = Date.now()
    const run = spawnSync(process.execPath, [cli, 'validate', path.join(generated, f.file)],
      { encoding: 'utf8', timeout: KILL_MS, maxBuffer: 64 * 1024 * 1024 })
    const cliMs = Date.now() - t0
    let answer = null
    try { answer = JSON.parse(run.stdout) } catch { /* reported below */ }
    // validate intentionally accepts over-limit canvas content with warnings;
    // malformed/newer boards fail. Neither is interchangeable with any JSON
    // response: a broken CLI used to pass every fixture by returning an error.
    const expectedReply = answer && (f.cliError
      ? run.status === 1 && answer.ok === false && typeof answer.error === 'string' && answer.error.includes(f.cliError)
      : run.status === 0 && answer.ok === true && Array.isArray(answer.warnings)
        && (f.cliWarning
          ? answer.warnings.length === 1 && typeof answer.warnings[0] === 'string' && answer.warnings[0].includes(f.cliWarning)
          : answer.warnings.length === 0))
    const cliOk = !run.error && expectedReply && cliMs <= limit.cli * scale

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
