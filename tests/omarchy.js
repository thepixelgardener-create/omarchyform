// Complete plugin smoke test using the installed first-party modules and facade.
// --live mounts test windows on the current compositor; board data stays isolated.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const { read, paper, inked, canvasColour } = require('./png')
const { checkExport } = require('./picture')
if (!process.argv.includes('--live')) {
  console.error('This test requires a running Omarchy/Hyprland desktop; pass --live to open isolated test surfaces.')
  process.exit(2)
}
const keep = process.argv.includes('--keep')
const paste = process.argv.includes('--paste')
const omarchy = process.env.OMARCHY_PATH || '/usr/share/omarchy'
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-compat-'))
try {
  const home = path.join(dir, 'home')
  fs.mkdirSync(home)
  for (const file of fs.readdirSync(path.join(__dirname, '..')).filter(f => /\.(qml|js|sh)$/.test(f)))
    fs.copyFileSync(path.join(__dirname, '..', file), path.join(dir, file))
  for (const module of ['Commons', 'Ui'])
    fs.cpSync(path.join(omarchy, 'shell', module), path.join(dir, module), { recursive: true })
  fs.mkdirSync(path.join(dir, 'services'))
  fs.copyFileSync(path.join(omarchy, 'shell/services/PluginShellApi.qml'), path.join(dir, 'services/PluginShellApi.qml'))
  fs.copyFileSync(path.join(__dirname, paste ? 'qml/tst_paste.qml' : 'qml/tst_omarchy.qml'), path.join(dir, 'shell.qml'))
  // A picture: what the clipboard stub hands over, and what the main run
  // drops on a pane.
  fs.writeFileSync(path.join(dir, 'pixels.png'), Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==', 'base64'))
  if (paste) {
    fs.mkdirSync(path.join(dir, 'stubs'))
    // The last stage asks what happens when the clipboard does not answer, so
    // the stub refuses once the test drops a marker beside it. A failure the
    // board only hears about through a real non-zero exit is the one worth
    // testing: assigning the message by hand would pass whatever the producers
    // actually do.
    fs.writeFileSync(path.join(dir, 'stubs/wl-paste'),
      '#!/bin/bash\nif [[ -e "$OMARCHYFORM_TEST_DIR/no-clipboard" ]]; then exit 1; fi\n'
      + 'if [[ $1 == --list-types ]]; then echo image/png; else cat "$OMARCHYFORM_TEST_DIR/pixels.png"; fi\n', {mode: 0o755})
  }
  // A board built by bin/omarchyform, waiting in the boards directory for the
  // real shell to open. The CLI's own suite checks its output against the
  // loader the plugin uses; this checks the plugin, running, actually opens it.
  const boards = path.join(home, '.local/share/omarchyform/boards')
  fs.mkdirSync(boards, { recursive: true })
  const built = spawnSync(process.execPath,
    [path.join(__dirname, '..', 'bin', 'omarchyform'), 'new', path.join(boards, 'from-cli.json'),
     '--note', 'built headlessly', '--note', 'by the command line'],
    { encoding: 'utf8' })
  if (built.status !== 0) {
    console.error('could not build the board for the round trip:', built.stdout, built.stderr)
    process.exitCode = 1
  }

  // And one outside the library entirely, the way a board arrives when someone
  // sends you one: the file manager hands its path to the shell.
  const outside = spawnSync(process.execPath,
    [path.join(__dirname, '..', 'bin', 'omarchyform'), 'new', path.join(dir, 'sent-to-me.omarchyform.json'),
     '--note', 'from somebody else'],
    { encoding: 'utf8' })
  if (outside.status !== 0) {
    console.error('could not build the board to open by path:', outside.stdout, outside.stderr)
    process.exitCode = 1
  }

  const theme = path.join(home, '.local/state/omarchy/current')
  fs.mkdirSync(theme, {recursive:true})
  fs.symlinkSync(path.join(os.homedir(), '.local/state/omarchy/current/theme'), path.join(theme, 'theme'))
  const display = process.env.WAYLAND_DISPLAY || ''
  const result = spawnSync('qs', ['--no-color', '-p', path.join(dir, 'shell.qml')], {
    encoding: 'utf8', timeout: 30000,
    env: {...process.env, HOME: home, PATH: (paste ? path.join(dir, 'stubs') + ':' : '') + process.env.PATH, QT_QPA_PLATFORM: 'wayland',
      QT_QPA_PLATFORMTHEME: '', QT_QUICK_CONTROLS_STYLE: 'Basic', XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
      WAYLAND_DISPLAY: path.isAbsolute(display) ? display : path.join(process.env.XDG_RUNTIME_DIR || '', display),
      OMARCHYFORM_TEST_DIR: dir}
  })
  const output = (result.stdout || '') + (result.stderr || '')
  fs.writeFileSync(path.join(dir, 'runtime.log'), output)
  if (result.error || result.status !== 0 || !output.includes('OMARCHY_TESTS_PASSED') || /FAIL:|TypeError|ReferenceError|Binding loop|WARN scene|ERROR/.test(output)) {
    console.error(output, result.error || '')
    process.exitCode = 1
  } else if (paste) {
    console.log('ok — clipboard images reach the live canvas, repeat, undo and save')
  } else {
    // The status line said the export succeeded; this says the board is in it.
    // The status line said the export succeeded; this says the board is in it.
    // An item culled by mistake draws nothing and still exports at exactly the
    // right size, so neither the file existing nor its dimensions would notice.
    //
    // Asked of each item's own rectangle rather than of the whole frame. The
    // gate this replaces wanted a fifth of the picture to be inked, and an
    // export is the board's bounds plus padding — so how much of it two notes
    // cover depends on how far apart they are, and the paste that makes one of
    // them lands at the centre of the *view*. It was measuring the display. On
    // a wide enough one the notes fell 728px apart and a complete export scored
    // 16%. The board is pinned to a fixed shape before the export now, and what
    // is asked of it no longer depends on the frame at all: see picture.js, and
    // tests/export.js for each fault being caught without a desktop.
    const problems = checkExport(read(path.join(dir, 'export.png')),
      JSON.parse(fs.readFileSync(path.join(dir, 'editable.json'), 'utf8')))
    if (problems.length) {
      for (const problem of problems) console.error(problem)
      process.exitCode = 1
      return
    }

    // The same board asked for on white and framed around one of its two
    // notes. A palette is the one thing about an export that a count of ink
    // cannot see — the same board covers the same fraction of the frame
    // whatever it is drawn in — so this looks at what it was drawn on, and at
    // the size, which is what the crop changes.
    const whole = read(path.join(dir, 'export.png'))
    const cropped = read(path.join(dir, 'export-light.png'))
    const page = paper(cropped)
    // Not checkExport: that reads its rectangles from a board file, and this
    // picture is of part of a board. What is asked of it is the two things a
    // crop and a palette change — what it came out on, and how big it is —
    // plus that something is in it at all.
    const filled = inked(cropped, { x: 0, y: 0, w: cropped.width, h: cropped.height },
                         canvasColour(cropped))
    if (page !== '#ffffff') {
      console.error(`a PNG asked for on white came out on ${page}`)
      process.exitCode = 1
    } else if (cropped.width >= whole.width) {
      console.error(`framing around one of two notes gave ${cropped.width}px, no narrower than the board's ${whole.width}px`)
      process.exitCode = 1
    } else if (filled <= 0) {
      console.error('the cropped PNG has nothing in it')
      process.exitCode = 1
    } else console.log('ok — full Omarchy plugin smoke test (live Wayland)')
  }
} finally {
  if (keep) console.log(`Test artifacts: ${dir}`)
  else fs.rmSync(dir, {recursive:true, force:true})
}
