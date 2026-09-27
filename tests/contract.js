#!/usr/bin/env node
// The views and the session reach into the controller by name. QML resolves
// those names at runtime, so a missing one is a TypeError in a suite that CI
// cannot run — which is exactly how `autosaveMs` and `backupPathFor` slipped
// past a green PR twice.
//
// This reads the names out of the source and checks three things:
//   - everything the views read off ctl exists on the controller
//   - everything the session reads off ctl exists on the controller
//   - the session test's stub carries the same members the session reads,
//     so the stub cannot quietly fall behind the thing it stands in for

const fs = require("fs")
const path = require("path")

const root = path.join(__dirname, "..")
const read = f => fs.readFileSync(path.join(root, f), "utf8")

// Members declared at the top level of a QML object: two spaces of indent.
function declaredMembers(source) {
  const names = new Set()
  for (const m of source.matchAll(/^ {2}(?:readonly\s+)?property\s+(?:alias\s+)?[\w.<>]+\s+(\w+)/gm))
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

function referenced(source, prefix) {
  const names = new Set()
  const pattern = new RegExp(prefix.replace(/\./g, "\\.") + "([A-Za-z_]\\w*)", "g")
  for (const m of source.matchAll(pattern)) names.add(m[1])
  return names
}

const controller = declaredMembers(read("Omarchyform.qml"))

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

// The session addresses it as session.ctl.
const session = read("BoardSession.qml")
const sessionReads = referenced(session, "session.ctl.")
expect(sessionReads, controller, "the controller", "BoardSession.qml")

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
const layoutStub = nestedMembers(read("tests/qt/tst_layout.qml"), "ctl")
for (const file of ["BoardToolbar.qml", "Help.qml", "Browser.qml", "ScrollHint.qml", "Commands.qml", "Conflict.qml"])
  expect(referenced(read(file), "ctl."), layoutStub, "the tst_layout stub", file)

const nodeReads = referenced(read("Node.qml"), "ctl.")
expect(nodeReads, nestedMembers(read("tests/qt/tst_node.qml"), "ctl"),
  "the tst_node stub", "tests/qt/tst_node.qml")

// PNG export draws the same Node against a stand-in controller of its own. It
// is not the real one, so the checks above never touched it, and a member
// added to Node would have gone missing from every exported image in silence.
expect(nodeReads, nestedMembers(read("BoardImage.qml"), "renderCtl"),
  "the PNG export's renderCtl", "BoardImage.qml")

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
for (const file of ["Omarchyform.qml", "BoardSession.qml", "BoardPersistence.qml", "BoardExchange.qml",
                    "Board.qml", "Node.qml", "Browser.qml", "Help.qml", "BoardToolbar.qml",
                    "BoardImage.qml", "ScrollHint.qml", "Commands.qml", "Conflict.qml"]) {
  const source = read(file)
  const rootId = (source.match(/^\s*id:\s*(\w+)\s*$/m) || [])[1]
  if (!rootId) { failures.push(`${file}: no id on the root object to check against`); continue }
  const own = new Set([...declaredMembers(source), ...declaredSignals(source)])
  const called = new Set()
  for (const m of source.matchAll(new RegExp("\\b" + rootId + "\\.(\\w+)\\s*\\(", "g"))) called.add(m[1])
  for (const name of [...called].sort())
    if (!own.has(name) && !inheritedMethods.has(name)) failures.push(`${file}: ${rootId} has no ${name}()`)
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
  const chord = /^ctrl\+([a-z])$/.exec(command.key)
  if (!chord) continue
  const branch = new RegExp("Key_" + chord[1].toUpperCase() + "\\b[^\\n]*board\\.ctl\\." + command.run + "\\(")
  if (!branch.test(board))
    failures.push(`Board.qml: nothing under ctrl+${chord[1]} runs ${command.run}() for "${command.name}"`)
}

// And every command names a function the controller has.
for (const command of Store.COMMANDS)
  if (!controller.has(command.run))
    failures.push(`BoardStore.js: "${command.name}" runs ${command.run}(), which the controller does not have`)

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

if (failures.length) {
  for (const line of failures) console.error("  " + line)
  console.error(`FAILED — ${failures.length} missing member(s)`)
  process.exit(1)
}
console.log(`ok — contract: ${controller.size} controller members, ${sessionReads.size} read by the session`)
