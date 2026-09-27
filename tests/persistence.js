// Run the actual persistence and session components in isolated headless shells.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
for (const scenario of ['persistence', 'session', 'timeout', 'exchange']) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-persistence-'))
  try {
    fs.writeFileSync(path.join(dir, 'blocked.json'), 'original')
    fs.mkdirSync(path.join(dir, 'blocked.json.bak.tmp'))
    fs.writeFileSync(path.join(dir, 'damaged.json'), '{broken')
    // A folder inside the boards folder that points back at it: a.json there
    // is readable, but saving through it would be refused.
    fs.symlinkSync(dir, path.join(dir, 'linked'))
    if (scenario === 'exchange') {
      // A library with one picture in it, and a board from somewhere else
      // carrying two: one that decodes to a picture and one that does not.
      for (const d of ['data', 'data/boards', 'data/images']) fs.mkdirSync(path.join(dir, d))
      const pixels = Buffer.from(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==',
        'base64')
      fs.writeFileSync(path.join(dir, 'data/images/pic.png'), pixels)
      fs.writeFileSync(path.join(dir, 'pixels.b64'), pixels.toString('base64'))
      const item = (id, x, src) => ({ id, kind: 'image', x, y: 0, w: 100, h: 100,
                                      tint: 'foreground', text: '', pinned: false, src })
      fs.writeFileSync(path.join(dir, 'shared.omarchyform.json'), JSON.stringify({
        kind: 'omarchyform.board', version: 5, nextId: 3,
        items: [item(1, 0, 'pic.png'), item(2, 200, 'text.png')],
        links: [],
        images: { 'pic.png': pixels.toString('base64'),
                  'text.png': Buffer.from('not a picture at all').toString('base64') }
      }, null, 2) + '\n')
    }
    if (scenario === 'timeout') {
      const fifo = spawnSync('mkfifo', [path.join(dir, 'slow.json')])
      if (fifo.status !== 0) throw new Error('could not create delayed-backup fixture')
    }
    for (const file of ['BoardPersistence.qml', 'BoardSession.qml', 'BoardExchange.qml', 'BoardStore.js', 'BoardFiles.sh'])
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
