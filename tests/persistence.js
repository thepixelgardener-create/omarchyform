// Run the actual persistence and session components in isolated headless shells.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
for (const scenario of ['persistence', 'session', 'timeout']) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-persistence-'))
  try {
    fs.writeFileSync(path.join(dir, 'blocked.json'), 'original')
    fs.mkdirSync(path.join(dir, 'blocked.json.bak.tmp'))
    fs.writeFileSync(path.join(dir, 'damaged.json'), '{broken')
    // A folder inside the boards folder that points back at it: a.json there
    // is readable, but saving through it would be refused.
    fs.symlinkSync(dir, path.join(dir, 'linked'))
    if (scenario === 'timeout') {
      const fifo = spawnSync('mkfifo', [path.join(dir, 'slow.json')])
      if (fifo.status !== 0) throw new Error('could not create delayed-backup fixture')
    }
    for (const file of ['BoardPersistence.qml', 'BoardSession.qml', 'BoardStore.js', 'BoardFiles.sh'])
      fs.copyFileSync(path.join(__dirname, '..', file), path.join(dir, file))
    fs.writeFileSync(path.join(dir, 'shell.qml'), fs.readFileSync(path.join(__dirname, `qml/tst_${scenario}.qml`), 'utf8').replace('import "../.."', ''))
    const result = spawnSync('qs', ['--no-color', '-p', path.join(dir, 'shell.qml')], {
      encoding: 'utf8', timeout: 15000,
      env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: '',
        QT_QUICK_CONTROLS_STYLE: 'Basic', XDG_RUNTIME_DIR: dir, OMARCHYFORM_TEST_DIR: dir }
    })
    const output = (result.stdout || '') + (result.stderr || '')
    if (result.error || result.status !== 0 || !output.includes(`${scenario.toUpperCase()}_TESTS_PASSED`) || output.includes('FAIL:')) {
      console.error(output, result.error || '')
      process.exitCode = 1
    } else console.log(`ok — QML ${scenario} regression tests`)
  } finally { fs.rmSync(dir, { recursive: true, force: true }) }
}
