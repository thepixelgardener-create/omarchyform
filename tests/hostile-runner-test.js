// Exercise the runner's verdict with controlled child-process replies. A CLI
// that exits with a JSON error must not pass a fixture expected to validate.
const assert = require('assert/strict')
const fs = require('fs')
const path = require('path')
const vm = require('vm')
const { fixtures } = require('./hostile-fixtures')
const source = fs.readFileSync(path.join(__dirname, 'hostile.js'), 'utf8')

function verdict(name, status, answer) {
  const fixture = fixtures.find(f => f.name === name)
  const output = []
  const exited = {}
  let code = 0
  const report = { open: { frame: 1 }, whole: { frame: 1 }, again: { frame: 1 }, steps: {} }
  const context = {
    __dirname, console: { log() {}, error(s) { output.push(s) } },
    process: { env: {}, argv: ['node', 'hostile.js', name], execPath: process.execPath,
      exit(value) { code = value; throw exited } },
    require(module) {
      if (module === 'fs') return { rmSync() {}, mkdirSync() {}, writeFileSync() {} }
      if (module === 'path') return path
      if (module === './hostile-fixtures') return { fixtures: [{ ...fixture, bytes: () => '' }] }
      if (module === 'child_process') return { spawnSync(command) {
        return command === process.execPath
          ? { status, stdout: JSON.stringify(answer), stderr: '' }
          : { status: 0, stdout: 'HOSTILE ' + JSON.stringify(report), stderr: '' }
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
console.log('ok — hostile runner: CLI successes, warnings, and refusals are checked')
