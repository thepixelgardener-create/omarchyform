#!/usr/bin/env node
// What a board costs to draw, at size. tests/bench.js measures marshalling —
// arithmetic over an array, and fast enough that it has never been the
// problem. This measures the half that is: a scene of delegates and two
// canvases, re-evaluated every frame.
//
//   node tests/scene.js                 100, 500, 1000 and 3000 items
//   node tests/scene.js 3000            one size
//   node tests/scene.js 3000 --textures every item textured
//
// Columns are milliseconds per frame, mean and 95th percentile. A phase at
// the refresh interval (6.9ms at 144Hz, 16.7ms at 60) is vsync-bound and has
// room to spare; above it, the board is dropping frames while you use it.
//
// A diagnostic, not a pass/fail gate, and not part of tests/run: it needs a
// compositor, and frame times on a busy desktop are noisy. Run it before and
// after a change and compare the columns.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const repo = path.join(__dirname, '..')
const omarchy = process.env.OMARCHY_PATH || '/usr/share/omarchy'

// What the numbers were measured on. A frame time means nothing without it —
// the same board is vsync-bound at 60Hz and drops frames at 144 — and a figure
// quoted in a changelog a year from now is only checkable against the machine
// that produced it. Everything here is read from what is already installed and
// every probe is allowed to fail: a missing tool costs one row, not a run.
function ask(command) {
  try {
    const out = spawnSync('sh', ['-c', command], { encoding: 'utf8', timeout: 5000 })
    const text = (out.stdout || '').trim()
    return text === '' ? null : text.split('\n')[0]
  } catch { return null }
}

// The screen the numbers were measured on, scale included. A fractionally
// scaled display draws more pixels than its resolution says, and that is the
// first thing to check when a frame time will not reproduce elsewhere.
function display() {
  try {
    const out = spawnSync('hyprctl', ['-j', 'monitors'], { encoding: 'utf8', timeout: 5000 })
    const monitors = JSON.parse(out.stdout || '[]')
    if (monitors.length === 0) return null
    const one = monitors.find(m => m.focused) || monitors[0]
    const scale = Number(one.scale)
    return `${one.width}\u00d7${one.height} at ${scale}x, `
      + (monitors.length > 1 ? `${monitors.length} outputs` : 'single output')
  } catch { return null }
}

function provenance() {
  return [
    ['Qt', ask('qmake6 -query QT_VERSION || /usr/lib/qt6/bin/qmake6 -query QT_VERSION')],
    ['Quickshell', ask(`qs --version 2>&1 | sed 's/^Quickshell //; s/ *(revision.*//'`)],
    ['Compositor', ask(`hyprctl version -j 2>/dev/null | sed -n 's/.*"version": *"\\([^"]*\\)".*/Hyprland \\1/p'`)],
    ['Refresh', ask(`hyprctl monitors -j 2>/dev/null | sed -n 's/.*"refreshRate": *\\([0-9]*\\.[0-9]\\).*/\\1 Hz/p'`)],
    ['GPU', ask(`lspci 2>/dev/null | grep -iE 'vga|3d' | head -1 | sed 's/.*: //'`)],
    ['CPU', ask(`sed -n 's/^model name[ \t]*: //p' /proc/cpuinfo | head -1`)],
    ['OS', ask(`. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME"`)],
    // The two ways this machine names its Omarchy disagree — the version file
    // says the release, the package says the revision. A bug report carries the
    // package version, so that is the one recorded here and in docs/install.md.
    ['Omarchy', ask(`omarchy-version 2>/dev/null || cat ${omarchy}/version 2>/dev/null`)],
    ['Display', display()]
  ].filter(row => row[1])
}

const args = process.argv.slice(2)
// --record writes docs/performance.md as well as printing, so the numbers a
// changelog quotes have a checked-in record of the machine that produced them.
const record = args.includes('--record')
const textures = args.includes('--textures')
const sizes = args.filter(a => !['--record', '--textures'].includes(a)).map(Number).filter(n => n > 0)
const plan = sizes.length ? sizes : [100, 500, 1000, 3000]

function measure(size) {
  // The same scratch copy beside the shell's own modules that the shot and
  // live suites build, so what is measured is what the shell would load.
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-scene-'))
  try {
    const home = path.join(dir, 'home')
    fs.mkdirSync(home)
    for (const file of fs.readdirSync(repo).filter(f => /\.(qml|js|sh)$/.test(f)))
      fs.copyFileSync(path.join(repo, file), path.join(dir, file))
    for (const module of ['Commons', 'Ui'])
      fs.cpSync(path.join(omarchy, 'shell', module), path.join(dir, module), { recursive: true })
    fs.mkdirSync(path.join(dir, 'services'))
    fs.copyFileSync(path.join(omarchy, 'shell/services/PluginShellApi.qml'),
      path.join(dir, 'services/PluginShellApi.qml'))
    fs.copyFileSync(path.join(__dirname, 'qml/scene.qml'), path.join(dir, 'shell.qml'))

    const state = path.join(home, '.local/state/omarchy/current')
    fs.mkdirSync(state, { recursive: true })
    fs.symlinkSync(path.join(os.homedir(), '.local/state/omarchy/current/theme'),
      path.join(state, 'theme'))

    const display = process.env.WAYLAND_DISPLAY || ''
    const result = spawnSync('qs', ['--no-color', '-p', path.join(dir, 'shell.qml')], {
      encoding: 'utf8', timeout: 180000,
      env: { ...process.env, HOME: home, QT_QPA_PLATFORM: 'wayland',
        QT_QPA_PLATFORMTHEME: '', QT_QUICK_CONTROLS_STYLE: 'Basic',
        XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
        WAYLAND_DISPLAY: path.isAbsolute(display) ? display
          : path.join(process.env.XDG_RUNTIME_DIR || '', display),
        OMARCHYFORM_BENCH_ITEMS: String(size), OMARCHYFORM_BENCH_TEXTURES: textures ? '1' : '0',
        OMARCHYFORM_TEST_DIR: dir }
    })
    const output = (result.stdout || '') + (result.stderr || '')
    if (!output.includes('BENCH_DONE')) {
      console.error(output.split('\n').slice(-25).join('\n'))
      return null
    }
    const rows = []
    let window = '?'
    for (const line of output.split('\n')) {
      const m = line.match(/BENCH (\S[^\t]*)\t([\d.]+)\t([\d.]+)/)
      if (m) rows.push({ name: m[1], mean: Number(m[2]), p95: Number(m[3]) })
      const w = line.match(/BENCH window (\d+)x(\d+)/)
      if (w) window = `${w[1]}×${w[2]}`
    }
    return { rows, window }
  } finally { fs.rmSync(dir, { recursive: true, force: true }) }
}

if (!process.env.WAYLAND_DISPLAY) {
  console.error('This needs a running Wayland session: it measures the real scene.')
  process.exit(2)
}

const facts = provenance()
facts.push(['Item textures', textures ? 'Ruled, Grid, Dots and Hatch, alternating on every item' : 'Plain'])
const factWidth = Math.max(...facts.map(f => f[0].length))
for (const [label, value] of facts) process.stdout.write(`${label.padEnd(factWidth)}  ${value}\n`)
process.stdout.write('\n')

const table = []
for (const size of plan) {
  const measured = measure(size)
  if (!measured) process.exit(1)
  table.push({ size, rows: measured.rows, window: measured.window })
}
// A tiled window is half the screen or all of it depending on what else is
// open, and a wider one draws more of the board, so the same code measures
// differently. Said once when every size had the same window, per size if not.
const windows = [...new Set(table.map(t => t.window))]
facts.push(['Window', (windows.length === 1 ? windows[0]
  : table.map(t => `${t.window} at ${t.size}`).join(', ')) + ' logical px'])
process.stdout.write(`Window  ${facts[facts.length - 1][1]}\n\n`)

const names = table[0].rows.map(r => r.name)
const width = Math.max(...names.map(n => n.length))
process.stdout.write('phase'.padEnd(width) + table.map(t => String(t.size).padStart(13)).join('') + '\n')
for (let i = 0; i < names.length; i++) {
  const cells = table.map(t => {
    const r = t.rows[i]
    return `${r.mean.toFixed(1)}/${r.p95.toFixed(1)}`.padStart(13)
  })
  process.stdout.write(names[i].padEnd(width) + cells.join('') + '\n')
}
// The idle row is the refresh interval this machine actually achieved, which
// is the budget every other row should be read against — measured rather than
// taken from what the monitor claims.
if (record) {
  const lines = ['# What a board costs to draw', '',
    'Written by `npm run bench:scene -- --record` on '
      + new Date().toISOString().slice(0, 10) + '. Every frame time quoted in the',
    'changelog was measured here; a frame time without the machine under it is',
    'not a number anyone can check.', '',
    '## Measured on', '', '| Part | Value |', '| --- | --- |']
  for (const [label, value] of facts) lines.push(`| ${label} | ${value} |`)
  lines.push('', '## Milliseconds per frame, mean/p95', '',
    '| phase | ' + table.map(t => t.size + ' items').join(' | ') + ' |',
    '| --- | ' + table.map(() => '---').join(' | ') + ' |')
  for (let i = 0; i < names.length; i++)
    lines.push(`| ${names[i]} | ` + table.map(t => `${t.rows[i].mean.toFixed(1)}/${t.rows[i].p95.toFixed(1)}`).join(' | ') + ' |')
  const idleRow = table[0].rows.find(r => r.name === 'idle')
  lines.push('', 'The `idle` row is the refresh interval this machine actually reached, and',
    'is the budget the rest are read against: a phase at '
      + (idleRow ? idleRow.mean.toFixed(1) : '?') + 'ms is vsync-bound and',
    'has room to spare, and a phase above it drops frames while the board is',
    'in use.')
  fs.writeFileSync(path.join(repo, 'docs/performance.md'), lines.join('\n') + '\n')
  process.stdout.write('\nwritten docs/performance.md\n')
}

const idle = table[0].rows.find(r => r.name === 'idle')
const budget = idle ? idle.mean : 0
process.stdout.write('\nms per frame, mean/p95.'
  + (budget ? ` One frame here is ${budget.toFixed(1)}ms; a row at that is vsync-bound.` : '')
  + '\n')
