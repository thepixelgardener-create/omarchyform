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

// A payload getter starts Qt's unbounded platform read before any later size
// check. Reject entry and drop without consulting URL, text or raw data getters.
function dropPolicy(source) {
  const errors = []
  for (const match of source.matchAll(/^( *)DropArea \{\n([\s\S]*?)^\1}/gm)) {
    const body = match[2]
    if (!/onEntered: function \(drag\) \{ drag\.accepted = false }/.test(body)
        || !/onDropped: function \(drop\) \{ drop\.accepted = false }/.test(body))
      errors.push('external drag offers must be rejected before payload access')
    if (/\.(urls|text|html|getDataAsString|getDataAsArrayBuffer|acceptProposedAction)\b/.test(body))
      errors.push('a drag handler reads or accepts an unbounded payload')
  }
  return errors
}
assert.ok(dropPolicy('  DropArea {\n    onDropped: function(drop) { use(drop.urls) }\n  }').length)
assert.ok(dropPolicy('  DropArea {\n    onEntered: function (drag) { drag.accepted = false }\n    onDropped: function (drop) { drop.accepted = false }\n    onPositionChanged: use(drag.text)\n  }').length)
for (const file of fs.readdirSync(root).filter(f => f.endsWith('.qml')))
  assert.deepEqual(dropPolicy(fs.readFileSync(path.join(root, file), 'utf8')), [], file)

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
// which reads through the helper's 1 MiB limit: directly, or as a LineField
// whose owner connects pasteRequested to it. The note editor's middle button
// is taken by Board.qml's pan surface, above every item; LineField takes its own.
//
// TextInput is refused outright. In Qt 6.12.0 an editable TextInput reads the
// clipboard's whole text every time the clipboard changes, with nobody pasting
// (QQuickTextInput::q_canPasteChanged calls QMimeData::text()), and no handler
// here runs before that read. TextEdit asks only which formats are offered.
function pastePolicy(source) {
  const errors = []
  const lines = source.split('\n')
  for (let i = 0; i < lines.length; i++) {
    const start = /^( *)(TextInput|TextEdit|LineField) \{$/.exec(lines[i])
    if (!start) {
      if (/\b(TextInput|TextEdit|LineField)\s*\{/.test(lines[i]) && !/^\s*\/\//.test(lines[i]))
        errors.push(`line ${i+1}: unsupported text field layout`)
      continue
    }
    const end = lines.findIndex((line, n) => n > i && line === start[1] + '}')
    const field = lines.slice(i + 1, end)
    const body = field.join('\n')
    if (start[2] === 'TextInput') {
      errors.push(`line ${i+1}: TextInput reads the clipboard on every change in Qt 6.12.0; use LineField`)
      continue
    }
    if (start[2] === 'LineField') {
      if (end < 0 || !/onPasteRequested: [^\n]*\.pasteInto\(/.test(body) || !/\btakesPaste: /.test(body))
        errors.push(`line ${i+1}: a LineField's owner must hand its paste to pasteInto and say when it takes one`)
      continue
    }
    // The paste keys, accepted, and handed over within the few lines after:
    // to pasteInto, or to a pasteRequested signal this field declares.
    const keys = field.findIndex(line => /event\.matches\(StandardKey\.Paste\)/.test(line))
    const handled = keys >= 0 && field.slice(keys, keys + 4).join('\n')
    const handedOver = handled && (/\.pasteInto\(/.test(handled)
      || (/\.pasteRequested\(\)/.test(handled) && /^\s*signal pasteRequested\(\)$/m.test(body)))
    if (end < 0 || !handled || !/event\.accepted = true/.test(handled) || !handedOver)
      errors.push(`line ${i+1}: ${start[2]} must hand its paste keys to pasteInto`)
  }
  // exchange.paste() is the board's own, through the helper; any other is Qt's.
  if (/(?<!exchange)\.paste\(\)/.test(source)) errors.push("Qt's own paste reads the clipboard without a limit")
  return errors
}
const pasteKeys = '    Keys.onPressed: function (event) {\n      if (event.matches(StandardKey.Paste)) { event.accepted = true; ctl.pasteInto(f); return }\n    }\n'
assert.ok(pastePolicy('  TextInput {\n' + pasteKeys + '  }').length, 'a TextInput is refused, however its paste keys go')
assert.ok(pastePolicy('  TextEdit {\n    text: "x"\n  }').length, 'a field without the paste keys is refused')
assert.ok(pastePolicy('  TextEdit {\n    Keys.onPressed: function (event) {}\n  }').length)
assert.ok(pastePolicy('  TextEdit {\n    Keys.onPressed: function (event) {\n      if (event.matches(StandardKey.Paste)) { event.accepted = true; f.pasteRequested(); return }\n    }\n  }').length,
  'a pasteRequested the field does not declare goes nowhere')
assert.ok(pastePolicy('  LineField {\n    takesPaste: true\n  }').length, "a LineField whose paste goes nowhere is refused")
assert.ok(pastePolicy('  LineField {\n    onPasteRequested: ctl.pasteInto(f)\n  }').length, 'and one that never says when it takes one')
assert.ok(pastePolicy('  TextEdit { id: f }').length, 'an unsupported layout is refused rather than skipped')
assert.ok(pastePolicy('editor.paste()').length)
assert.deepEqual(pastePolicy('root.workspace.exchange.paste()'), [], "the board's own paste is the bounded one")
assert.deepEqual(pastePolicy('  TextEdit {\n' + pasteKeys + '  }'), [])
assert.deepEqual(pastePolicy('  LineField {\n    takesPaste: open\n    onPasteRequested: ctl.pasteInto(f)\n  }'), [])
for (const file of fs.readdirSync(root).filter(f => f.endsWith('.qml')))
  assert.deepEqual(pastePolicy(fs.readFileSync(path.join(root, file), 'utf8')), [], file)
// LineField is what the line fields are, and it keeps the middle button from Qt.
const lineField = fs.readFileSync(path.join(root, 'LineField.qml'), 'utf8')
assert.match(lineField, /^TextEdit \{\n(?:.*\n)*?  textFormat: TextEdit\.PlainText\n/m, 'LineField is a plain-text TextEdit')
assert.match(lineField, /\n  MouseArea \{\n(?:    .*\n)*?    acceptedButtons: Qt\.MiddleButton\n/, 'LineField takes the middle button')
assert.match(fs.readFileSync(path.join(root, 'Board.qml'), 'utf8'),
  /MouseArea \{\n    id: panSurface\n[^}]*acceptedButtons: Qt\.MiddleButton/,
  'the pan surface takes the middle button from every item, the note editor included')

// Qt's JSON.parse keeps an array's elements on an engine stack nothing checks,
// and a 1.1 MB file overflows it (Store.MAX_JSON_OPEN). Everything the shell
// parses goes through parseJson, which counts first; only the two copies of
// it call JSON.parse. The command line runs in node, whose parser has no such
// limit.
function bareParse(source, guard) {
  return source.split('\n').map((line, i) => [line, i + 1])
    .filter(([line]) => /\bJSON\.parse\s*\(/.test(line) && !/^\s*\/\//.test(line)
      && !(guard && line === '  return JSON.parse(text)'))
    .map(([, n]) => `line ${n}: JSON.parse outside parseJson can take the shell down; use parseJson`)
}
const guards = ['BoardStore.js', 'BoardHistory.js']
assert.ok(bareParse('    try { st = JSON.parse(raw) } catch (e) {}').length)
assert.ok(bareParse('  return JSON.parse(text)', false).length, "parseJson's own line, anywhere else")
assert.deepEqual(bareParse('    try { st = Store.parseJson(raw) } catch (e) {}\n  // JSON.parse(text) here'), [])
for (const file of fs.readdirSync(root).filter(f => /\.(qml|js)$/.test(f)))
  assert.deepEqual(bareParse(fs.readFileSync(path.join(root, file), 'utf8'), guards.includes(file)), [], file)
for (const file of guards)
  assert.equal((fs.readFileSync(path.join(root, file), 'utf8').match(/^  return JSON\.parse\(text\)$/gm) || []).length, 1,
    `${file}: JSON.parse is called once, by parseJson`)

// A picture that lands in images/ is loaded by Qt in the shell, so each way in
// holds the bytes that land to their pixels and, for a PNG, to the compressed
// text Qt would inflate, before placing them.
function unguardedLandings(script) {
  const errors = []
  for (const op of script.split(/\n  [a-z]+\)\n/).slice(1)) {
    const lands = op.indexOf('place_new "$temporary" "$images_root/')
    if (lands < 0) continue
    for (const guard of ['refuse_huge_pictures "$temporary"', 'refuse_compressed_text "$temporary"'])
      if (op.indexOf(guard) < 0 || op.indexOf(guard) > lands) errors.push(`${op.split('\n')[0].trim()}: ${guard.split(' ')[0]} before it lands`)
  }
  return errors
}
const filesHelper = fs.readFileSync(path.join(root, 'BoardFiles.sh'), 'utf8')
assert.ok(unguardedLandings('case x in\n  addimage)\n    refuse_huge_pictures "$temporary" png\n    place_new "$temporary" "$images_root/x"\n    ;;\n').length,
  'a way in without the text check is refused')
assert.deepEqual(unguardedLandings(filesHelper), [], 'every picture is checked before it lands')
assert.equal((filesHelper.match(/place_new "\$temporary" "\$images_root\//g) || []).length, 3,
  'paste, import and shared pictures; a new way in needs the same checks')
// And one already in the folder, however it got there, is drawn only once
// checkimages has found it fit: imagePath is the only file URL into the
// folder, and it answers one only for a picture pictureState has cleared.
const gate = '    return root.pictureState(name) === "" ? "file://" + root.imagesDir + "/" + name : ""'
function ungatedPictures(sources) {
  const errors = []
  for (const [file, source] of sources)
    source.split('\n').forEach((line, i) => {
      if (/^\s*\/\//.test(line) || (file === 'Omarchyform.qml' && line === gate)) return
      if (/(imagesDir|\/images\/)/.test(line) && /file:|resolvedUrl|Qt\.url|source\s*[:=]/.test(line))
        errors.push(`${file}:${i + 1}: a picture URL that is not imagePath's, which waits for its check`)
    })
  return errors
}
assert.ok(ungatedPictures([['Node.qml', '    source: "file://" + node.ctl.imagesDir + "/" + node.isrc']]).length)
assert.ok(ungatedPictures([['Node.qml', '    picture.source = Qt.resolvedUrl(dataDir + "/images/" + name)']]).length)
assert.ok(ungatedPictures([['Omarchyform.qml', '    return Store.imageIsValid(name) ? "file://" + root.imagesDir + "/" + name : ""']]).length,
  'nor one that does not wait for the check')
assert.deepEqual(ungatedPictures(fs.readdirSync(root).filter(f => /\.(qml|js)$/.test(f))
  .map(f => [f, fs.readFileSync(path.join(root, f), 'utf8')])), [], 'every picture waits for its check')
assert.ok(fs.readFileSync(path.join(root, 'Omarchyform.qml'), 'utf8').includes('  function imagePath(name) {\n' + gate + '\n  }'),
  'imagePath is the gate')

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
