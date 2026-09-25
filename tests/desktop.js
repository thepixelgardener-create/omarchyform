// The launcher entry lands in a directory shared with every other application,
// so the installer is only allowed to touch a file it wrote itself. These are
// the cases a marketplace review asks about: fresh install, repeat install, a
// conflicting target, a managed file edited by hand, and removal.
const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const script = path.join(__dirname, '../desktop/install.sh')
const shipped = fs.readFileSync(path.join(__dirname, '../desktop/omarchyform.desktop'), 'utf8')
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-desktop-'))
const target = path.join(dir, 'applications/omarchyform.desktop')

// XDG_DATA_HOME is the only thing pointing the installer anywhere, so a test
// run cannot reach the real launcher directory.
const run = (...args) => spawnSync('bash', [script, ...args],
  { encoding: 'utf8', env: { ...process.env, XDG_DATA_HOME: dir } })

try {
  // Fresh install.
  assert.equal(run().status, 0)
  assert.equal(fs.readFileSync(target, 'utf8'), shipped, 'the shipped entry lands verbatim')
  assert.equal(fs.statSync(target).mode & 0o777, 0o644)

  // Repeat install: idempotent, not a conflict with itself.
  assert.equal(run().status, 0, 'installing twice is not an error')
  assert.equal(fs.readFileSync(target, 'utf8'), shipped)

  // A managed entry edited by hand. Local work is not overwritten silently.
  fs.writeFileSync(target, shipped.replace('Name=Omarchyform', 'Name=My Board'))
  const modified = run()
  assert.equal(modified.status, 4)
  assert.match(modified.stderr, /local edits/)
  assert.match(fs.readFileSync(target, 'utf8'), /Name=My Board/, 'the edit survives')
  // ...until it is replaced on purpose.
  assert.equal(run('--force').status, 0)
  assert.equal(fs.readFileSync(target, 'utf8'), shipped)

  // An entry someone else owns, sitting at our path. Never ours to replace.
  const foreign = '[Desktop Entry]\nName=Someone else\nExec=true\n'
  fs.writeFileSync(target, foreign)
  const conflict = run()
  assert.equal(conflict.status, 3)
  assert.match(conflict.stderr, /another launcher entry/)
  assert.equal(fs.readFileSync(target, 'utf8'), foreign, 'their file is untouched')

  // Removal leaves a file we do not own exactly where it is.
  const foreignRemoval = run('--uninstall')
  assert.equal(foreignRemoval.status, 3)
  assert.equal(fs.readFileSync(target, 'utf8'), foreign)

  // Removal of our own entry.
  assert.equal(run('--force').status, 0)
  assert.equal(run('--uninstall').status, 0)
  assert.equal(fs.existsSync(target), false, 'and the file is gone')

  // Removing what is not there is a success, so an uninstall can be repeated.
  const again = run('--uninstall')
  assert.equal(again.status, 0)
  assert.match(again.stdout, /Nothing to remove/)

  // A symlink at the target is not a regular file we wrote; it is someone
  // else's redirection and the installer does not follow it.
  const elsewhere = path.join(dir, 'elsewhere.desktop')
  fs.writeFileSync(elsewhere, foreign)
  fs.symlinkSync(elsewhere, target)
  assert.equal(run().status, 3, 'a symlink is refused rather than written through')
  assert.equal(run('--uninstall').status, 3)
  assert.equal(fs.readFileSync(elsewhere, 'utf8'), foreign, 'and its destination is intact')

  // An unknown argument is a mistake, not an install.
  assert.equal(run('--wipe').status, 2)
} finally { fs.rmSync(dir, { recursive: true, force: true }) }
console.log('ok — desktop entry: ownership, conflicts, local edits and removal')
