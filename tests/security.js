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
// parses goes through parseJson, which counts first; only it calls
// JSON.parse. The command line runs in node, whose parser has no such limit.
function bareParse(source, guard) {
  return source.split('\n').map((line, i) => [line, i + 1])
    .filter(([line]) => /\bJSON\.parse\s*\(/.test(line) && !/^\s*\/\//.test(line)
      && !(guard && line === '  return JSON.parse(text)'))
    .map(([, n]) => `line ${n}: JSON.parse outside parseJson can take the shell down; use parseJson`)
}
const guards = ['BoardStore.js']
assert.ok(bareParse('    try { st = JSON.parse(raw) } catch (e) {}').length)
assert.ok(bareParse('  return JSON.parse(text)', false).length, "parseJson's own line, anywhere else")
assert.deepEqual(bareParse('    try { st = Store.parseJson(raw) } catch (e) {}\n  // JSON.parse(text) here'), [])
for (const file of fs.readdirSync(root).filter(f => /\.(qml|js)$/.test(f)))
  assert.deepEqual(bareParse(fs.readFileSync(path.join(root, file), 'utf8'), guards.includes(file)), [], file)
for (const file of guards)
  assert.equal((fs.readFileSync(path.join(root, file), 'utf8').match(/^  return JSON\.parse\(text\)$/gm) || []).length, 1,
    `${file}: JSON.parse is called once, by parseJson`)

// An array written at an item's id is as long as the id, and a two-item board
// can carry id 2,147,483,646. slice(), join(), indexOf(), forEach() and
// JSON.stringify() walk every hole up to the length: the history codec's
// slice() of one held the shell for 25 seconds. Lookups by id, or by a
// connector's end, are plain objects (docs/security-review.md, "Cost trace").
function idIndexedArrays(source) {
  const arrays = new Set([...source.matchAll(/\b(\w+)\s*=\s*\[\]/g)].map(m => m[1]))
  const found = []
  for (const m of source.matchAll(/\b(\w+)\[/g)) {
    if (!arrays.has(m[1])) continue
    let depth = 1, at = m.index + m[0].length
    while (at < source.length && depth > 0) {
      if (source[at] === '[') depth++
      else if (source[at] === ']') depth--
      at++
    }
    const index = source.slice(m.index + m[0].length, at - 1).trim()
    if (/^\s*=(?!=)/.test(source.slice(at)) && /(?:^|\.)(?:i?id|lfrom|lto|from|to)$|Id$/.test(index))
      found.push(`line ${source.slice(0, m.index).split('\n').length}: ${m[1]}[${index}] is an array written at an id; use an object`)
  }
  return found
}
assert.ok(idIndexedArrays('  var rows = []\n  rows[r.id] = r').length, 'the history codec\'s rows')
assert.ok(idIndexedArrays('  var was = []\n  was[before.items[i].id] = before.items[i]').length, 'an id behind an index')
assert.ok(idIndexedArrays('  var seen = []\n  seen[id] = true').length)
assert.ok(idIndexedArrays('  var ends = []\n  ends[l.lto] = l').length, "a connector's end")
assert.deepEqual(idIndexedArrays('  var map = {}\n  map[items.get(i).iid] = i'), [], 'an object is the lookup')
assert.deepEqual(idIndexedArrays('  var rows = []\n  rows[i] = r\n  if (rows[r.id] === r) rows.push(r.id)'), [],
  'positions, reads and pushes are not lengths')
// node walks the holes as well, so the command line is held to it too.
for (const file of [...fs.readdirSync(root).filter(f => /\.(qml|js)$/.test(f)), 'bin/omarchyform', 'bin/store.js'])
  assert.deepEqual(idIndexedArrays(fs.readFileSync(path.join(root, file), 'utf8')), [], file)

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

// What the marketplace's reviewers have raised against other plugins, held
// here as rules: docs/security-review.md, "Before submitting", lists each class
// and where it is checked.
//
// Process arguments are readable by every account through /proc/<pid>/cmdline,
// so nothing private may ride on them: note text, clipboard contents, a whole
// board. Every helper call's arguments are listed here as reviewed: folders,
// paths, board and picture names, generated names and numbers. Contents go on
// stdin or in a staged file in a private folder. A new or changed argument
// fails until it is reviewed and added. (Board and file names are names; they
// appear on command lines as in any program that opens a file.)
function calls(source, fn) {
  const found = []
  for (let at = source.indexOf(fn + '('); at >= 0; at = source.indexOf(fn + '(', at + 1)) {
    let end = at + fn.length + 1, depth = 1
    while (depth && end < source.length) { if (source[end] === '(') depth++; else if (source[end] === ')') depth--; end++ }
    found.push(source.slice(at + fn.length + 1, end - 1).replace(/\s+/g, ' ').trim())
  }
  return found
}
const reviewedArguments = [
  'BoardExchange.qml: "filesize", [path]',
  'BoardExchange.qml: "unbundleimage", [exchange.ctl.imagesDir, bytes.path, "shared-" + Date.now() + "-" + exchange.sharing.at]',
  'BoardExchange.qml: "imagebudget", [exchange.ctl.imagesDir]',
  'BoardExchange.qml: "bundleimages", [exchange.ctl.imagesDir, String(exchange.bundleBudget)].concat(exchange.snapshot.names)',
  'BoardExchange.qml: "clipimage", [exchange.ctl.imagesDir, "paste-" + Date.now()]',
  'BoardExchange.qml: "publish", [exchange.ctl.boardsDir, exchange.baseName, output.path]',
  'BoardExchange.qml: "export", [output.path, exchange.snapshot.destination, exchange.ctl.dataDir]',
  'BoardExchange.qml: "clipcopyimage", [exchange.ctl.imagesDir, only.isrc]',
  'BoardExchange.qml: "clipcopy", []',
  'BoardExchange.qml: "importimage", [next.pane.imagesDir, "drop-" + Date.now() + "-" + exchange.dropSeq, next.path]',
  'BoardExchange.qml: "cliptext", [exchange.ctl.dataDir]',
  'BoardLibrary.qml: "mkdir", [library.boardsDir, dir]',
  'BoardLibrary.qml: "move", [library.boardsDir, e.path, library.boardsDir, target]',
  'BoardLibrary.qml: "purge", [library.trashDir, e.file]',
  'BoardLibrary.qml: "move", [library.boardsDir, e.path, library.trashDir, file]',
  'BoardLibrary.qml: "move", [library.trashDir, e.file, library.boardsDir, e.path]',
  'BoardPane.qml: "export", [root.dataDir + "/.image-export.png", path, root.dataDir]',
  'BoardSession.qml: "snapshot", [session.ctl.boardPath, session.ctl.lockPathFor(session.ctl.currentBoard), session.ctl.boardsDir]',
  'BoardSession.qml: "filesize", [session.ctl.boardPath]',
  'BoardSession.qml: "check", [session.ctl.boardsDir, session.ctl.currentBoard]',
  'Omarchyform.qml: "checkimages", [root.imagesDir]',
  'Omarchyform.qml: "private", [root.dataDir, root.boardsDir, root.backupsDir, root.trashDir, root.imagesDir, root.locksDir]',
  'bin/omarchyform: "revision", [path.resolve(file)]',
  'bin/omarchyform: "commit", [target, aside(target, "backup"), aside(target, "lock"), expected === undefined ? "-" : expected], text',
  'BoardLibrary.qml: ["find", library.boardsDir, "-mindepth", "1", "-printf", "%y\\\\t%P\\\\n"]',
  'Omarchyform.qml: ["cp", "-n", root.legacyPath, root.boardsDir + "/board.json"]'
]
const runtimeQml = fs.readdirSync(root).filter(f => f.endsWith('.qml'))
const usedArguments = []
for (const file of runtimeQml) {
  const source = fs.readFileSync(path.join(root, file), 'utf8')
  for (const call of calls(source, 'fileCommand')) if (call !== 'action, args') usedArguments.push(`${file}: ${call}`)
  for (const m of source.matchAll(/command: (\["(?!bash")[^\n]*\])/g)) usedArguments.push(`${file}: ${m[1]}`)
}
for (const call of calls(fs.readFileSync(path.join(root, 'bin/omarchyform'), 'utf8'), 'helper'))
  if (call !== 'verb, args, input') usedArguments.push(`bin/omarchyform: ${call}`)
assert.deepEqual(usedArguments.filter(a => !reviewedArguments.includes(a)), [],
  'a helper call with arguments not yet reviewed for private contents')
assert.deepEqual(reviewedArguments.filter(a => !usedArguments.includes(a)), [], 'a reviewed call that is gone: take it off the list')
const content = /\b(text|itext|contents|body|clipboard|note|query|needle|secret|token|password|payload)\b/i
assert.deepEqual(reviewedArguments.filter(a => content.test(a.replace(/, text$/, ''))), [],
  'contents never ride on arguments, whatever the list says')
assert.match(fs.readFileSync(path.join(root, 'BoardPersistence.qml'), 'utf8'), /onStarted: \{\n\s*commit\.write\(persistence\.contents\)/,
  'a board goes to the helper on stdin')

// Private files stay private: the helper makes everything 0600 or 0700, the
// plugin's folders are made private by it (existing ones too) rather than by
// a bare mkdir, and the files the shell writes itself go only into them.
assert.match(filesHelper, /^umask 077$/m, 'the helper writes with umask 077')
assert.match(filesHelper, /\n  publish\)\n(?:.*\n)*?    chmod 600 -- "\$staged"\n(?:.*\n)*?    while ! ln -T/, 'an imported board is made private before it has a name')
for (const file of runtimeQml) {
  const source = fs.readFileSync(path.join(root, file), 'utf8')
  assert.ok(!/command: \["mkdir"|\["mkdir",/.test(source), `${file}: folders are made private by the helper, not by mkdir`)
  for (const id of new Set([...source.matchAll(/(\w+)\.setText\(/g)].map(m => m[1]))) {
    const assigned = [...source.matchAll(new RegExp(`\\b${id}\\.path = ([^\\n]+)`, 'g'))].map(m => m[1].trim())
    const declared = (new RegExp(`id: ${id}\\b[^}]*?\\n\\s*path: ([^\\n]+)`).exec(source) || [])[1]
    for (const where of [...assigned, ...(declared ? [declared] : [])].filter(w => w !== '""'))
      assert.match(where, /^(\w+\.)*(dataDir|backupsDir|trashDir|boardsDir|statePath|trashIndexPath)\b/,
        `${file}: ${id} is written by the shell itself, so only into the plugin's private folders`)
  }
}
assert.match(fs.readFileSync(path.join(root, 'Omarchyform.qml'), 'utf8'),
  /command: root\.fileCommand\("private", \[root\.dataDir, root\.boardsDir, root\.backupsDir, root\.trashDir, root\.imagesDir, root\.locksDir\]\)/,
  'every folder of the plugin\'s is made private as the shell starts, the data folder first')

// Nothing is staged in the shared /tmp: every temporary file is made inside a
// folder of the plugin's own, or of the user's choosing.
for (const line of filesHelper.split('\n').filter(l => /\bmktemp\b/.test(l) && !/^\s*#/.test(l)))
  assert.match(line, /mktemp (-p "[^"]+"|-- "[^"]+")/, `a temporary file in a folder of its own: ${line.trim()}`)
for (const file of [...runtimeQml, ...fs.readdirSync(root).filter(f => f.endsWith('.js')), 'bin/omarchyform', 'bin/store.js', 'BoardFiles.sh'])
  assert.ok(!/["'`]\/tmp\b|\btmpdir\(|\$\{?TMPDIR/.test(fs.readFileSync(path.join(root, file), 'utf8')), `${file}: nothing private in the shared /tmp`)

// Nothing listens: no socket another account could connect to.
const listening = /createServer|\.listen\(|SocketServer|LocalServer|WebSocketServer|\bnc\s+-l|\bsocat\b|http\.server|SimpleHTTPRequestHandler/
assert.ok(listening.test('net.createServer(handler).listen(8080)'))
for (const file of runtimeFiles)
  assert.ok(!listening.test(fs.readFileSync(path.join(root, file), 'utf8')), `${file}: a listening socket needs per-user authentication and review`)

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
  const run = (args, input='', extra={}) => spawnSync('bash', [path.join(root, 'BoardFiles.sh'), ...args],
    {env: {...env, ...extra}, input, encoding:'utf8', timeout:10000, maxBuffer:2*1024*1024})
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
  // Staged in the private folder it is given, never the shared /tmp.
  const pasted = run(['cliptext', dir], '', { TMPDIR: '/nonexistent' })
  success(pasted)
  assert.equal(pasted.stdout,secret)
  assert.equal(pasted.stderr,'')
  assert.deepEqual(fs.readdirSync(dir).sort(), before, 'clipboard temporary file removed')
  assert.equal(run(['cliptext']).status === 0, false, 'not without a folder of its own to stage in')
  const shared = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-shared-')); fs.chmodSync(shared, 0o777)
  fs.symlinkSync(dir, path.join(shared, 'link'))
  assert.equal(run(['cliptext', path.join(shared, 'link')]).status, 3, 'nor through a link')
  fs.rmSync(shared, { recursive: true, force: true })
  fs.writeFileSync(path.join(dir,'clipboard'),Buffer.alloc(1048577,0x78))
  const oversized = run(['cliptext', dir])
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
