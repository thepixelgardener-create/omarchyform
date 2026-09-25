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
for (const file of ["Board.qml", "Node.qml", "Browser.qml", "Help.qml", "BoardToolbar.qml", "BoardExchange.qml", "BoardImage.qml"]) {
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

const nodeReads = referenced(read("Node.qml"), "ctl.")
expect(nodeReads, nestedMembers(read("tests/qt/tst_node.qml"), "ctl"),
  "the tst_node stub", "tests/qt/tst_node.qml")

// PNG export draws the same Node against a stand-in controller of its own. It
// is not the real one, so the checks above never touched it, and a member
// added to Node would have gone missing from every exported image in silence.
expect(nodeReads, nestedMembers(read("BoardImage.qml"), "renderCtl"),
  "the PNG export's renderCtl", "BoardImage.qml")

if (failures.length) {
  for (const line of failures) console.error("  " + line)
  console.error(`FAILED — ${failures.length} missing member(s)`)
  process.exit(1)
}
console.log(`ok — contract: ${controller.size} controller members, ${sessionReads.size} read by the session`)
