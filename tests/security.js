#!/usr/bin/env node
// A focused regression screen, not a general static analyzer. See the review
// checklist for boundaries requiring human review and runtime Qt coverage.
const assert = require('assert/strict')
const fs = require('fs'), os = require('os'), path = require('path')
const {spawnSync} = require('child_process')
const {loadStore} = require('./harness')
const root = path.resolve(__dirname, '..')
const S = loadStore()

function qmlPolicy(source) {
  const errors = []
  // These QML files use one object/property per line. A different layout must
  // extend this check before use; do not silently exempt a new text renderer.
  const lines = source.split('\n')
  for (let i = 0; i < lines.length; i++) {
    if (!/\bText\s*\{/.test(lines[i]) || /^\s*\/\//.test(lines[i])) continue
    const start = /^( *)Text \{$/.exec(lines[i])
    if (!start) { errors.push(`line ${i+1}: unsupported Text layout`); continue }
    const pad = start[1]
    const end = lines.findIndex((line, n) => n > i && line === pad + '}')
    const formats = lines.slice(i+1, end).filter(line => line.startsWith(pad+'  textFormat:'))
    if (end < 0 || formats.length !== 1 ||
        !/^\s*textFormat: Text\.(PlainText|StyledText)\s*$/.test(formats[0]))
      errors.push(`line ${i+1}: Text requires explicit PlainText or reviewed StyledText`)
  }
  if (/\bconsole\s*\./.test(source)) errors.push('production QML logging needs privacy review')
  if (/\b(XMLHttpRequest|WebSocket|WebEngineView)\b|\bQt\.(openUrlExternally|createQmlObject)\s*\(|\bQuickshell\.execDetached\s*\(/.test(source))
    errors.push('new network, dynamic QML, or detached execution boundary needs review')
  if (/\b(eval|Function)\s*\(/.test(source)) errors.push('dynamic code execution needs review')
  if (/['"](?:ba)?sh['"]\s*,\s*['"]-c['"]/.test(source)) errors.push('shell source must not be constructed in QML')
  return errors
}

// Prove that the guards reject the regressions they claim to detect.
assert.ok(qmlPolicy('Text {\n  text: userText\n}').length)
assert.ok(qmlPolicy('Text {\n  textFormat: Text.AutoText\n}').length)
assert.ok(qmlPolicy('Text { text: userText }').length)
assert.ok(qmlPolicy('console.log(note)').length)
assert.ok(qmlPolicy('new XMLHttpRequest()').length)
assert.ok(qmlPolicy('command: ["bash", "-c", note]').length)
assert.deepEqual(qmlPolicy('Text {\n  textFormat: Text.PlainText\n}'), [])

function newBoundary(source) {
  return /\b(fetch|XMLHttpRequest|WebSocket)\s*\(|\b(?:require|import)\s*\(?\s*['"](?:node:)?(?:https?|net|tls|dgram|dns|undici|axios|ws)['"]|^\s*import\s+QtWeb|^\s*(?:exec\s+)?(?:curl|wget|ssh|scp|nc|sudo|pkexec)\s/m.test(source)
}
for (const source of ['fetch(url)', 'require("node:https")', 'exec curl "$url"', 'import QtWebEngine'])
  assert.equal(newBoundary(source), true)
const runtimeFiles = fs.readdirSync(root).filter(f => /\.(qml|js|sh)$/.test(f))
for (const folder of ['bin', 'desktop'])
  for (const file of fs.readdirSync(path.join(root, folder)))
    runtimeFiles.push(folder + '/' + file)
for (const file of runtimeFiles)
  assert.equal(newBoundary(fs.readFileSync(path.join(root, file), 'utf8')), false,
    `${file}: network or privilege boundary needs security review`)
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'))
for (const field of ['dependencies', 'optionalDependencies', 'devDependencies'])
  assert.deepEqual(Object.keys(pkg[field] || {}), [], 'new dependencies require security review')
for (const hook of ['preinstall', 'install', 'postinstall', 'prepare'])
  assert.equal(pkg.scripts[hook], undefined, 'new install hooks require security review')

// Deliberate styled renderers: notes escaped by noteMarkup; status escaped by
// escapeMarkup; all others use application-owned hints. Additions need review.
const styledCounts = {'Board.qml': 3, 'Browser.qml': 2, 'Conflict.qml': 1,
  'BoardToolbar.qml': 1, 'Node.qml': 1}
for (const file of fs.readdirSync(root).filter(f => f.endsWith('.qml'))) {
  const source = fs.readFileSync(path.join(root, file), 'utf8')
  assert.deepEqual(qmlPolicy(source), [], file)
  assert.equal((source.match(/textFormat: Text\.StyledText/g)||[]).length,
    styledCounts[file] || 0, `${file}: new styled renderer requires data-flow review`)
}
// Qt's own paste reads everything a clipboard's owner sends before anything
// here can count it, so an owner that never stops sending takes the shell's
// memory. Every field that takes typing hands its paste keys to pasteInto,
// which reads through the helper's 1 MiB limit; a line field also takes the
// middle button, which pastes the primary selection the same way. The note
// editor's middle button is taken by Board.qml's pan surface, above every item.
function pastePolicy(source) {
  const errors = []
  const lines = source.split('\n')
  for (let i = 0; i < lines.length; i++) {
    const start = /^( *)(TextInput|TextEdit) \{$/.exec(lines[i])
    if (!start) {
      if (/\b(TextInput|TextEdit)\s*\{/.test(lines[i]) && !/^\s*\/\//.test(lines[i]))
        errors.push(`line ${i+1}: unsupported text field layout`)
      continue
    }
    const end = lines.findIndex((line, n) => n > i && line === start[1] + '}')
    const field = lines.slice(i + 1, end)
    const body = field.join('\n')
    // The paste keys, accepted, and handed over within the few lines after.
    const keys = field.findIndex(line => /event\.matches\(StandardKey\.Paste\)/.test(line))
    const handled = keys >= 0 && field.slice(keys, keys + 4).join('\n')
    if (end < 0 || !handled || !/event\.accepted = true/.test(handled) || !/\.pasteInto\(/.test(handled))
      errors.push(`line ${i+1}: ${start[2]} must hand its paste keys to pasteInto`)
    if (start[2] === 'TextInput' && !/MouseArea \{[^\n]*acceptedButtons: Qt\.MiddleButton/.test(body))
      errors.push(`line ${i+1}: TextInput must take the middle button from Qt`)
  }
  // exchange.paste() is the board's own, through the helper; any other is Qt's.
  if (/(?<!exchange)\.paste\(\)/.test(source)) errors.push("Qt's own paste reads the clipboard without a limit")
  return errors
}
assert.ok(pastePolicy('  TextInput {\n    text: "x"\n  }').length, 'a field without the paste keys is refused')
assert.ok(pastePolicy('  TextEdit {\n    Keys.onPressed: function (event) {}\n  }').length)
assert.ok(pastePolicy('  TextInput {\n    Keys.onPressed: function (event) {\n      if (event.matches(StandardKey.Paste)) { event.accepted = true; ctl.pasteInto(f); return }\n    }\n  }').length,
  'a line field without the middle guard is refused')
assert.ok(pastePolicy('  TextInput { id: f }').length, 'an unsupported layout is refused rather than skipped')
assert.ok(pastePolicy('editor.paste()').length)
assert.deepEqual(pastePolicy('root.workspace.exchange.paste()'), [], "the board's own paste is the bounded one")
assert.deepEqual(pastePolicy('  TextInput {\n    MouseArea { anchors.fill: parent; acceptedButtons: Qt.MiddleButton }\n' +
  '    Keys.onPressed: function (event) {\n      if (event.matches(StandardKey.Paste)) { event.accepted = true; ctl.pasteInto(f); return }\n    }\n  }'), [])
for (const file of fs.readdirSync(root).filter(f => f.endsWith('.qml')))
  assert.deepEqual(pastePolicy(fs.readFileSync(path.join(root, file), 'utf8')), [], file)
assert.match(fs.readFileSync(path.join(root, 'Board.qml'), 'utf8'),
  /MouseArea \{\n    id: panSurface\n[^}]*acceptedButtons: Qt\.MiddleButton/,
  'the pan surface takes the middle button from every item, the note editor included')

const exchange = fs.readFileSync(path.join(root, 'BoardExchange.qml'), 'utf8')
assert.match(exchange, /fileCommand\("clipcopy", \[\]\)/, 'QML copy helper has no content arguments')
assert.doesNotMatch(exchange, /fileCommand\("clipcopy", \[(?!\])/,
  'no additional copy call may pass content arguments')

// A board from outside names pictures, and those names address this library.
// Every import is staged through withSharedImages, which clears the ones it
// did not carry — including when it carried none and has no images key at all.
function unrewrittenImports(source) {
  const calls = source.match(/\bexchange\.stage(?:Import)?\([^\n]*/g) || []
  if (calls.length === 0) return ['no imported board is staged']
  return calls.filter(call => !/^exchange\.stage(?:Import)?\(Store\.withSharedImages\(/.test(call))
}
assert.ok(unrewrittenImports('if (names.length === 0) { exchange.stage(raw, base, false); return }').length)
assert.ok(unrewrittenImports('exchange.stageImport(raw, base, false)').length)
assert.deepEqual(unrewrittenImports('exchange.stageImport(Store.withSharedImages(raw, {}), base, false)'), [])
assert.ok(unrewrittenImports('').length)
assert.deepEqual(unrewrittenImports(exchange), [], 'an imported board keeps picture names it did not carry')

const colors = {foreground:'#ffffff', accent:'#00ffff', urgent:'#ff0000', muted:'#888888'}
for (const text of ['<img src="https://example.invalid/beacon">',
  '<img src="file:///private.png">', '<a href="https://example.invalid">click</a>',
  '&lt;img src="file:///private.png"&gt;', '*<img src=x>*', '[accent]<img src=x>[/]']) {
  assert.doesNotMatch(S.noteMarkup(text, colors), /<(img|a|iframe|script)\b/i)
  assert.doesNotMatch(S.escapeMarkup(text), /[<>]/)
}
for (const name of ['../private.png', '/private.png', 'file:///private.png',
  'https://example.invalid/x', '..', 'a\nb.png', 'a%2fb.png'])
  assert.equal(S.imageIsValid(name), false, `reject image source ${JSON.stringify(name)}`)
console.log('ok — security: explicit text formats, bounded paste, markup escaping and local image names')

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-security-'))
try {
  const stubs = path.join(dir, 'stubs')
  fs.mkdirSync(stubs)
  const secret = 'privacy-canary-秘密-$HOME-`id`-$(id)\n\n'
  // Capture metadata while both real helper and stub clipboard process live.
  // The sentinel enters only on stdin, including in the test harness.
  fs.writeFileSync(path.join(stubs, 'wl-copy'), `#!/bin/bash
printf '%s' "$#" > "$SCREEN_DIR/argc"
cat /proc/$$/cmdline /proc/$PPID/cmdline > "$SCREEN_DIR/argv"
cat /proc/$$/environ /proc/$PPID/environ > "$SCREEN_DIR/env"
cat > "$SCREEN_DIR/clipboard"
`, {mode:0o755})
  const env = {...process.env, HOME:dir, TMPDIR:dir, SCREEN_DIR:dir, PATH:stubs+':'+process.env.PATH}
  const run = (args, input='') => spawnSync('bash', [path.join(root, 'BoardFiles.sh'), ...args],
    {env, input, encoding:'utf8', timeout:10000, maxBuffer:2*1024*1024})
  function success(result) { assert.ifError(result.error); assert.equal(result.status,0,result.stderr) }
  const copied = run(['clipcopy'], secret)
  success(copied)
  assert.equal(fs.readFileSync(path.join(dir, 'clipboard'),'utf8'),secret)
  assert.equal(fs.readFileSync(path.join(dir, 'argc'),'utf8'),'0')
  for (const name of ['argv', 'env'])
    assert.ok(!fs.readFileSync(path.join(dir,name),'utf8').includes(secret), `private text absent from ${name}`)
  assert.equal(copied.stdout+copied.stderr, '')
  assert.notEqual(run(['clipcopy', 'legacy argument']).status,0)

  fs.writeFileSync(path.join(stubs, 'wl-paste'), '#!/bin/bash\ncat "$SCREEN_DIR/clipboard"\n', {mode:0o755})
  const before = fs.readdirSync(dir).sort()
  const pasted = run(['cliptext'])
  success(pasted)
  assert.equal(pasted.stdout,secret)
  assert.equal(pasted.stderr,'')
  assert.deepEqual(fs.readdirSync(dir).sort(), before, 'clipboard temporary file removed')
  fs.writeFileSync(path.join(dir,'clipboard'),Buffer.alloc(1048577,0x78))
  const oversized = run(['cliptext'])
  assert.equal(oversized.status,5)
  assert.equal(oversized.stdout,'', 'oversized clipboard never reaches QML')
  assert.deepEqual(fs.readdirSync(dir).sort(),before, 'failure removes clipboard temporary file')

  const boards = path.join(dir,'boards'), backups = path.join(dir,'backups')
  fs.mkdirSync(boards); fs.mkdirSync(backups)
  const board = path.join(boards,'private.json'), backup = path.join(backups,'private.bak')
  for (const text of [secret,secret+'changed']) {
    const committed = run(['commit',board,backup,path.join(dir,'board.lock'),'-',boards,backups],text)
    success(committed)
    assert.ok(!(committed.stdout+committed.stderr).includes(secret), 'commit reports metadata only')
  }
  for (const file of [board,backup]) assert.equal(fs.statSync(file).mode & 0o077,0,'new private board and backup modes')
  assert.equal(fs.readFileSync(backup,'utf8'),secret)
  assert.deepEqual(fs.readdirSync(boards),['private.json'],'commit staging is cleaned')

  // Those modes hold under any umask: the files start as mktemp's 0600. What a
  // umask did reach is what the helper makes on the way — folders and locks —
  // so they are checked under the loosest one there is.
  const umask = process.umask(0)
  try {
    const nested = path.join(boards,'folder','nested.json'), nestedBackup = path.join(backups,'folder','nested.bak')
    const lock = path.join(dir,'locks','nested.lock')
    for (const text of [secret,secret+'changed'])
      success(run(['commit',nested,nestedBackup,lock,'-',boards,backups],text))
    success(run(['mkdir',boards,'made']))
    for (const folder of [path.dirname(nested),path.dirname(nestedBackup),path.dirname(lock),path.join(boards,'made')])
      assert.equal(fs.statSync(folder).mode & 0o777,0o700,`helper folder is private under umask 000: ${path.relative(dir,folder)}`)
    for (const file of [nested,nestedBackup,lock])
      assert.equal(fs.statSync(file).mode & 0o077,0,`helper file is private under umask 000: ${path.relative(dir,file)}`)
  } finally { process.umask(umask) }

  const cli = spawnSync(process.execPath,[path.join(root,'bin/omarchyform'),'apply',board,'-'],
    {env,input:'CANARY-private-invalid-operations',encoding:'utf8',timeout:10000})
  assert.ifError(cli.error)
  assert.equal(cli.status,1)
  assert.ok(!(cli.stdout+cli.stderr).includes('CANARY'), 'malformed operations must not echo input')
  assert.deepEqual(JSON.parse(cli.stdout), {ok:false, error:'the operations are not JSON', detail:null})
  console.log('ok — security: process metadata, clipboard limits, cleanup, private writes and CLI errors')
} finally { fs.rmSync(dir,{recursive:true,force:true}) }
console.log('Security regression screen passed. Complete docs/security-review.md before release.')
