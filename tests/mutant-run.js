#!/usr/bin/env node
// Runs the suite against a mutated copy of BoardStore.js.
// Exit 0 = suite still passed (the mutant SURVIVED, which is bad news).
// Exit 1 = suite failed or blew up (the mutant was KILLED, which is good).
//
// Lives in its own process so a mutation that produces an infinite loop can be
// killed by a timeout instead of hanging the whole run.

const fs = require("fs")
const { loadStore } = require("./harness")
// ./run.js, spelled out: `require("./run")` finds the extensionless bash
// script beside it first, and blows up here, above the catch — which
// counted every mutant as killed and made the score a constant 100%.
const { runSuite } = require("./run.js")

try {
  const source = fs.readFileSync(process.argv[2], "utf8")
  const r = runSuite(loadStore(source))
  process.exit(r.failed === 0 ? 0 : 1)
} catch (e) {
  // A mutant that will not even parse or load counts as killed.
  process.exit(1)
}
