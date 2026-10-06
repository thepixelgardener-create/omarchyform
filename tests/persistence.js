// Run the actual persistence and session components in isolated headless shells.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
for (const scenario of ['persistence', 'session', 'timeout', 'exchange', 'clipboard']) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-persistence-'))
  try {
    fs.writeFileSync(path.join(dir, 'blocked.json'), 'original')
    fs.mkdirSync(path.join(dir, 'blocked.json.bak.tmp'))
    fs.writeFileSync(path.join(dir, 'damaged.json'), '{broken')
    // A folder inside the boards folder that points back at it: a.json there
    // is readable, but saving through it would be refused.
    fs.symlinkSync(dir, path.join(dir, 'linked'))
    if (scenario === 'exchange') {
      // A library with one picture in it, and boards arriving from outside:
      // one whole, one carrying a picture that is not one, and one naming a
      // picture no board would ever write.
      for (const d of ['data', 'data/boards', 'data/images']) fs.mkdirSync(path.join(dir, d))
      const pixels = Buffer.from(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==',
        'base64')
      // A second picture that is not the same bytes: anything after IEND is
      // still a PNG to everything that reads one.
      const other = Buffer.concat([pixels, Buffer.from('a second picture')])
      fs.writeFileSync(path.join(dir, 'data/images/pic.png'), pixels)
      fs.writeFileSync(path.join(dir, 'pixels.b64'), pixels.toString('base64'))
      fs.writeFileSync(path.join(dir, 'other.b64'), other.toString('base64'))
      // The bytes themselves, to compare a landed picture against.
      fs.writeFileSync(path.join(dir, 'raw-pixels'), pixels)
      fs.mkdirSync(path.join(dir, 'stubs'))
      fs.writeFileSync(path.join(dir, 'stubs/wl-paste'), '#!/bin/bash\nif [[ $1 == --list-types ]]; then echo image/png; else cat "$OMARCHYFORM_TEST_DIR/raw-pixels"; fi\n', {mode: 0o755})
      fs.writeFileSync(path.join(dir, 'raw-other'), other)
      const item = (id, x, src) => ({ id, kind: 'image', x, y: 0, w: 100, h: 100,
                                      tint: 'foreground', text: '', pinned: false, src })
      const board = (items, images) => JSON.stringify({
        kind: 'omarchyform.board', version: 5, nextId: items.length + 1, items, links: [], images
      }, null, 2) + '\n'

      // Whole: two pictures, one of them referred to twice, and one of them
      // under a name this library has already given to different bytes.
      fs.writeFileSync(path.join(dir, 'shared.omarchyform.json'), board(
        [item(1, 0, 'pic.png'), item(2, 200, 'pic.png'), item(3, 400, 'two.png')],
        { 'pic.png': other.toString('base64'), 'two.png': pixels.toString('base64') }))

      // Carrying something that decodes to text rather than a picture.
      fs.writeFileSync(path.join(dir, 'broken.omarchyform.json'), board(
        [item(1, 0, 'pic.png'), item(2, 200, 'text.png')],
        { 'pic.png': pixels.toString('base64'),
          'text.png': Buffer.from('not a picture at all').toString('base64') }))

      // Carrying no pictures at all, while naming one this library has. The
      // name must not survive the trip, or it addresses this library's picture.
      fs.writeFileSync(path.join(dir, 'foreign.omarchyform.json'), board(
        [item(1, 0, 'pic.png')], undefined))

      // Naming a picture no board would write: refused before anything is
      // decoded, because the name is what decides a path on disk.
      fs.writeFileSync(path.join(dir, 'rejected.omarchyform.json'), board(
        [item(1, 0, 'fine.png')],
        { 'fine.png': pixels.toString('base64'), '../escape.png': pixels.toString('base64') }))

      // Too large to read into memory at all.
      fs.writeFileSync(path.join(dir, 'enormous.omarchyform.json'), Buffer.alloc(33554433, 0x20))

      // Small enough to read, with a note longer than a note can be: the board
      // would only open it read-only, so it is not imported to be opened.
      fs.writeFileSync(path.join(dir, 'overlong.omarchyform.json'), board(
        [{ id: 1, kind: 'note', x: 0, y: 0, w: 220, h: 160, text: 'x'.repeat(1048577) }], undefined))

      // Somewhere an export cannot be published, with something already there.
      fs.mkdirSync(path.join(dir, 'locked'))
      fs.writeFileSync(path.join(dir, 'locked/there.omarchyform.json'), 'not mine to replace')
      fs.chmodSync(path.join(dir, 'locked'), 0o500)
    }
    if (scenario === 'clipboard') {
      fs.mkdirSync(path.join(dir, 'stubs'))
      fs.writeFileSync(path.join(dir, 'stubs/wl-copy'), `#!/bin/bash
printf '%s' "$#" > "$OMARCHYFORM_TEST_DIR/copy-argc"
cat /proc/$$/cmdline > "$OMARCHYFORM_TEST_DIR/copy-argv"
cat /proc/$PPID/cmdline >> "$OMARCHYFORM_TEST_DIR/copy-argv"
cat > "$OMARCHYFORM_TEST_DIR/copied"
[[ ! -e "$OMARCHYFORM_TEST_DIR/fail-copy" ]]
`, {mode: 0o755})
    }
    if (scenario === 'timeout') {
      const fifo = spawnSync('mkfifo', [path.join(dir, 'slow.json')])
      if (fifo.status !== 0) throw new Error('could not create delayed-backup fixture')
    }
    for (const file of ['BoardPersistence.qml', 'BoardSession.qml', 'BoardExchange.qml', 'BoardStore.js', 'BoardFiles.sh'])
      fs.copyFileSync(path.join(__dirname, '..', file), path.join(dir, file))
    // The scenarios import the repository from two folders up; here it is the
    // folder they run in.
    fs.writeFileSync(path.join(dir, 'shell.qml'), fs.readFileSync(path.join(__dirname, `qml/tst_${scenario}.qml`), 'utf8')
      .replace('import "../.."', '').replace('"../../BoardStore.js"', '"BoardStore.js"'))
    const result = spawnSync('qs', ['--no-color', '-p', path.join(dir, 'shell.qml')], {
      encoding: 'utf8', timeout: 15000,
      env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: '',
        PATH: path.join(dir, 'stubs') + ':' + process.env.PATH,
        QT_QUICK_CONTROLS_STYLE: 'Basic', XDG_RUNTIME_DIR: dir, OMARCHYFORM_TEST_DIR: dir }
    })
    const output = (result.stdout || '') + (result.stderr || '')
    if (result.error || result.status !== 0 || !output.includes(`${scenario.toUpperCase()}_TESTS_PASSED`) || output.includes('FAIL:')) {
      console.error(output, result.error || '')
      process.exitCode = 1
    } else console.log(`ok — QML ${scenario} regression tests`)
  } finally {
    // The read-only fixture has to be writable again before it can be removed.
    try { fs.chmodSync(path.join(dir, 'locked'), 0o700) } catch { /* not that scenario */ }
    fs.rmSync(dir, { recursive: true, force: true })
  }
}
