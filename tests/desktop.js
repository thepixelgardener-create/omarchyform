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
const source = name => fs.readFileSync(path.join(__dirname, '../desktop', name), 'utf8')
const shipped = source('omarchyform.desktop')
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-desktop-'))
const bin = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-bin-'))
const target = path.join(dir, 'applications/omarchyform.desktop')

// Three files, in three shared directories. Every one of them is a place
// another program's file could already be.
const installed = [
  ['omarchyform.desktop', target],
  ['omarchyform.xml', path.join(dir, 'mime/packages/omarchyform.xml')],
  ['omarchyform-open', path.join(bin, 'omarchyform-open')]
]

// Both variables are set, always. XDG_DATA_HOME alone would leave the command
// going to the real ~/.local/bin, and a test suite that installs into the
// machine it is checking is not a test suite.
const run = (...args) => spawnSync('bash', [script, ...args],
  { encoding: 'utf8', env: { ...process.env, XDG_DATA_HOME: dir, XDG_BIN_HOME: bin } })

try {
  // The README tells people to run `./desktop/install.sh`, which only works if
  // the bit survives a clone. It did not, and every user hit permission denied.
  assert.ok(fs.statSync(script).mode & 0o111, 'the installer ships executable')

  // Every shipped file carries the two keys the installer decides ownership by;
  // one missing them could never be replaced or removed again.
  for (const [name] of installed) {
    assert.match(source(name), /X-Omarchyform-Managed=true/, `${name} says it is ours`)
    assert.match(source(name), /X-Omarchyform-Entry-Version=/, `${name} says which version`)
  }
  assert.ok(fs.statSync(path.join(__dirname, '../desktop/omarchyform-open')).mode & 0o111,
    'the opener ships executable')

  // An Exec value is unescaped twice: as a string, where only \s \n \t \r and
  // \\ mean anything, then as a command line, where a quoted argument escapes
  // " ` $ and \ with a backslash. Read here the way the specification reads
  // it, because the New board payload was once written a backslash short:
  // Quickshell warned on every scan and guessed right, and GLib refused the
  // line, so the action did nothing in any GTK launcher.
  function execArgv(line) {
    const strings = { s: ' ', n: '\n', t: '\t', r: '\r', '\\': '\\' }
    let value = ''
    for (let i = 0; i < line.length; i++) {
      if (line[i] !== '\\') { value += line[i]; continue }
      const next = line[++i]
      if (!(next in strings)) throw new Error(`illegal string escape \\${next} in ${line}`)
      value += strings[next]
    }
    const argv = []
    let arg = null, quoted = false
    for (let i = 0; i < value.length; i++) {
      const c = value[i]
      if (quoted) {
        if (c === '\\') {
          const next = value[++i]
          if (!'"`$\\'.includes(next)) throw new Error(`illegal escape \\${next} in a quoted argument`)
          arg += next
        } else if (c === '"') quoted = false
        else arg += c
      } else if (c === ' ') {
        if (arg !== null) { argv.push(arg); arg = null }
      } else if (c === '"') { quoted = true; arg = arg ?? '' }
      else arg = (arg ?? '') + c
    }
    if (quoted) throw new Error(`unterminated quote in ${line}`)
    if (arg !== null) argv.push(arg)
    return argv
  }
  const groups = {}
  let group = null
  for (const line of shipped.split('\n')) {
    const header = line.match(/^\[(.+)\]$/)
    if (header) { group = groups[header[1]] = {}; continue }
    const pair = line.match(/^([A-Za-z0-9-]+)=(.*)$/)
    if (pair && group) group[pair[1]] = pair[2]
  }
  assert.deepStrictEqual(execArgv(groups['Desktop Entry'].Exec), ['omarchyform-open', '%f'])
  assert.deepStrictEqual(execArgv(groups['Desktop Action NewBoard'].Exec),
    ['omarchy-shell', 'shell', 'summon', 'thepixelgardener.omarchyform', '{"action":"new"}'],
    'New board summons the board with its payload, quotes and all')
  assert.throws(() => execArgv('omarchy-shell shell summon thepixelgardener.omarchyform "{\\"action\\":\\"new\\"}"'),
    /illegal string escape/, 'and the line it replaces is refused by the same reading')

  // Fresh install: all three land verbatim, the command executable.
  assert.equal(run().status, 0)
  for (const [name, where] of installed)
    assert.equal(fs.readFileSync(where, 'utf8'), source(name), `${name} lands verbatim`)
  assert.equal(fs.statSync(target).mode & 0o777, 0o644)
  assert.equal(fs.statSync(path.join(bin, 'omarchyform-open')).mode & 0o777, 0o755)

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
  assert.match(conflict.stderr, /already there/)
  assert.equal(fs.readFileSync(target, 'utf8'), foreign, 'their file is untouched')

  // A conflict on any one file stops the whole install: half a feature is
  // worse than none, and a command with no file type to answer for is half.
  const opener = path.join(bin, 'omarchyform-open')
  fs.rmSync(target)
  fs.writeFileSync(opener, '#!/bin/sh\necho someone else\n')
  assert.equal(run().status, 3, 'a conflict anywhere refuses everywhere')
  assert.equal(fs.existsSync(target), false, 'and nothing was written first')
  fs.rmSync(opener)
  fs.writeFileSync(target, foreign)

  // Removal leaves a file we do not own exactly where it is.
  const foreignRemoval = run('--uninstall')
  assert.equal(foreignRemoval.status, 3)
  assert.equal(fs.readFileSync(target, 'utf8'), foreign)

  // Removal of our own files.
  assert.equal(run('--force').status, 0)
  assert.equal(run('--uninstall').status, 0)
  for (const [name, where] of installed)
    assert.equal(fs.existsSync(where), false, `${name} is gone`)

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

  // What the file type is actually for: a file manager telling a board from
  // any other JSON. Skipped where the tools are not installed — a container
  // has neither — because this is about the desktop, not about the code.
  const haveMime = spawnSync('sh', ['-c', 'command -v update-mime-database && command -v gio'],
    { encoding: 'utf8' }).status === 0
  if (!haveMime) {
    console.log('skipped: the file type check needs update-mime-database and gio')
  } else {
    fs.rmSync(target, { force: true })
    assert.equal(run().status, 0)
    // The field, not the output: gio prints the path too, and a temporary
    // directory named after this project matches anything looked for in it.
    const contentType = file => {
      const out = spawnSync('gio', ['info', '-a', 'standard::content-type', file],
        { encoding: 'utf8', env: { ...process.env, XDG_DATA_HOME: dir } }).stdout
      const line = out.split('\n').find(l => l.includes('standard::content-type:'))
      return line ? line.split(':').pop().trim() : ''
    }

    const board = path.join(dir, 'shared.omarchyform.json')
    fs.writeFileSync(board, JSON.stringify({ kind: 'omarchyform.board', version: 5, nextId: 1, items: [], links: [] }))
    assert.equal(contentType(board), 'application/x-omarchyform-board',
      'a shared board is recognised as a board')

    // And a board still named .json is not claimed, because claiming *.json
    // would hand every JSON file on the machine to a note-taking program.
    const plain = path.join(dir, 'ordinary.json')
    fs.writeFileSync(plain, '{"not":"a board"}')
    assert.equal(contentType(plain), 'application/json', 'other JSON is left alone')
    run('--uninstall')
  }

  // The opener hands the shell a JSON payload with the board's path in it. A
  // file name may hold any byte but a slash and NUL, so the path has to come
  // out of JSON.parse exactly as it went in, newlines and all.
  {
    const stubs = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-shell-'))
    const record = path.join(stubs, 'summoned')
    fs.writeFileSync(path.join(stubs, 'omarchy-shell'),
      '#!/usr/bin/env bash\nprintf \'%s\\0\' "$@" > "$SUMMONED"\n', { mode: 0o755 })
    const open = (...args) => {
      fs.rmSync(record, { force: true })
      const out = spawnSync('bash', [path.join(__dirname, '../desktop/omarchyform-open'), ...args], {
        encoding: 'utf8', timeout: 10000,
        env: { ...process.env, PATH: stubs + ':' + process.env.PATH, SUMMONED: record }
      })
      const argv = fs.existsSync(record) ? fs.readFileSync(record, 'utf8').split('\0').slice(0, -1) : []
      return { status: out.status, argv }
    }
    try {
      const bare = open()
      assert.strictEqual(bare.status, 0)
      assert.deepStrictEqual(bare.argv, ['shell', 'summon', 'thepixelgardener.omarchyform', '{}'], 'a bare summon')
      for (const name of ['plain.json', 'say "hi".json', 'back\\slash.json', 'this & that.json',
                          'two\nlines.json', 'tab\there.json', 'bell\x07.json', 'ends in a newline\n']) {
        const file = path.join(stubs, name)
        fs.writeFileSync(file, '{}')
        const opened = open(file)
        assert.strictEqual(opened.status, 0, JSON.stringify(name))
        let payload = null
        try { payload = JSON.parse(opened.argv[3]) } catch { /* reported below */ }
        assert.deepStrictEqual(payload, { action: 'open', path: fs.realpathSync(file) },
          `${JSON.stringify(name)} arrives whole: ${JSON.stringify(opened.argv[3])}`)
      }
      assert.strictEqual(open(path.join(stubs, 'missing.json')).status, 1, 'a board that is not there')
    } finally {
      fs.rmSync(stubs, { recursive: true, force: true })
    }
  }
} finally {
  fs.rmSync(dir, { recursive: true, force: true })
  fs.rmSync(bin, { recursive: true, force: true })
}
console.log('ok — desktop entry: ownership, conflicts, local edits and removal')
