// No text field may read the clipboard's contents until someone pastes: Qt
// 6.12.0's TextInput read all of them on every change, and a clipboard owner on
// Wayland can send for as long as it likes. Builds tests/qt/clipboard_watch.cpp
// against this machine's Qt and runs it offscreen with every field open in turn.
//
// The installed Qt decides what this proves. On one whose TextInput only asks
// which formats are offered, the old fields pass too, so the run that matters
// is on Qt 6.12.0; docs/security-review.md says how it was run there.
const { spawnSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const pkg = (...args) => spawnSync('pkg-config', args, { encoding: 'utf8' })
const version = pkg('--modversion', 'Qt6Gui').stdout.trim()
const flags = pkg('--cflags', '--libs', 'Qt6Quick', 'Qt6Gui').stdout.trim()
if (!version || !flags) {
  console.error('clipboard: needs pkg-config and Qt 6 development headers to build the watcher')
  process.exit(1)
}
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-clipboard-'))
try {
  const watcher = process.env.CLIPBOARD_WATCH || path.join(dir, 'clipboard_watch')
  if (!process.env.CLIPBOARD_WATCH) {
    const build = spawnSync('g++', ['-std=c++17', '-fPIC', '-O0', path.join(__dirname, 'qt', 'clipboard_watch.cpp'),
      '-o', watcher, ...flags.split(/\s+/)], { encoding: 'utf8', timeout: 300000 })
    if (build.status !== 0) { console.error(build.stderr || build.error); process.exit(1) }
  }
  const run = spawnSync(watcher, [path.join(__dirname, 'qt', 'clipboard_scene.qml')], {
    encoding: 'utf8', timeout: 60000,
    env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: '' } })
  const out = (run.stdout || '') + (run.stderr || '')
  if (run.status !== 0 || !out.includes('CLIPBOARD_TESTS_PASSED')) { console.error(out, run.error || ''); process.exit(1) }
  const qt = (/^Qt (\S+)/m.exec(out) || [])[1] || version
  console.log(`ok — clipboard: no text field reads the clipboard's contents unasked, on Qt ${qt}`)
} finally {
  fs.rmSync(dir, { recursive: true, force: true })
}
