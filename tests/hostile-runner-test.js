// Exercise the runner's verdict with controlled child-process replies. A CLI
// that exits with a JSON error must not pass a fixture expected to validate,
// and a session that never reads a board again must not pass one that opens.
const assert = require('assert/strict')
const fs = require('fs')
const path = require('path')
const vm = require('vm')
const { fixtures } = require('./hostile-fixtures')
const source = fs.readFileSync(path.join(__dirname, 'hostile.js'), 'utf8')

// `session` is what tests/hostile/session.qml reports, for a board of a
// megabyte or more; undefined runs the runner without qs.
function verdict(name, status, answer, session) {
  const fixture = fixtures.find(f => f.name === name)
  const size = session === undefined ? 0 : 2 * 1024 * 1024
  const output = []
  const exited = {}
  let code = 0
  const report = { open: { frame: 1 }, whole: { frame: 1 }, again: { frame: 1 }, steps: {} }
  const context = {
    __dirname, console: { log() {}, error(s) { output.push(s) } },
    process: { env: {}, argv: ['node', 'hostile.js', name], execPath: process.execPath,
      exit(value) { code = value; throw exited } },
    require(module) {
      if (module === 'fs') return { rmSync() {}, mkdirSync() {}, writeFileSync() {}, copyFileSync() {}, appendFileSync() {},
        existsSync: () => session !== undefined, mkdtempSync: prefix => prefix + 'x', readFileSync: () => '' }
      if (module === 'os') return { tmpdir: () => '/tmp' }
      if (module === 'path') return path
      if (module === './hostile-fixtures') return { fixtures: [{ ...fixture, bytes: () => ({ length: size }) }] }
      if (module === 'child_process') return { spawnSync(command) {
        if (command === process.execPath) return { status, stdout: JSON.stringify(answer), stderr: '' }
        if (command === '/usr/bin/qs') return { status: 0, stdout: 'SESSION ' + JSON.stringify(session), stderr: '' }
        return { status: 0, stdout: 'HOSTILE ' + JSON.stringify(report), stderr: '' }
      } }
      throw new Error('Unexpected dependency: ' + module)
    }
  }
  try { vm.runInNewContext(source, context) } catch (error) { if (error !== exited) throw error }
  return { code, output: output.join('\n') }
}

const success = { ok: true, warnings: [] }
assert.equal(verdict('max-links', 0, success).code, 0)
assert.equal(verdict('max-links', 1, { ok: false, error: 'cannot read board' }).code, 1,
  'an unexpected CLI JSON error fails an accepted board')
assert.equal(verdict('max-links', 1, success).code, 1, 'a nonzero exit cannot claim success')
assert.equal(verdict('max-links', 0, {}).code, 1, 'arbitrary JSON is not validation')
assert.equal(verdict('max-links', 0, { ok: true, warnings: ['unexpected refusal'] }).code, 1)
assert.equal(verdict('one-past-items', 0, {
  ok: true, warnings: ['it has more than 5,000 items; the board opens read-only until there are fewer']
}).code, 0, 'CLI validation deliberately warns about canvas limits')
assert.equal(verdict('one-past-items', 0, success).code, 1, 'a missing limit warning fails')
assert.equal(verdict('future-version', 1, {
  ok: false, error: 'board.json is format 8, newer than this understands'
}).code, 0, 'the expected format refusal passes')
assert.equal(verdict('future-version', 0, success).code, 1, 'accepting a newer version fails')
assert.equal(verdict('future-version', 1, { ok: false, error: 'cannot read board' }).code, 1,
  'an unrelated error cannot stand in for the expected refusal')
assert.equal(verdict('deep-nesting', 1, {
  ok: false, error: 'board.json is not a board this understands'
}).code, 0)

// Through a session: opened, and read again once replaced.
const held = ms => ({ ms: ms + 100, worst: ms })
const opened = (reload, opens) => ({ open: held(100), reload, opens, items: 1, damaged: !opens, conflict: false, saveError: '' })
assert.equal(verdict('max-links', 0, success, opened(held(500), true)).code, 0)
assert.equal(verdict('max-links', 0, success, opened(held(2500), true)).code, 1, 'a reload held past its budget fails')
assert.equal(verdict('max-links', 0, success, opened('never', true)).code, 1, 'a board that opens must be read again')
assert.equal(verdict('max-links', 0, success, opened(null, true)).code, 1)
assert.equal(verdict('max-links', 0, success, opened('refused', true)).code, 1, 'a reload taken for a conflict fails')
assert.equal(verdict('max-links', 0, success, opened(held(500), false)).code, 1, 'a board that should open must')
assert.equal(verdict('one-past-items', 0, {
  ok: true, warnings: ['it has more than 5,000 items; the board opens read-only until there are fewer']
}, opened(null, false)).code, 0, 'a board shown read-only is not read again')
console.log('ok — hostile runner: CLI successes, warnings, refusals and session reloads are checked')
