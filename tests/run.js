#!/usr/bin/env node
// Runs the suite against the real BoardStore.js. Exit code 0 = all green.

const { loadStore } = require("./harness")
const { tests } = require("./suite")

function runSuite(Store) {
  const results = { passed: 0, failed: 0, failures: [] }
  for (const t of tests(Store)) {
    try {
      t.fn()
      results.passed++
    } catch (e) {
      results.failed++
      results.failures.push({ name: t.name, message: e.message })
    }
  }
  return results
}

if (require.main === module) {
  const r = runSuite(loadStore())
  for (const f of r.failures) console.log(`  FAIL  ${f.name}\n        ${f.message}`)
  const total = r.passed + r.failed
  console.log(`${r.failed === 0 ? "ok" : "FAILED"} — ${r.passed}/${total} tests passed`)
  process.exit(r.failed === 0 ? 0 : 1)
}

module.exports = { runSuite }
