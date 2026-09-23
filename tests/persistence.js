// Run the actual persistence component in an isolated, headless Quickshell.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-persistence-'))
try {
  fs.writeFileSync(path.join(dir, 'blocked.json'), 'original')
  fs.mkdirSync(path.join(dir, 'blocked.json.bak.tmp'))
  fs.copyFileSync(path.join(__dirname, '../BoardPersistence.qml'), path.join(dir, 'BoardPersistence.qml'))
  fs.writeFileSync(path.join(dir, 'shell.qml'), fs.readFileSync(path.join(__dirname, 'qml/tst_persistence.qml'), 'utf8').replace('import "../.."', ''))
  const result = spawnSync('qs', ['--no-color', '-p', path.join(dir, 'shell.qml')], {
    encoding: 'utf8', timeout: 15000,
    env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: '',
      QT_QUICK_CONTROLS_STYLE: 'Basic', XDG_RUNTIME_DIR: dir, OMARCHYFORM_TEST_DIR: dir }
  })
  const output = (result.stdout || '') + (result.stderr || '')
  if (result.error || result.status !== 0 || !output.includes('PERSISTENCE_TESTS_PASSED') || output.includes('FAIL:')) {
    console.error(output, result.error || '')
    process.exitCode = 1
  } else console.log('ok — QML persistence: backup ordering, busy guard, write/backup failures, retry')
} finally { fs.rmSync(dir, { recursive: true, force: true }) }
