// Photograph the plugin in each state worth judging by eye, in every theme
// asked for. Runs the real components against the live compositor in an
// isolated HOME, so the installed copy and the running shell are untouched.
//
//   node tests/shots.js                  the theme you are using
//   node tests/shots.js tokyo-night catppuccin-latte
//   node tests/shots.js --light --dark   one of each, whichever is installed
//
// Pictures land in ~/.cache/omarchyform/shots/<theme>/ — outside the plugin
// tree, so they are never part of what a user installs.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const repo = path.join(__dirname, '..')
const omarchy = process.env.OMARCHY_PATH || '/usr/share/omarchy'
const cache = path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), '.cache'),
  'omarchyform/shots')
const themeDirs = [path.join(os.homedir(), '.config/omarchy/themes'), path.join(omarchy, 'themes')]

function modeOf(dir) {
  try {
    const colors = fs.readFileSync(path.join(dir, 'colors.toml'), 'utf8')
    return /^\s*mode\s*=\s*"light"/m.test(colors) ? 'light' : 'dark'
  } catch { return 'dark' }
}

// A theme is a name to look up in the usual places, or a path to one.
function resolveTheme(name) {
  if (name.includes('/')) return { label: path.basename(name), dir: path.resolve(name) }
  for (const base of themeDirs) {
    const dir = path.join(base, name)
    if (fs.existsSync(path.join(dir, 'colors.toml'))) return { label: name, dir }
  }
  throw new Error('no theme called ' + name + ' in ' + themeDirs.join(' or '))
}

function firstThemeOfMode(mode) {
  for (const base of themeDirs) {
    if (!fs.existsSync(base)) continue
    for (const name of fs.readdirSync(base).sort()) {
      const dir = path.join(base, name)
      if (fs.existsSync(path.join(dir, 'colors.toml')) && modeOf(dir) === mode)
        return { label: name, dir }
    }
  }
  throw new Error('no ' + mode + ' theme installed to photograph')
}

const args = process.argv.slice(2)
let requested
try {
  requested = args.length === 0
    ? [{ label: 'current', dir: path.join(os.homedir(), '.local/state/omarchy/current/theme') }]
    : args.map(arg => arg === '--light' ? firstThemeOfMode('light')
        : arg === '--dark' ? firstThemeOfMode('dark')
        : resolveTheme(arg))
} catch (error) {
  // A theme that is not there is a typo, not a crash worth a stack trace.
  console.error(error.message)
  process.exit(2)
}

function capture(theme) {
  const out = path.join(cache, theme.label)
  fs.rmSync(out, { recursive: true, force: true })
  fs.mkdirSync(out, { recursive: true })

  // A scratch copy of the plugin beside the shell's own modules, exactly as the
  // live test builds one, so what is photographed is what the shell would load.
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-shots-'))
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
    fs.copyFileSync(path.join(__dirname, 'qml/shot.qml'), path.join(dir, 'shell.qml'))

    // The theme is the only thing reaching out of the isolated HOME: board data,
    // state and images all stay inside it.
    const state = path.join(home, '.local/state/omarchy/current')
    fs.mkdirSync(state, { recursive: true })
    fs.symlinkSync(theme.dir, path.join(state, 'theme'))

    const display = process.env.WAYLAND_DISPLAY || ''
    const result = spawnSync('qs', ['--no-color', '-p', path.join(dir, 'shell.qml')], {
      encoding: 'utf8', timeout: 120000,
      env: { ...process.env, HOME: home, QT_QPA_PLATFORM: 'wayland',
        QT_QPA_PLATFORMTHEME: '', QT_QUICK_CONTROLS_STYLE: 'Basic',
        XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR,
        WAYLAND_DISPLAY: path.isAbsolute(display) ? display
          : path.join(process.env.XDG_RUNTIME_DIR || '', display),
        OMARCHYFORM_SHOT_DIR: out, OMARCHYFORM_TEST_DIR: dir }
    })
    const output = (result.stdout || '') + (result.stderr || '')
    if (!output.includes('SHOTS_DONE')) {
      console.error(output.split('\n').slice(-25).join('\n'))
      return false
    }
    const taken = fs.readdirSync(out).filter(f => f.endsWith('.png'))
    console.log(`${theme.label} (${modeOf(theme.dir)}) — ${taken.length} pictures in ${out}`)
    return true
  } finally { fs.rmSync(dir, { recursive: true, force: true }) }
}

if (!process.env.WAYLAND_DISPLAY) {
  console.error('This needs a running Wayland session: it photographs the real components.')
  process.exit(2)
}
let ok = true
for (const theme of requested) ok = capture(theme) && ok
process.exit(ok ? 0 : 1)
