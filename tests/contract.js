#!/usr/bin/env node
// The views and the session reach into the controller by name. QML resolves
// those names at runtime, so a missing one is a TypeError in a suite that CI
// cannot run — which is exactly how `autosaveMs` and `backupPathFor` slipped
// past a green PR twice.
//
// This reads the names out of the source and checks three things:
//   - everything the views read off ctl exists on the pane, BoardPane.qml,
//     which is the controller every view is given
//   - everything the session reads off ctl exists on the document,
//     BoardDocument.qml, which is the controller the session is given
//   - the session test's stub carries the same members the session reads,
//     so the stub cannot quietly fall behind the thing it stands in for
// and the same of the library, which the views reach as a second object, and
// of the pane, the document and the workspace, which reach into each other.

const fs = require("fs")
const path = require("path")

const root = path.join(__dirname, "..")
const read = f => fs.readFileSync(path.join(root, f), "utf8")

// Members declared at the top level of a QML object: two spaces of indent.
function declaredMembers(source) {
  const names = new Set()
  for (const m of source.matchAll(/^ {2}(?:readonly\s+|required\s+)?property\s+(?:alias\s+)?[\w.<>]+\s+(\w+)/gm))
    names.add(m[1])
  for (const m of source.matchAll(/^ {2}function\s+(\w+)\s*\(/gm)) names.add(m[1])
  return names
}

// Members declared inside a nested block, for the test stub.
function nestedMembers(source, blockId) {
  const start = source.indexOf("id: " + blockId)
  if (start < 0) return new Set()
  const body = source.slice(start)
  const names = new Set()
  for (const m of body.matchAll(/^ {4}(?:readonly\s+)?property\s+(?:alias\s+)?[\w.<>]+\s+(\w+)/gm))
    names.add(m[1])
  for (const m of body.matchAll(/^ {4}function\s+(\w+)\s*\(/gm)) names.add(m[1])
  return names
}

// The body of an object assigned to a property, for a theme that lives inside
// a stub. Braces are matched rather than indentation guessed, so a member that
// sits after the block cannot be counted as part of it.
function blockBody(source, marker) {
  const at = source.indexOf(marker)
  if (at < 0) return ""
  const open = source.indexOf("{", at)
  if (open < 0) return ""
  let depth = 0
  for (let i = open; i < source.length; i++) {
    if (source[i] === "{") depth++
    else if (source[i] === "}" && --depth === 0) return source.slice(open, i)
  }
  return ""
}

function membersAt(body, indent) {
  const pad = " ".repeat(indent)
  const names = new Set()
  for (const m of body.matchAll(new RegExp(`^${pad}(?:readonly\\s+)?property\\s+(?:alias\\s+)?[\\w.<>]+\\s+(\\w+)`, "gm")))
    names.add(m[1])
  for (const m of body.matchAll(new RegExp(`^${pad}function\\s+(\\w+)\\s*\\(`, "gm"))) names.add(m[1])
  return names
}

function referenced(source, prefix) {
  const names = new Set()
  const pattern = new RegExp(prefix.replace(/\./g, "\\.") + "([A-Za-z_]\\w*)", "g")
  for (const m of source.matchAll(pattern)) names.add(m[1])
  return names
}

const controller = declaredMembers(read("BoardPane.qml"))
const documentMembers = declaredMembers(read("BoardDocument.qml"))
const workspaceMembers = declaredMembers(read("Omarchyform.qml"))

const failures = []
function expect(names, available, what, where) {
  for (const name of [...names].sort())
    if (!available.has(name)) failures.push(`${where}: ${what} has no '${name}'`)
}

// The views address the controller as ctl.
for (const file of ["Board.qml", "Node.qml", "Browser.qml", "Help.qml", "BoardToolbar.qml", "BoardExchange.qml", "BoardImage.qml", "ScrollHint.qml", "Commands.qml", "Conflict.qml"]) {
  const source = read(file)
  expect(referenced(source, "ctl."), controller, "the controller", file)
}

// The palette, the fonts and the metrics come off a theme object now rather
// than off the controller, so the same check applies to it: a panel that reads
// a token Theme.qml does not declare is a TypeError on a desktop.
const themeTokens = declaredMembers(read("Theme.qml"))
const themed = ["Board.qml", "Node.qml", "Browser.qml", "Help.qml", "BoardToolbar.qml",
                "BoardImage.qml", "ScrollHint.qml", "Commands.qml", "Conflict.qml", "Surface.qml"]
for (const file of themed) expect(referenced(read(file), "theme."), themeTokens, "Theme.qml", file)

// The session addresses its document as session.ctl.
const session = read("BoardSession.qml")
const sessionReads = referenced(session, "session.ctl.")
expect(sessionReads, documentMembers, "the document", "BoardSession.qml")

// The pane, the document and the workspace reach into each other by name too,
// through whichever handle each holds on the other. Every handle is listed:
// a pane reached as `pane.` in one function and `root.panes[i].` in the next is
// the same object, and a name missing from it is the same TypeError.
function referencedBy(source, pattern) {
  const names = new Set()
  for (const m of source.matchAll(new RegExp(pattern + "\\.([A-Za-z_]\\w*)", "g"))) names.add(m[1])
  return names
}
const pane = read("BoardPane.qml")
const documentSource = read("BoardDocument.qml")
const workspace = read("Omarchyform.qml")
expect(referenced(pane, "root.workspace."), workspaceMembers, "the workspace", "BoardPane.qml")
expect(referenced(pane, "root.doc."), documentMembers, "the document", "BoardPane.qml")
expect(referenced(documentSource, "doc.workspace."), workspaceMembers, "the workspace", "BoardDocument.qml")
expect(referencedBy(documentSource, "\\b(?:pane|panes\\[\\w+\\])"), controller, "the pane", "BoardDocument.qml")
expect(referencedBy(workspace, "(?:root\\.activePane|root\\.panes\\[\\w+\\]|\\bpane|\\bfirst)"), controller,
  "the pane", "Omarchyform.qml")
expect(referencedBy(workspace, "(?:root\\.documents\\[\\w+\\]|\\.doc|\\bdoc)"), documentMembers,
  "the document", "Omarchyform.qml")

// And the stub that stands in for it during the QML session test.
const stub = nestedMembers(read("tests/qml/tst_session.qml"), "ctl")
expect(sessionReads, stub, "the tst_session stub", "tests/qml/tst_session.qml")

// And the stub the exchange runs against while a shared board goes out through
// the real helper script and comes back in.
expect(referenced(read("BoardExchange.qml"), "ctl."),
  nestedMembers(read("tests/qml/tst_exchange.qml"), "ctl"),
  "the tst_exchange stub", "tests/qml/tst_exchange.qml")

// And the stub the Qt layout test puts in its place, which drives the toolbar,
// the help panel and the browser at once. Added after a missing member got
// past every check there was: reading an undefined colour off that stub is
// silent on Qt 6.11 and fatal on the 6.4 CI runs, so the suite was green on
// the machine it was written on and red the moment it was pushed. Which Qt is
// reading the name is not something a check on the names can be wrong about.
//
// It found four more that had been missing all along.
const layoutSource = read("tests/qt/tst_layout.qml")
const layoutStub = nestedMembers(layoutSource, "ctl")
// Its palette is written out rather than instantiated, because Theme.qml reads
// Omarchy's own singletons and that suite runs where there is only Qt. This is
// what keeps the copy honest: everything a panel reads has to be in both.
const layoutTheme = membersAt(blockBody(layoutSource, "property QtObject theme:"), 6)
for (const file of ["BoardToolbar.qml", "Help.qml", "Browser.qml", "ScrollHint.qml", "Commands.qml", "Conflict.qml",
                    "Surface.qml"]) {
  expect(referenced(read(file), "ctl."), layoutStub, "the tst_layout stub", file)
  expect(referenced(read(file), "theme."), layoutTheme, "the tst_layout stub's theme", file)
}

// Help is driven a second time through a rig of its own, with a stub the check
// above never saw because it is a ctl by another name. A member missing from it
// is the same TypeError, in a test that would otherwise pass for the wrong
// reason — which is how this one was found.
const roomy = blockBody(layoutSource, "id: roomyHelp")
const helpReads = read("Help.qml")
// Sliced from the id rather than a brace: the object's own brace opens before
// its id, so there is nothing to match from there.
const rigCtl = roomy.slice(roomy.indexOf("id: c"))
expect(referenced(helpReads, "ctl."), membersAt(rigCtl, 8),
  "the roomyHelp rig's ctl", "tests/qt/tst_layout.qml")
// Help draws its card with Surface, which reads the rig's theme as well.
for (const reads of [helpReads, read("Surface.qml")])
  expect(referenced(reads, "theme."), membersAt(blockBody(roomy, "property QtObject theme:"), 10),
    "the roomyHelp rig's theme", "tests/qt/tst_layout.qml")

// The canvas suite mounts the whole board — the surface, the items on it, the
// header and every panel it hosts — against one stub, so that stub stands in
// for the controller in front of more of the tree than any other. Same reason
// as above: an undefined read there is silent on one Qt and fatal on another.
const panSource = read("tests/qt/tst_pan.qml")
const panStub = nestedMembers(panSource, "ctl")
const panTheme = membersAt(blockBody(panSource, "property QtObject theme:"), 6)
for (const file of ["Board.qml", "Node.qml", "BoardToolbar.qml", "Help.qml", "Browser.qml",
                    "ScrollHint.qml", "Commands.qml", "Conflict.qml", "BoardImage.qml", "Surface.qml"]) {
  expect(referenced(read(file), "ctl."), panStub, "the tst_pan stub", file)
  expect(referenced(read(file), "theme."), panTheme, "the tst_pan stub's theme", file)
}

// The board library is an object of its own, BoardLibrary.qml, and the
// browser, the board, the session and the controller reach into it by name
// the way the views reach into ctl. So the same checks: whatever is read off it
// is declared on it, and on every stub that stands in for it.
const libraryMembers = new Set([...declaredMembers(read("BoardLibrary.qml")), ...declaredSignals(read("BoardLibrary.qml"))])
const libraryReads = {
  "Browser.qml": referenced(read("Browser.qml"), "browser.library."),
  "Board.qml": referenced(read("Board.qml"), "ctl.library."),
  "BoardSession.qml": referenced(session, "session.ctl.library."),
  "BoardPane.qml": referenced(pane, "root.library."),
  "Omarchyform.qml": referenced(workspace, "root.library.")
}
for (const [file, reads] of Object.entries(libraryReads)) expect(reads, libraryMembers, "BoardLibrary.qml", file)
const libraryStub = source => membersAt(blockBody(source, "property QtObject library:"), 6)
expect(libraryReads["Browser.qml"], libraryStub(layoutSource), "the tst_layout stub's library", "Browser.qml")
for (const file of ["Browser.qml", "Board.qml"])
  expect(libraryReads[file], libraryStub(panSource), "the tst_pan stub's library", file)
expect(libraryReads["BoardSession.qml"], libraryStub(read("tests/qml/tst_session.qml")),
  "the tst_session stub's library", "BoardSession.qml")

const nodeReads = referenced(read("Node.qml"), "ctl.")
expect(nodeReads, nestedMembers(read("tests/qt/tst_node.qml"), "ctl"),
  "the tst_node stub", "tests/qt/tst_node.qml")

// PNG export draws the same Node against a stand-in controller of its own. It
// is not the real one, so the checks above never touched it, and a member
// added to Node would have gone missing from every exported image in silence.
expect(nodeReads, nestedMembers(read("BoardImage.qml"), "renderCtl"),
  "the PNG export's renderCtl", "BoardImage.qml")
expect(referenced(read("Node.qml"), "theme."),
  membersAt(blockBody(read("BoardImage.qml"), "property QtObject theme:"), 6),
  "the PNG export's theme", "BoardImage.qml")

// A file also reaches into itself by its own id, and QML resolves that name the
// same way it resolves ctl. — at runtime, in code paths a green suite may never
// take. Three calls to a fail() that was never written sat in BoardExchange
// until a review found them, and each one turned a handled failure into a
// TypeError that left importing busy for the rest of the session.
//
// Only calls are checked. Properties read off an id include everything the base
// type brings with it, which is not in this file to be found; a method call is
// almost always the file's own, and the few that are not are named here.
const inheritedMethods = new Set(["forceActiveFocus", "grabToImage", "mapToItem", "mapFromItem", "destroy"])

function declaredSignals(source) {
  const names = new Set()
  for (const m of source.matchAll(/^ {2}signal\s+(\w+)/gm)) names.add(m[1])
  return names
}

// BoardBar is left out: it extends the shell's own BarWidget, so setting() and
// bar come from a type that is not in this repository.
for (const file of ["Omarchyform.qml", "BoardPane.qml", "BoardDocument.qml", "BoardSession.qml", "BoardPersistence.qml", "BoardExchange.qml", "BoardLibrary.qml",
                    "Board.qml", "Node.qml", "Browser.qml", "Help.qml", "BoardToolbar.qml",
                    "BoardImage.qml", "ScrollHint.qml", "Commands.qml", "Conflict.qml",
                    "Theme.qml", "Surface.qml"]) {
  const source = read(file)
  const rootId = (source.match(/^\s*id:\s*(\w+)\s*$/m) || [])[1]
  if (!rootId) { failures.push(`${file}: no id on the root object to check against`); continue }
  const own = new Set([...declaredMembers(source), ...declaredSignals(source)])
  const called = new Set()
  for (const m of source.matchAll(new RegExp("\\b" + rootId + "\\.(\\w+)\\s*\\(", "g"))) called.add(m[1])
  for (const name of [...called].sort())
    if (!own.has(name) && !inheritedMethods.has(name)) failures.push(`${file}: ${rootId} has no ${name}()`)
}

// The pane, the document and the workspace were one file until the split, and
// a name that moved out of one of them can still be read through its old id:
// `root.dialogOpen` in the fullscreen surface outlived its move to the pane,
// and the only sign was keyboard focus taken while a file dialog was up. These
// three use nothing their base Item brings, so every read through their own id
// is checked, not only calls.
for (const [file, id] of [["Omarchyform.qml", "root"], ["BoardPane.qml", "root"], ["BoardDocument.qml", "doc"]]) {
  const source = read(file)
  const own = new Set([...declaredMembers(source), ...declaredSignals(source)])
  const reads = new Set()
  for (const m of source.matchAll(new RegExp("\\b" + id + "\\.(\\w+)", "g"))) reads.add(m[1])
  for (const name of [...reads].sort())
    if (!own.has(name)) failures.push(`${file}: ${id} has no '${name}'`)
}

// The palette and the keyboard have to agree about which letter does what.
// BoardStore's table carries the label the palette shows and the function it
// dispatches; Board.qml carries what the key actually runs. A key that moved in
// one and not the other would put a lie in the list whose whole job is to teach
// the keys — and nothing else compares the two, because QML resolves both at
// runtime, in a scene CI cannot open.
const Store = require("../bin/store").loadStore()

const keyTable = new Map()
for (const m of read("Board.qml").matchAll(/^\s*"(.+?)": function \(\) \{ board\.ctl\.(\w+)\((.*?)\)/gm))
  keyTable.set(m[1], { run: m[2], arg: m[3].trim() })

// Two keys are spelt differently in a list than they arrive in an event, and
// one is an alias: `=` is `+` without the shift on the keyboards that put it
// there, so both reach the same command.
const spelt = new Map([[" ", "space"], ["=", "+"]])

const byKey = new Map()
for (const command of Store.COMMANDS)
  if (command.key.length === 1 || command.key === "space") byKey.set(command.key, command)

for (const [key, bound] of keyTable) {
  const named = spelt.get(key) || key
  const command = byKey.get(named)
  if (!command) {
    failures.push(`Board.qml: the key "${key}" runs ${bound.run}(), which no command names`)
    continue
  }
  if (command.run !== bound.run)
    failures.push(`Board.qml: "${key}" runs ${bound.run}(), but "${command.name}" says ${command.run}()`)
  // Four commands differ only by what they are handed — which shape to add,
  // which way to move a thing through the stack — so the argument matters as
  // much as the name. Compared only when it is a string: an arithmetic one in
  // the key table is a number by the time the command table has it.
  if (typeof command.arg === "string" && bound.arg.replace(/['"]/g, "") !== command.arg)
    failures.push(`Board.qml: "${key}" runs ${bound.run}(${bound.arg}), but "${command.name}" passes "${command.arg}"`)
}
const reachable = new Set([...keyTable.keys()].map(k => spelt.get(k) || k))
for (const command of byKey.values())
  if (!reachable.has(command.key))
    failures.push(`BoardStore.js: "${command.name}" shows the key "${command.key}", which the board does not bind`)

// The chorded ones live in their own branch rather than the table, so this only
// checks that the branch for that letter reaches the same function. The rest —
// del, F2, enter — are named in KEY_HELP and checked by eye.
const board = read("Board.qml")
for (const command of Store.COMMANDS) {
  const chord = /^(?:ctrl|super)\+([a-z])$/.exec(command.key)
  if (!chord) continue
  if (command.needs === "typing") {
    const editorBranch = new RegExp("Key_" + chord[1].toUpperCase() + "\\b[^\\n]*body\\.markText\\(\"" + command.arg + "\"\\)")
    if (!editorBranch.test(read("Node.qml"))) failures.push("Missing editor chord for " + command.name)
    continue
  }
  const branch = new RegExp("Key_" + chord[1].toUpperCase() + "\\b[^\\n]*board\\.ctl\\." + command.run + "\\(")
  if (!branch.test(board))
    failures.push(`Board.qml: nothing under ctrl+${chord[1]} runs ${command.run}() for "${command.name}"`)
}

// And every command names a function the controller has.
for (const command of Store.COMMANDS)
  if (!controller.has(command.run))
    failures.push(`BoardStore.js: "${command.name}" runs ${command.run}(), which the controller does not have`)

// Severity and subject come from the producer, never from the words. Every
// answer the exchange gives names which operation it is about, so a success can
// take down the failure it recovered from and leave the others alone — and a
// call site that forgets is a failure that either never clears or clears the
// wrong one. Checked here because it is a property of every call site rather
// than of any one path a test happens to take.
function callArguments(source, callee) {
  const calls = []
  let at = 0
  while ((at = source.indexOf(callee + "(", at)) >= 0) {
    let i = at + callee.length + 1
    let depth = 1
    let quote = ""
    for (; i < source.length && depth > 0; i++) {
      const c = source[i]
      if (quote) { if (c === "\\") i++; else if (c === quote) quote = "" }
      else if (c === '"' || c === "'") quote = c
      else if (c === "(") depth++
      else if (c === ")") depth--
    }
    calls.push({ at, text: source.slice(at + callee.length + 1, i - 1) })
    at = i
  }
  return calls
}

// The last argument, whatever the ones before it contain: a message is often a
// sum of strings with commas inside them, so the split has to see through
// quotes and brackets the way the scan above does.
function lastArgument(text) {
  let depth = 0
  let quote = ""
  let cut = -1
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (quote) { if (c === "\\") i++; else if (c === quote) quote = "" }
    else if (c === '"' || c === "'") quote = c
    else if ("([{".includes(c)) depth++
    else if (")]}".includes(c)) depth--
    else if (c === "," && depth === 0) cut = i
  }
  return cut < 0 ? "" : text.slice(cut + 1)
}

const kinds = new Set(Store.FAILURE_KINDS)
function checkKinds(file, callee, allowNone) {
  const source = read(file)
  const found = callArguments(source, callee)
  if (found.length === 0) failures.push(`${file}: nothing calls ${callee}()`)
  for (const call of found) {
    const line = source.slice(0, call.at).split("\n").length
    const tail = lastArgument(call.text)
    // A kind chosen at runtime is still written out: the branches of
    // `atPoint ? "picture" : "clipboard"` are both names to check. What is not
    // allowed is a kind with no literal in it at all, which nothing here can
    // hold to the list.
    const named = [...tail.matchAll(/"([^"]*)"/g)].map(m => m[1])
    if (named.length === 0) {
      // Passing a kind straight through is how the controller forwards what a
      // producer already decided; the producer is checked at its own call.
      if (/^\s*kind\s*$/.test(tail)) continue
      failures.push(`${file}:${line}: ${callee}() ends with no kind that can be read from the source`)
      continue
    }
    for (const kind of named)
      if (!(kind === "" && allowNone) && !kinds.has(kind))
        failures.push(`${file}:${line}: ${callee}() names "${kind}", which is not one of ${[...kinds].join(", ")}`)
  }
}

// A success may recover nothing, and says so with "". A failure is always about
// something: there is no such thing as a failure of no operation.
checkKinds("BoardExchange.qml", "exchange.finished", true)
checkKinds("BoardExchange.qml", "exchange.failed", false)
checkKinds("BoardExchange.qml", "exchange.fail", false)
checkKinds("BoardPane.qml", "root.report", false)

// The live suite walks numbered stages down one if/else chain, so a number used
// twice makes the second one unreachable — and which of the blocks between them
// run at all is then decided by whichever guard the timing happens to satisfy.
// That is how five assertions about pinning stopped running, on a suite that
// went on reporting ok. Nothing in a QML file notices a duplicated number, and
// nothing in a passing run looks different from one that skipped half of it.
//
// The reverse is not a fault: a stage nothing branches on is how that file
// parks while an asynchronous grab is in flight, with the callback setting the
// real next one.
const live = read("tests/qml/tst_omarchy.qml")
const branchedOn = [...live.matchAll(/test\.stage === (\d+)/g)].map(m => m[1])
const seenStage = new Set()
for (const stage of branchedOn) {
  if (seenStage.has(stage))
    failures.push(`tests/qml/tst_omarchy.qml: stage ${stage} is branched on twice, so the second one can never be reached`)
  seenStage.add(stage)
}
const assignedStage = new Set([...live.matchAll(/test\.stage = (\d+)/g)].map(m => m[1]))
for (const stage of seenStage)
  if (stage !== "0" && !assignedStage.has(stage))
    failures.push(`tests/qml/tst_omarchy.qml: stage ${stage} is branched on but nothing ever sets it`)

// An id that is also a property every Item has is a name Qt may resolve two
// ways. `palette` is one: inside a delegate, Qt 6.4 resolves it to the item's
// own palette rather than to the id, and every binding under it then reads off
// undefined — while Qt 6.11 resolves the id and says nothing. That is a green
// suite here and a red one on the version CI runs, which is the same trap the
// name `Palette` set for the file itself.
const reservedIds = new Set([
  "palette", "anchors", "parent", "children", "childrenRect", "visibleChildren",
  "data", "resources", "state", "states", "transitions", "transform", "layer",
  "opacity", "visible", "enabled", "clip", "focus", "activeFocus", "activeFocusOnTab",
  "x", "y", "z", "width", "height", "implicitWidth", "implicitHeight",
  "scale", "rotation", "smooth", "antialiasing", "baselineOffset", "containmentMask"
])

for (const file of [...fs.readdirSync(root).filter(f => f.endsWith(".qml")),
                    ...fs.readdirSync(path.join(root, "tests/qml")).map(f => "tests/qml/" + f),
                    ...fs.readdirSync(path.join(root, "tests/qt")).map(f => "tests/qt/" + f)]) {
  for (const m of read(file).matchAll(/^\s*id:\s*(\w+)\s*$/gm))
    if (reservedIds.has(m[1]))
      failures.push(`${file}: "${m[1]}" is a property every Item has, so it is not a safe id`)
}

// Menu entries dispatch by function name just like palette commands.
for (const entry of [...Store.MENU_COMMANDS, ...Store.ZOOM_COMMANDS]) {
  if (!controller.has(entry.run)) failures.push(`Menu action ${entry.run} is missing`)
}

if (failures.length) {
  for (const line of failures) console.error("  " + line)
  console.error(`FAILED — ${failures.length} missing member(s)`)
  process.exit(1)
}
console.log(`ok — contract: ${controller.size} pane members, ${sessionReads.size} read by the session`)
