// Complete plugin smoke test using the installed first-party modules and facade.
// --live mounts test windows on the current compositor; board data stays isolated.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const { coverage } = require('./png')
if (!process.argv.includes('--live')) {
  console.error('This test requires a running Omarchy/Hyprland desktop; pass --live to open isolated test surfaces.')
  process.exit(2)
}
const keep = process.argv.includes('--keep')
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
  fs.copyFileSync(path.join(__dirname, 'qml/tst_omarchy.qml'), path.join(dir, 'shell.qml'))
  const theme = path.join(home, '.local/state/omarchy/current')
  fs.mkdirSync(theme, {recursive:true})
  fs.symlinkSync(path.join(os.homedir(), '.local/state/omarchy/current/theme'), path.join(theme, 'theme'))
  const display = process.env.WAYLAND_DISPLAY || ''
  const result = spawnSync('qs', ['--no-color', '-p', path.join(dir, 'shell.qml')], {
    encoding: 'utf8', timeout: 30000,
    env: {...process.env, HOME: home, QT_QPA_PLATFORM: 'wayland',
      QT_QPA_PLATFORMTHEME: '', QT_QUICK_CONTROLS_STYLE: 'Basic', XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
      WAYLAND_DISPLAY: path.isAbsolute(display) ? display : path.join(process.env.XDG_RUNTIME_DIR || '', display),
      OMARCHYFORM_TEST_DIR: dir}
  })
  const output = (result.stdout || '') + (result.stderr || '')
  fs.writeFileSync(path.join(dir, 'runtime.log'), output)
  if (result.error || result.status !== 0 || !output.includes('OMARCHY_TESTS_PASSED') || /FAIL:|TypeError|ReferenceError|Binding loop|WARN scene|ERROR/.test(output)) {
    console.error(output, result.error || '')
    process.exitCode = 1
  } else {
    // The status line said the export succeeded; this says the board is in it.
    // An item culled by mistake draws nothing and still exports at the right
    // size, so neither the file existing nor its dimensions would notice.
    //
    // The two notes this test exports cover 28% of the frame. With the items
    // culled out of it, only the connector between them is left and coverage
    // falls to 11%, so the two cases are not close; a fifth is between them
    // with room on both sides.
    const inked = coverage(path.join(dir, 'export.png'))
    if (inked < 0.2) {
      console.error(`exported PNG is ${(inked * 100).toFixed(1)}% inked: the board did not render into it`)
      process.exitCode = 1
    } else console.log('ok — full Omarchy plugin smoke test (live Wayland)')
  }
} finally {
  if (keep) console.log(`Test artifacts: ${dir}`)
  else fs.rmSync(dir, {recursive:true, force:true})
}
