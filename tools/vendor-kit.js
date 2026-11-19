#!/usr/bin/env node
// Copy the Omarchy UI kit's Qt Quick parts into kit/, the way the kit itself
// harvests them from the shell: verbatim, with only the imports changed.
//
//   node tools/vendor-kit.js /path/to/omarchy-ui          copy the pinned set
//   node tools/vendor-kit.js /path/to/omarchy-ui --check  say what would change
//
// The kit (github.com/omacom/omarchy-ui, MIT) is a library for apps: its theme
// comes from a small C++ ThemeSource that reads the theme files and asks
// Hyprland. A shell plugin can load no C++, so kit/Theme/ThemeSource.qml stands
// in for it, and Theme.qml fills it from the same files the shell reads.
// Everything else in kit/Theme is the kit's own resolver, so a component here
// draws exactly what it draws in Omarchy Control or the kit's gallery.
//
// Only the components the plugin uses come over, with whatever they use in
// turn. Nothing that types text comes over: the kit's text inputs are
// TextInputs, and every field here is a LineField, for the paste and clipboard
// reasons LineField.qml gives. The copy stops if one would.
'use strict'
const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')

// What the plugin's panels are built from. Their dependencies follow.
const WANTED = ['Toolbar', 'ToolbarSeparator', 'Tooltip', 'ShortcutSheet', 'Keycap', 'KeyCombo',
  'ListRow', 'Dialog', 'Toast', 'Banner', 'SwatchStrip', 'Pane', 'Card', 'ScrollArea',
  'EmptyState', 'Heading', 'CursorModel', 'Button', 'PanelActionButton', 'BorderSurface']
const THEME = ['Border.qml', 'BorderGeometry.js', 'Color.qml', 'I18n.qml', 'Numbers.js',
  'Strings.js', 'Style.qml', 'Tokens.qml', 'Util.qml']
const SINGLETONS = ['Border', 'Color', 'I18n', 'Style', 'Tokens', 'Util', 'ThemeSource']

const repo = path.join(__dirname, '..')
const out = path.join(repo, 'kit')
const args = process.argv.slice(2)
const check = args.includes('--check')
const src = args.find(a => !a.startsWith('--'))
if (!src) {
  console.error('usage: node tools/vendor-kit.js /path/to/omarchy-ui [--check]')
  process.exit(2)
}
const ui = path.join(src, 'qt/qml/Omarchy/Ui')
const theme = path.join(src, 'qt/qml/Omarchy/Theme')
const rev = execFileSync('git', ['-C', src, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim()

// Every kit type a file names, as `Name {` or `Name.member` of a type that exists.
const known = fs.readdirSync(ui).filter(f => f.endsWith('.qml')).map(f => f.slice(0, -4))
function uses(text) {
  return known.filter(name => new RegExp('(^|[^A-Za-z0-9_.])' + name + '\\s*\\{', 'm').test(text))
}
const take = []
const queue = WANTED.slice()
while (queue.length) {
  const name = queue.shift()
  if (take.includes(name)) continue
  if (!known.includes(name)) throw new Error('the kit has no ' + name)
  take.push(name)
  for (const dep of uses(fs.readFileSync(path.join(ui, name + '.qml'), 'utf8')))
    if (!take.includes(dep)) queue.push(dep)
}
take.sort()

function rewriteUi(text, name) {
  if (/\b(TextInput|TextEdit)\b/.test(text))
    throw new Error(name + ' types text; the plugin types only through LineField')
  return text
    .replace(/^import Omarchy\.Theme as (\w+)$/m, 'import "../Theme" as $1')
    .replace(/^import Omarchy\.Theme$/m, 'import "../Theme"')
    .replace(/^import "\.\.\/Theme\/BorderGeometry\.js"/m, 'import "../Theme/BorderGeometry.js"')
    // Qt 6.6 added Shape's curve renderer. Asked for by name, an older Qt
    // (the 6.4 CI runs) cannot load the file at all, and with it every kit
    // border; asked for only where the property exists, a border on 6.4 is
    // drawn by the default renderer instead.
    .replace(/^(\s*)preferredRendererType: Shape\.CurveRenderer\n/m,
      '$1id: curveShape\n$1Component.onCompleted: if ("preferredRendererType" in curveShape) curveShape.preferredRendererType = Shape.CurveRenderer\n')
}
function rewriteTheme(text) {
  return text
    .replace(/^import Omarchy\.Theme as (\w+)$/m, 'import "." as $1')
    .replace(/^import Omarchy\.Theme\.Native\n/m, '')
}

const files = {}
for (const name of take) files['Ui/' + name + '.qml'] = rewriteUi(fs.readFileSync(path.join(ui, name + '.qml'), 'utf8'), name)
for (const f of THEME) {
  const text = fs.readFileSync(path.join(theme, f), 'utf8')
  files['Theme/' + f] = f.endsWith('.qml') ? rewriteTheme(text) : text
}
for (const [f, text] of Object.entries(files))
  if (/Omarchy\.Theme|Omarchy\.Ui/.test(text.split('\n').filter(l => l.startsWith('import')).join('\n')))
    throw new Error(f + ' still imports a kit module by name')
files['Ui/qmldir'] = take.map(n => n + ' 1.0 ' + n + '.qml').join('\n') + '\n'
files['Theme/qmldir'] = SINGLETONS.map(n => 'singleton ' + n + ' 1.0 ' + n + '.qml').join('\n') + '\n'
files['LICENSE'] = fs.readFileSync(path.join(src, 'LICENSE'), 'utf8')
files['KIT_REV'] = rev + '\n'

let changed = 0
for (const [f, text] of Object.entries(files)) {
  const target = path.join(out, f)
  const old = fs.existsSync(target) ? fs.readFileSync(target, 'utf8') : null
  if (old === text) continue
  changed++
  console.log((old === null ? 'new     ' : 'changed ') + 'kit/' + f)
  if (!check) {
    fs.mkdirSync(path.dirname(target), { recursive: true })
    fs.writeFileSync(target, text)
  }
}
// Files a previous copy brought that this one does not. ThemeSource.qml is ours.
for (const dir of ['Ui', 'Theme']) {
  const d = path.join(out, dir)
  if (!fs.existsSync(d)) continue
  for (const f of fs.readdirSync(d)) {
    if (dir === 'Theme' && f === 'ThemeSource.qml') continue
    if (files[dir + '/' + f] !== undefined) continue
    changed++
    console.log('gone    kit/' + dir + '/' + f)
    if (!check) fs.rmSync(path.join(d, f))
  }
}
console.log(changed ? `${changed} file${changed === 1 ? '' : 's'} ${check ? 'would change' : 'changed'} (kit ${rev.slice(0, 7)}, ${take.length} components)`
  : `kit/ is the kit at ${rev.slice(0, 7)}`)
process.exit(check && changed ? 1 : 0)
