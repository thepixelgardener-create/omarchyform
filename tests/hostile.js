// Every board in tests/hostile-fixtures.js, opened by every engine that reads
// one and held to a time: offscreen by the real Board (tests/hostile/), by
// bin/omarchyform, and for a board of a megabyte or more by a real
// BoardSession, which opens it and reads it again when another process
// replaces it (tests/hostile/session.qml). A fixture past its budget, or one
// that never finishes, fails.
//
//   node tests/hostile.js [name...]   only the fixtures named
//
// The budgets are the worst frame on a software-rendered offscreen window,
// and for the session the longest its thread was held at once, set below;
// docs/performance.md has what they were measured at.
// OMARCHYFORM_HOSTILE_SCALE multiplies every one, for a slower machine than
// the one that set them.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const { fixtures } = require('./hostile-fixtures')

const runner = process.env.QMLTESTRUNNER || '/usr/lib/qt6/bin/qmltestrunner'
// The session needs Quickshell, which CI's runners do not have; without it
// that part is skipped and says so.
const qs = process.env.QS || '/usr/bin/qs'
const haveQs = fs.existsSync(qs)
const scale = Number(process.env.OMARCHYFORM_HOSTILE_SCALE || 1)
const cli = path.join(__dirname, '..', 'bin', 'omarchyform')
const generated = path.join(__dirname, 'hostile', 'generated')

// The longest a board may hold the shell up at once, in ms: the worst frame
// while it opens, is drawn zoomed out, and opens again. A fixture listed in
// KNOWN is a stall still there: its ceiling is about half as much again as
// measured on 2026-10-17 (Qt 6.12, offscreen, software), so it cannot get
// worse unnoticed, and fixing it means lowering or deleting it. The command
// line's budget is wall time.
const BUDGET = { qml: 2000, cli: 2000, session: 2000 }
const KNOWN = {
  // 20,000 connectors on screen at once: working out where each one goes and
  // stroking them, 2.5 to 3.8s. Round line caps made it 20s.
  'max-links': 6000,
  // jsonFits walks a text it cannot settle by counting: 1.3 to 2.5s at 32 MB.
  'escaped-quotes': 4000, 'old-history': 4000
}
// The same for the session, from open to read again. None is over the default
// now: escaped-quotes, the slowest, holds it 1.4 to 1.5s to open and the same
// to read again, measured on 2026-10-19. Reading it again took 2.4 to 3.3s
// until acceptDisk stopped parsing the text a second time; tests/editing.js
// counts the parses, so that cannot come back however fast a machine is.
const KNOWN_SESSION = {}
const budget = name => ({ qml: KNOWN[name] || BUDGET.qml, cli: BUDGET.cli,
  session: KNOWN_SESSION[name] || BUDGET.session })
// What the session does with a board's text itself, reading it, comparing it
// and parsing it, grows with its bytes; what grows with its items is the
// Board's to time. So the session takes the boards of a megabyte or more.
const SESSION_BYTES = 1024 * 1024
const SESSION_FILES = ['LineField.qml', 'BoardPersistence.qml', 'BoardSession.qml', 'BoardExchange.qml',
  'BoardStore.js', 'BoardFiles.sh', 'BoardFiles.py', 'BoardFileProcess.qml', 'BoardDocument.qml']
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
    const bytes = f.bytes()
    fs.writeFileSync(path.join(generated, file), bytes)
    return { name: f.name, file, size: bytes.length, opens: f.opens, cliWarning: f.cliWarning, cliError: f.cliError }
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

    // The board in a session: opened, then read again once another process
    // has replaced it with one more byte. A board shown read-only is not read
    // again, so it has only its opening.
    let sessionOk = true, sessionShown = ''
    const viaSession = haveQs && f.size >= SESSION_BYTES ? session(f) : null
    if (viaSession) {
      const r = viaSession.seen
      const reread = r && f.opens ? r.reload !== null && typeof r.reload === 'object' : r && r.reload === null
      const held = r ? Math.max(r.open.worst, reread && r.reload ? r.reload.worst : 0) : 0
      sessionOk = viaSession.run.status === 0 && !viaSession.run.error && r !== null && r.opens === f.opens && reread
        && held <= limit.session * scale && !/TypeError|ReferenceError/.test(viaSession.output)
      sessionShown = !r ? '; session no report'
        : `; session open ${r.open.ms}ms (held ${r.open.worst})` + (r.reload === null ? ''
          : typeof r.reload === 'object' ? ` reload ${r.reload.ms}ms (held ${r.reload.worst})` : ` reload ${r.reload}`)
    }

    const shown = seen
      ? `open ${seen.open.ms}ms (frame ${seen.open.frame}) whole ${seen.whole.ms}ms (frame ${seen.whole.frame}) ` +
        `again ${seen.again.ms}ms, ${seen.items} items ${seen.links} links ${JSON.stringify(seen.steps)}`
      : qml.error ? `killed after ${KILL_MS}ms` : 'no report'
    console.log(`${qmlOk && cliOk && sessionOk ? 'ok  ' : 'FAIL'} ${f.name.padEnd(20)} ${shown}; cli ${cliMs}ms${sessionShown}`)
    if (!qmlOk) failures.push(f.name + ' (board)' + (seen ? '' : '\n' + output.slice(-4000)))
    if (!cliOk) failures.push(f.name + ' (cli): ' + (run.error ? run.error.message : (run.stdout + run.stderr).slice(0, 400)))
    if (!sessionOk) failures.push(f.name + ' (session)' + (viaSession.seen ? '' : '\n' + viaSession.output.slice(-4000)))
  }
} finally { fs.rmSync(generated, { recursive: true, force: true }) }

// tests/hostile/session.qml in a scratch folder with the files a document
// needs, as tests/persistence.js runs its scenarios, with the board as
// board.json and the version that replaces it beside it.
function session(f) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-hostile-session-'))
  try {
    for (const file of SESSION_FILES) fs.copyFileSync(path.join(__dirname, '..', file), path.join(dir, file))
    fs.writeFileSync(path.join(dir, 'shell.qml'),
      fs.readFileSync(path.join(__dirname, 'hostile', 'session.qml'), 'utf8').replace('import "../.."', ''))
    fs.copyFileSync(path.join(generated, f.file), path.join(dir, 'board.json'))
    fs.copyFileSync(path.join(generated, f.file), path.join(dir, 'changed.json'))
    fs.appendFileSync(path.join(dir, 'changed.json'), ' ')
    const run = spawnSync(qs, ['--no-color', '-p', path.join(dir, 'shell.qml')], {
      encoding: 'utf8', timeout: KILL_MS, maxBuffer: 64 * 1024 * 1024,
      env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: '', QT_QUICK_CONTROLS_STYLE: 'Basic',
        XDG_RUNTIME_DIR: dir, OMARCHYFORM_TEST_DIR: dir }
    })
    const output = (run.stdout || '') + (run.stderr || '')
    const line = output.split('\n').find(l => l.includes('SESSION {'))
    return { run, output, seen: line ? JSON.parse(line.slice(line.indexOf('{'))) : null }
  } finally { fs.rmSync(dir, { recursive: true, force: true }) }
}

if (failures.length) {
  console.error('\nOver budget or broken:\n  ' + failures.join('\n  '))
  process.exit(1)
}
console.log(`ok — ${chosen.length} hostile boards within budget` + (haveQs ? '' : `; no ${qs}, so none through a session`))
