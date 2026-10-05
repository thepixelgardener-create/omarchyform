#!/usr/bin/env node
// The command line, checked against the loader the plugin itself uses.
//
// The point of `bin/omarchyform` is that something which is not a person can
// build a board and the board will then open. So it is not enough that the CLI
// reads back what it wrote: every board it produces goes through readFile,
// fillItems and fillLinks — the same three calls the plugin makes on the way
// to drawing — and has to come out the other side unchanged.
const fs = require('fs')
const os = require('os')
const path = require('path')
const assert = require('assert/strict')
const { spawnSync } = require('child_process')
const { loadStore, RowModel } = require('../bin/store')

const S = loadStore()
const cli = path.join(__dirname, '..', 'bin', 'omarchyform')
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-cli-'))

// An isolated HOME: the CLI keeps its locks and backups under the library, and
// a suite that writes into the library it is checking is not a suite.
const env = { ...process.env, HOME: dir }

function run(...args) {
  const out = spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8', input: '', env })
  let parsed = null
  try { parsed = JSON.parse(out.stdout) } catch { /* reported by the caller */ }
  return { status: out.status, out: parsed, raw: out.stdout + out.stderr }
}

function pipe(stdin, ...args) {
  const out = spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8', input: stdin, env })
  let parsed = null
  try { parsed = JSON.parse(out.stdout) } catch { /* reported by the caller */ }
  return { status: out.status, out: parsed, raw: out.stdout + out.stderr }
}

// What the plugin does to a file on its way to the screen. If this cannot take
// what the CLI wrote, the board does not open, whatever the CLI reported.
function asThePluginWouldLoad(file) {
  const data = S.readFile(fs.readFileSync(file, 'utf8'))
  assert.ok(data, `${file} is not something readFile accepts`)
  const items = new RowModel()
  const links = new RowModel()
  S.fillItems(items, data.items)
  S.fillLinks(links, items, data.links)
  return { items, links, rows: S.itemRows(items), edges: S.linkRows(links) }
}

try {
  {
    const file = path.join(dir, 'a.json')
    const made = run('new', file, '--note', 'first', '--note', 'second')
    assert.equal(made.status, 0, made.raw)
    assert.equal(made.out.items, 2)

    const loaded = asThePluginWouldLoad(file)
    assert.equal(loaded.items.count, 2, 'the plugin loads both notes')
    assert.deepEqual(loaded.rows.map(r => r.text), ['first', 'second'])
    assert.ok(loaded.rows.every(r => r.kind === 'note' && r.w >= S.MIN_SIZE))
    // Laid out apart rather than stacked: two notes at the same point read as
    // one note on the board.
    assert.notEqual(loaded.rows[0].x, loaded.rows[1].x)
  }

  {
    // It will not write over a board unless told to, because the thing driving
    // it may not have looked first.
    const file = path.join(dir, 'a.json')
    const again = run('new', file, '--note', 'clobber')
    assert.equal(again.status, 1, 'refuses an existing file')
    assert.equal(asThePluginWouldLoad(file).items.count, 2, 'and left it alone')
    assert.equal(run('new', file, '--force', '--note', 'one').status, 0, '--force means it')
    assert.equal(asThePluginWouldLoad(file).items.count, 1)
  }

  {
    const file = path.join(dir, 'b.json')
    run('new', file, '--note', 'one', '--note', 'two')
    const ops = JSON.stringify([
      { op: 'add', args: ['ellipse', 500, 0, 200, 140, 'a shape', 'accent'] },
      { op: 'link', args: [1, 3] },
      { op: 'setText', args: [2, 'changed'] },
      { op: 'setTint', args: [2, 'urgent'] }
    ])
    const applied = pipe(ops, 'apply', file, '-')
    assert.equal(applied.status, 0, applied.raw)
    assert.equal(applied.out.applied[0].added, 3, 'the new id comes back')

    const loaded = asThePluginWouldLoad(file)
    assert.equal(loaded.items.count, 3)
    assert.equal(loaded.edges.length, 1, 'the connector survives the round trip')
    assert.deepEqual(loaded.edges[0], { from: 1, to: 3 })
    const two = loaded.rows.find(r => r.id === 2)
    assert.equal(two.text, 'changed')
    assert.equal(two.tint, 'urgent')
    assert.equal(loaded.rows.find(r => r.id === 3).kind, 'ellipse')
  }

  {
    // Removing an item takes its connectors with it. A connector pointing at
    // nothing is dropped on load, so leaving them would silently lose them —
    // and the count the CLI reported would be a lie.
    const file = path.join(dir, 'c.json')
    run('new', file, '--note', 'a', '--note', 'b', '--note', 'c')
    pipe(JSON.stringify([{ op: 'link', args: [1, 2] }, { op: 'link', args: [2, 3] }]), 'apply', file, '-')
    const after = pipe(JSON.stringify([{ op: 'remove', args: [2] }]), 'apply', file, '-')
    assert.equal(after.out.links, 0, 'both connectors reported gone')
    assert.equal(asThePluginWouldLoad(file).edges.length, 0, 'and gone on disk')
  }

  {
    // Joining a pair the other way round turns it, the way pressing x twice
    // on the board does, rather than leaving two connectors on one pair.
    const file = path.join(dir, 'd.json')
    run('new', file, '--note', 'a', '--note', 'b')
    pipe(JSON.stringify([{ op: 'link', args: [1, 2] }]), 'apply', file, '-')
    const turned = pipe(JSON.stringify([{ op: 'link', args: [2, 1] }]), 'apply', file, '-')
    assert.equal(turned.out.links, 1, 'still one connector')
    assert.equal(turned.out.applied[0].turned, true, 'and it says it turned it')
    assert.deepEqual(asThePluginWouldLoad(file).edges[0], { from: 2, to: 1 })
  }

  {
    // A dry run answers with what would happen and changes nothing.
    const file = path.join(dir, 'e.json')
    run('new', file, '--note', 'only')
    const before = fs.readFileSync(file, 'utf8')
    const dry = pipe(JSON.stringify([{ op: 'add', args: ['rect', 0, 0] }]), 'apply', file, '-', '--dry-run')
    assert.equal(dry.out.items, 2, 'it says what would be there')
    assert.equal(fs.readFileSync(file, 'utf8'), before, 'and the file is untouched')
  }

  {
    // Every failure is a JSON answer and a non-zero exit, because the caller
    // may be a program that only ever reads stdout.
    const file = path.join(dir, 'f.json')
    run('new', file, '--note', 'one')
    const before = fs.readFileSync(file, 'utf8')
    for (const [ops, what] of [
      [[{ op: 'setText', args: [99, 'x'] }], 'an id that is not there'],
      [[{ op: 'nonsense', args: [] }], 'an op that does not exist'],
      [[{ args: [] }], 'an entry with no op'],
      [[{ op: 'add', args: ['hexagon', 0, 0] }], 'a kind that does not exist'],
      [[{ op: 'link', args: [1, 1] }], 'an item pointing at itself'],
      // Names every plain object answers to, which are not operations: each
      // used to find a method on the table and crash with a stack trace.
      ...['toString', 'constructor', '__proto__', 'hasOwnProperty', 'valueOf'].map(name =>
        [[{ op: name, args: [] }], `an op called ${name}`])
    ]) {
      const failed = pipe(JSON.stringify(ops), 'apply', file, '-')
      assert.equal(failed.status, 1, what + ' exits 1')
      assert.ok(failed.out && failed.out.ok === false, what + ' answers with JSON: ' + failed.raw)
      assert.ok(typeof failed.out.error === 'string' && failed.out.error.length > 0, what + ' says why')
    }
    assert.equal(fs.readFileSync(file, 'utf8'), before, 'and none of them changed the board')
    assert.equal(run('apply', file, path.join(dir, 'nope.json')).status, 1, 'missing ops file')
    assert.equal(pipe('not json', 'apply', file, '-').status, 1, 'ops that are not JSON')
    assert.equal(pipe('{"op":"add"}', 'apply', file, '-').status, 1, 'ops that are not a list')
  }

  {
    // inspect and validate describe a board without changing it.
    const file = path.join(dir, 'g.json')
    run('new', file, '--note', 'hello')
    const before = fs.readFileSync(file, 'utf8')
    const seen = run('inspect', file)
    assert.equal(seen.out.items, 1)
    assert.equal(seen.out.contents[0].text, 'hello')
    assert.ok(!('x' in seen.out.contents[0]), 'geometry is left out until asked for')
    assert.ok('x' in run('inspect', file, '--full').out.contents[0], '--full has it')
    assert.equal(run('validate', file).out.version, 5)
    assert.deepEqual(run('validate', file).out.repairs, [], 'a board it wrote needs no repair')
    assert.equal(fs.readFileSync(file, 'utf8'), before, 'neither verb wrote anything')
  }

  {
    // A board from a newer Omarchyform is not a broken one, and must not be
    // reported as though throwing it away were reasonable.
    const file = path.join(dir, 'future.json')
    fs.writeFileSync(file, JSON.stringify({ version: 99, nextId: 1, items: [], links: [] }))
    const future = run('validate', file)
    assert.equal(future.status, 1)
    assert.match(future.out.error, /newer/)
    assert.match(future.out.detail, /read-only/)

    const broken = path.join(dir, 'broken.json')
    fs.writeFileSync(broken, '{ this is not json')
    assert.match(run('validate', broken).out.error, /not a board/)
  }

  {
    // What it repairs on the way in, said out loud: a board is hand-editable
    // and shareable, so the file and what would be drawn can differ.
    const file = path.join(dir, 'damaged.json')
    fs.writeFileSync(file, JSON.stringify({
      version: 5, nextId: 9,
      items: [{ id: 1, kind: 'note', x: 0, y: 0, w: 100, h: 100 }],
      links: [{ from: 1, to: 404 }]
    }))
    const checked = run('validate', file)
    assert.equal(checked.status, 0, 'it still loads')
    assert.equal(checked.out.repairs.length, 1)
    assert.match(checked.out.repairs[0], /connector/)
  }

  {
    // A note can only be so long: the board refuses to open a longer one, so
    // the command line refuses to write one. Through stdin, because an
    // argument this long is past what the kernel will pass to a program.
    const file = path.join(dir, 'long.json')
    run('new', file, '--note', 'short')
    const before = fs.readFileSync(file, 'utf8')
    const long = 'x'.repeat(S.MAX_NOTE_LENGTH + 1)
    for (const [ops, what] of [
      [[{ op: 'setText', args: [1, long] }], 'setText'],
      [[{ op: 'add', args: ['note', 0, 0, 220, 160, long] }], 'add']
    ]) {
      const refused = pipe(JSON.stringify(ops), 'apply', file, '-')
      assert.equal(refused.status, 1, `${what} past the limit exits 1`)
      assert.match(refused.out.error, new RegExp(`^${what}: .*a note holds at most ${S.MAX_NOTE_LENGTH}$`))
    }
    assert.equal(fs.readFileSync(file, 'utf8'), before, 'and the board is untouched')
    const exact = pipe(JSON.stringify([{ op: 'setText', args: [1, 'x'.repeat(S.MAX_NOTE_LENGTH)] }]), 'apply', file, '-')
    assert.equal(exact.status, 0, 'a note exactly at the limit is written: ' + exact.raw.slice(0, 200))

    // One written by something else still loads here, which is how it gets
    // shortened, and validate says why the board will not open it.
    const found = path.join(dir, 'found.json')
    fs.writeFileSync(found, JSON.stringify({ version: 5, nextId: 2, links: [],
      items: [{ id: 1, kind: 'note', x: 0, y: 0, w: 100, h: 100, text: long }] }))
    const checked = run('validate', found)
    assert.equal(checked.status, 0)
    assert.deepEqual(checked.out.repairs, [], 'nothing about it is repaired')
    assert.equal(checked.out.warnings.length, 1)
    assert.match(checked.out.warnings[0], /^item 1 is longer than 1048576 characters; the board opens read-only/)
    assert.equal(pipe(JSON.stringify([{ op: 'setText', args: [1, 'shorter'] }]), 'apply', found, '-').status, 0,
      'and the note can be shortened')
    assert.deepEqual(run('validate', found).out.warnings, [], 'after which there is nothing to say')
  }

  {
    // `ops` is the same table `apply` dispatches through, so the two cannot
    // drift: everything it lists has to actually run.
    const listed = run('ops')
    assert.ok(listed.out.ops.length >= 9)
    const file = path.join(dir, 'h.json')
    run('new', file, '--note', 'a', '--note', 'b')
    for (const entry of listed.out.ops) {
      assert.ok(entry.args && entry.does, `${entry.op} says what it takes and does`)
      const sample = {
        add: ['note', 0, 0], setText: [1, 'x'], setTint: [1, 'accent'], setKind: [1, 'rect'],
        move: [1, 10, 10], resize: [1, 100, 100], pin: [1, true], remove: [2], link: [1, 2],
        unlink: [1, 2]
      }[entry.op]
      assert.ok(sample, `${entry.op} is covered here`)
    }
    assert.deepEqual(listed.out.kinds, S.KINDS, 'kinds come from the board, not a copy')
    assert.deepEqual(listed.out.tints, S.TINTS, 'and so do tints')
  }

  {
    // A board arrives in one step, because the shell watches the file while the
    // board is open: a write anything else can see half of arrives there as a
    // damaged board. And when it cannot be written at all, that is an answer
    // like any other rather than a stack trace, with nothing left beside it.
    const folder = path.join(dir, 'read-only')
    fs.mkdirSync(folder)
    const file = path.join(folder, 'i.json')
    assert.equal(run('new', file).status, 0)
    fs.chmodSync(folder, 0o500)
    try {
      // Skipped where the folder can still be written to — root ignores the
      // mode bits, and a container often runs as root — because otherwise the
      // write succeeds and the check fails without anything being wrong.
      let writable = true
      try { fs.accessSync(folder, fs.constants.W_OK) } catch { writable = false }
      if (writable) {
        console.log('skipped: the unwritable board check needs a user the folder mode can refuse')
      } else {
        const refused = pipe(JSON.stringify([{ op: 'add', args: ['note', 0, 0] }]), 'apply', file)
        assert.equal(refused.status, 1, refused.raw)
        assert.equal(refused.out.ok, false)
        assert.match(refused.out.error, /cannot write/)
        assert.deepEqual(fs.readdirSync(folder), ['i.json'], 'and nothing is left behind')
        // The original is untouched: it was never opened for writing.
        assert.equal(asThePluginWouldLoad(file).rows.length, 0)
      }
    } finally { fs.chmodSync(folder, 0o700) }
  }

  {
    // The previous version is kept, whoever replaced it.
    const file = path.join(dir, 'kept.json')
    run('new', file, '--note', 'first')
    const before = fs.readFileSync(file, 'utf8')
    pipe(JSON.stringify([{ op: 'add', args: ['note', 0, 0, 200, 140, 'second'] }]), 'apply', file)
    assert.equal(asThePluginWouldLoad(file).rows.length, 2)
    assert.equal(fs.readFileSync(file + '.bak', 'utf8'), before, 'the version it replaced is beside it')

    // And `new --force` over an existing board keeps that one too.
    run('new', file, '--force', '--note', 'third')
    assert.equal(asThePluginWouldLoad(file).rows.length, 1)
    assert.equal(asThePluginWouldLoad(file + '.bak').rows.length, 2, 'the two-note board is the backup now')
  }

  {
    // The write that arrives second. Something else takes the lock, changes
    // the board while holding it, and lets go: the CLI read the version before
    // that and has to be told rather than writing over it.
    //
    // The lock is where the plugin's own writes take it, so this is the same
    // serialization both ends use, not a rehearsal of it.
    const file = path.join(dir, 'contested.json')
    run('new', file, '--note', 'original')
    const lock = path.join(dir, '.local/share/omarchyform/locks',
                           encodeURIComponent(path.resolve(file)) + '.lock')
    fs.mkdirSync(path.dirname(lock), { recursive: true })
    const other = JSON.stringify({ kind: 'omarchyform.board', version: 5, nextId: 2,
      items: [{ id: 1, kind: 'note', x: 0, y: 0, w: 180, h: 140, tint: 'foreground',
                text: 'written by somebody else', pinned: false }], links: [] })
    const holder = require('child_process').spawn('bash',
      ['-c', `flock ${JSON.stringify(lock)} -c 'sleep 0.4; printf %s ${JSON.stringify(other)} > ${JSON.stringify(file)}'`],
      { detached: true, stdio: 'ignore' })
    // Long enough for the lock to be held, short enough to be inside the sleep.
    spawnSync('bash', ['-c', 'sleep 0.15'])
    const refused = pipe(JSON.stringify([{ op: 'add', args: ['note', 0, 0] }]), 'apply', file)
    holder.unref()
    assert.equal(refused.status, 1, refused.raw)
    assert.equal(refused.out.ok, false)
    assert.match(refused.out.error, /changed since it was read/)
    assert.match(refused.out.detail, /--force/)
    assert.equal(JSON.parse(fs.readFileSync(file, 'utf8')).items[0].text, 'written by somebody else',
      'and the other writer\'s board is the one on disk')

    // --force is the same explicit overwrite the board itself offers, and it
    // keeps what it replaced.
    const forced = pipe(JSON.stringify([{ op: 'add', args: ['note', 0, 0] }]), 'apply', file, '--force')
    assert.equal(forced.status, 0, forced.raw)
    assert.equal(asThePluginWouldLoad(file).rows.length, 2)
    assert.equal(JSON.parse(fs.readFileSync(file + '.bak', 'utf8')).items[0].text, 'written by somebody else')
  }

  {
    // Two boards in the library that used to share one lock: a board in a
    // folder, and a board whose name is what flattening that folder produced.
    // Each has to get its own, or two unrelated boards wait on each other.
    const boards = path.join(dir, '.local/share/omarchyform/boards')
    fs.mkdirSync(path.join(boards, 'work'), { recursive: true })
    const nested = path.join(boards, 'work/a.json')
    const flat = path.join(boards, 'work__a.json')
    for (const file of [nested, flat]) {
      const made = run('new', file, '--note', 'in the library')
      assert.equal(made.status, 0, made.raw)
    }
    const locks = fs.readdirSync(path.join(dir, '.local/share/omarchyform/locks')).sort()
    assert.ok(locks.includes(S.lockKey('work/a.json') + '.lock'), `nested lock missing from ${locks}`)
    assert.ok(locks.includes(S.lockKey('work__a.json') + '.lock'), `flat lock missing from ${locks}`)
    assert.notEqual(S.lockKey('work/a.json'), S.lockKey('work__a.json'))

    // The lock the plugin would take for the same board. Both ends read the
    // key off BoardStore.js now, so this is the agreement itself rather than a
    // second copy of the rule that could drift away from it.
    const plugin = path.join(dir, '.local/share/omarchyform/locks',
                             S.lockKey('work/a.json') + '.lock')
    assert.ok(fs.existsSync(plugin), 'the CLI took the lock the plugin would take')
  }

  console.log('ok — command line: boards built headlessly, loaded the way the plugin loads them')
} finally {
  fs.rmSync(dir, { recursive: true, force: true })
}
