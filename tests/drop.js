// External offers delivered through Qt’s platform entry points must be
// rejected without requesting their payload, on either pane. Builds
// tests/qt/drop_inject.cpp against this machine's Qt, which needs its private
// window-system header, and runs it offscreen.
const { spawnSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const pkg = (...args) => spawnSync('pkg-config', args, { encoding: 'utf8' })
const version = pkg('--modversion', 'Qt6Gui').stdout.trim()
const includes = pkg('--variable=includedir', 'Qt6Gui').stdout.trim()
const flags = pkg('--cflags', '--libs', 'Qt6Quick', 'Qt6Gui').stdout.trim()
const qpa = path.join(includes, 'QtGui', version)
if (!version || !flags || !fs.existsSync(path.join(qpa, 'QtGui', 'qpa', 'qwindowsysteminterface.h'))) {
  console.error('drop: needs pkg-config and Qt ' + (version || '6') + ' with its private headers to build the injector')
  process.exit(1)
}
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-drop-'))
try {
  const injector = path.join(dir, 'drop_inject')
  const build = spawnSync('g++', ['-std=c++17', '-fPIC', '-O0', path.join(__dirname, 'qt', 'drop_inject.cpp'),
    '-o', injector, '-I' + qpa, '-I' + path.join(qpa, 'QtGui'), ...flags.split(/\s+/)], { encoding: 'utf8' })
  if (build.status !== 0) { console.error(build.stderr); process.exit(1) }
  const file = path.join(dir, 'shot.png')
  fs.writeFileSync(file, '')
  const run = spawnSync(injector, [path.join(__dirname, 'qt', 'drop_scene.qml'), file], {
    encoding: 'utf8', timeout: 60000,
    env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: '' } })
  const out = (run.stdout || '') + (run.stderr || '')
  if (run.status !== 0 || !out.includes('DROP_TESTS_PASSED')) { console.error(out); process.exit(1) }
  console.log('ok — drop: all external offers rejected with zero payload reads in single and split views')
} finally {
  fs.rmSync(dir, { recursive: true, force: true })
}
