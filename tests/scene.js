#!/usr/bin/env node
// What a board costs to draw, at size. tests/bench.js measures marshalling —
// arithmetic over an array, and fast enough that it has never been the
// problem. This measures the half that is: a scene of delegates and two
// canvases, re-evaluated every frame.
//
//   node tests/scene.js                 100, 500, 1000 and 3000 items
//   node tests/scene.js 3000            one size
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

const sizes = process.argv.slice(2).map(Number).filter(n => n > 0)
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
        OMARCHYFORM_BENCH_ITEMS: String(size), OMARCHYFORM_TEST_DIR: dir }
    })
    const output = (result.stdout || '') + (result.stderr || '')
    if (!output.includes('BENCH_DONE')) {
      console.error(output.split('\n').slice(-25).join('\n'))
      return null
    }
    const rows = []
    for (const line of output.split('\n')) {
      const m = line.match(/BENCH (\S[^\t]*)\t([\d.]+)\t([\d.]+)/)
      if (m) rows.push({ name: m[1], mean: Number(m[2]), p95: Number(m[3]) })
    }
    return rows
  } finally { fs.rmSync(dir, { recursive: true, force: true }) }
}

if (!process.env.WAYLAND_DISPLAY) {
  console.error('This needs a running Wayland session: it measures the real scene.')
  process.exit(2)
}

const table = []
for (const size of plan) {
  const rows = measure(size)
  if (!rows) process.exit(1)
  table.push({ size, rows })
}

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
process.stdout.write('\nms per frame, mean/p95.\n')
