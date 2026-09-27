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
for (const file of ["Board.qml", "Node.qml", "Browser.qml", "Help.qml", "BoardToolbar.qml", "BoardExchange.qml", "BoardImage.qml", "ScrollHint.qml"]) {
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
for (const file of ["BoardToolbar.qml", "Help.qml", "Browser.qml", "ScrollHint.qml"])
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
                    "BoardImage.qml", "ScrollHint.qml"]) {
  const source = read(file)
  const rootId = (source.match(/^\s*id:\s*(\w+)\s*$/m) || [])[1]
  if (!rootId) { failures.push(`${file}: no id on the root object to check against`); continue }
  const own = new Set([...declaredMembers(source), ...declaredSignals(source)])
  const called = new Set()
  for (const m of source.matchAll(new RegExp("\\b" + rootId + "\\.(\\w+)\\s*\\(", "g"))) called.add(m[1])
  for (const name of [...called].sort())
    if (!own.has(name) && !inheritedMethods.has(name)) failures.push(`${file}: ${rootId} has no ${name}()`)
}

if (failures.length) {
  for (const line of failures) console.error("  " + line)
  console.error(`FAILED — ${failures.length} missing member(s)`)
  process.exit(1)
}
console.log(`ok — contract: ${controller.size} controller members, ${sessionReads.size} read by the session`)
