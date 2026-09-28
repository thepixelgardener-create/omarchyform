// What happens to a held screenshot run when it is let go of.
//
//   node tests/hold.js
//
// `npm run shots -- --hold` leaves a board on screen for the pointer checks in
// docs/pointer-checks.md, and the first version of it never ended: the facade's
// hide callback closed the board, the timer went on returning, and the process
// stayed up with nobody watching it and a temporary directory nobody removed.
// So the thing worth testing is not what it draws — the harness beside it does
// that — but that it starts, survives being moved between window modes, ends
// when it is dismissed, waits for what it was writing, and takes its own
// scratch tree with it whichever way it goes.
//
// The board is dismissed by the run itself rather than by a hand, through hooks
// tests/qml/shot.qml reads from the environment and nothing else sets.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync, spawn } = require('child_process')

if (!process.env.WAYLAND_DISPLAY) {
  console.error('This needs a running Wayland session: it opens the real board.')
  process.exit(2)
}

const shots = path.join(__dirname, 'shots.js')
const runRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-hold-suite-'))
process.env.TMPDIR = runRoot
process.env.XDG_CACHE_HOME = path.join(runRoot, 'cache')
const failures = []

function check(what, condition, detail) {
  if (!condition) failures.push(what + (detail ? ': ' + detail : ''))
}

// Every run builds its own directory under here and is expected to take it
// away again. Counted rather than pattern-matched: another run may be open in
// another terminal, and removing its tree would take the board out from under
// whoever is driving it.
function scratchTrees() {
  return fs.readdirSync(os.tmpdir()).filter(f => f.startsWith('omarchyform-shots-'))
}

function held(name, env) {
  const before = scratchTrees()
  const run = spawnSync('node', [shots, '--dark', '--hold'], {
    encoding: 'utf8', timeout: 180000,
    env: { ...process.env, OMARCHYFORM_SHOT_DISMISS: '20', ...env }
  })
  const output = (run.stdout || '') + (run.stderr || '')
  const left = scratchTrees().filter(d => !before.includes(d))
  check(name + ': it did not hang', !run.error, run.error && run.error.message)
  check(name + ': it cleaned up after itself', left.length === 0, left.join(', '))
  return { status: run.status, output }
}

// Dismissed once it is up: the board goes, what it was writing finishes, and
// the run reports that it got there.
{
  const run = held('dismissed')
  check('dismissed: it held the board first', run.output.includes('SHOTS_HOLDING'))
  check('dismissed: it noticed the dismissal', run.output.includes('SHOTS_HELD_DISMISSING'))
  check('dismissed: it finished', run.output.includes('SHOTS_HELD_DONE'), run.output.slice(-400))
  check('dismissed: it exited cleanly', run.status === 0, 'exit ' + run.status)
}

// A window mode switch takes one surface down and puts another up. The board is
// never closed, so the run must not end — the first lifecycle that watched a
// window rather than the board would have ended here.
{
  const run = held('window mode', { OMARCHYFORM_SHOT_TOGGLE: '8' })
  check('window mode: it switched', run.output.includes('SHOTS_HELD_TOGGLED'), run.output.slice(-400))
  check('window mode: it stayed up until it was dismissed',
        run.output.indexOf('SHOTS_HELD_TOGGLED') < run.output.indexOf('SHOTS_HELD_DISMISSING'))
  check('window mode: and then finished', run.output.includes('SHOTS_HELD_DONE'))
  check('window mode: exited cleanly', run.status === 0, 'exit ' + run.status)
}

// A board that cannot be written is the one thing a held run must not exit
// quietly on: closing flushes, and a flush that fails means the work on screen
// did not reach the disk. Arranged by taking the boards directory away from the
// board while it is open, which is the shape of a full disk or a directory
// somebody moved.
{
  const run = held('a failed write', { OMARCHYFORM_SHOT_FAILWRITE: '1' })
  check('a failed write: it said so', run.output.includes('SHOTS_HELD_FAILED'), run.output.slice(-400))
  check('a failed write: it said what happened',
        /SHOTS_HELD_FAILED[^\n]*could not be written/.test(run.output))
  check('a failed write: it did not report success', !run.output.includes('SHOTS_HELD_DONE'))
  check('a failed write: it exited non-zero', run.status === 1, 'exit ' + run.status)
}

// And the other way out: the terminal, rather than the board. Interrupting has
// to reach the child — a board left on screen with nothing watching it is the
// bug this file exists for — and the parent still has to take its own tree
// away, which it cannot do if the interrupt kills it where it stands.
function interrupted() {
  const before = scratchTrees()
  return new Promise(resolve => {
    const child = spawn('node', [shots, '--dark', '--hold'],
      { env: { ...process.env }, stdio: ['ignore', 'pipe', 'pipe'] })
    let output = ''
    child.stdout.on('data', d => { output += d })
    child.stderr.on('data', d => { output += d })
    // Once the board is up, not before: interrupting it mid-photograph would
    // be testing something else.
    const watch = setInterval(() => {
      if (!output.includes('SHOTS_HOLDING')) return
      clearInterval(watch)
      child.kill('SIGINT')
    }, 200)
    const giveUp = setTimeout(() => { clearInterval(watch); child.kill('SIGKILL') }, 180000)
    child.on('close', code => {
      check('interrupted: distinct cancellation result', code === 130, 'exit ' + code)
      clearInterval(watch)
      clearTimeout(giveUp)
      // A moment for the parent's own cleanup to land after its child went.
      setTimeout(() => {
        const left = scratchTrees().filter(d => !before.includes(d))
        check('interrupted: the board was up first', output.includes('SHOTS_HOLDING'))
        check('interrupted: it said it was closing', output.includes('closing the board'),
              output.slice(-400))
        check('interrupted: it cleaned up after itself', left.length === 0, left.join(', '))
        const match = /SHOTS_CHILD_PID (\d+)/.exec(output)
        check('interrupted: exact child PID recorded', !!match)
        if (match) {
          let alive = true
          try { process.kill(Number(match[1]), 0) }
          catch (error) { if (error.code === 'ESRCH') alive = false }
          check('interrupted: that child was reaped', !alive, 'pid ' + match[1])
        }
        resolve()
      }, 500)
    })
  })
}

interrupted().then(finish)

function finish() {
  fs.rmSync(runRoot, { recursive: true, force: true })
  if (failures.length) {
    for (const line of failures) console.error('  ' + line)
    console.error(`FAILED — ${failures.length} check(s)`)
    process.exitCode = 1
    return
  }
  console.log('ok — a held board: starts, survives a mode switch, ends when dismissed or interrupted, cleans up')
}
