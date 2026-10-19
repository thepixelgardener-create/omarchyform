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
        add: ['note', 0, 0], setText: [1, 'x'], setTint: [1, 'accent'], setKind: [1, 'rect'], setTexture: [1, 'grid'],
        move: [1, 10, 10], resize: [1, 100, 100], pin: [1, true], remove: [2], link: [1, 2],
        unlink: [1, 2]
      }[entry.op]
      assert.ok(sample, `${entry.op} is covered here`)
    }
    assert.deepEqual(listed.out.kinds, S.KINDS, 'kinds come from the board, not a copy')
    assert.deepEqual(listed.out.tints, S.TINTS, 'and so do tints')
    assert.deepEqual(listed.out.textures, S.TEXTURES, 'and textures')
    assert.deepEqual([listed.out.maximumItems, listed.out.maximumConnectors], [S.MAX_ITEMS, S.MAX_LINKS],
      'and what a board holds')
  }

  {
    // A board holds so many items and connectors: the board refuses to open
    // more, so the command line refuses to add them.
    const rows = n => Array.from({ length: n }, (_, i) => ({ id: i + 1, kind: 'rect', x: i, y: 0, w: 60, h: 60 }))
    const apply = (file, op, ...args) => pipe(JSON.stringify([{ op, args }]), 'apply', file, '-')
    const full = path.join(dir, 'full.json')
    fs.writeFileSync(full, JSON.stringify({ version: 5, nextId: S.MAX_ITEMS + 1, items: rows(S.MAX_ITEMS), links: [] }))
    const before = fs.readFileSync(full, 'utf8')
    const added = apply(full, 'add', 'note', 0, 0)
    assert.equal(added.status, 1)
    assert.equal(added.out.error, 'add: a board holds at most 5,000 items')
    assert.equal(fs.readFileSync(full, 'utf8'), before, 'and the board is untouched')

    const n = 202
    const links = []
    for (let a = 1; a <= n && links.length < S.MAX_LINKS; a++)
      for (let b = a + 1; b <= n && links.length < S.MAX_LINKS; b++) links.push({ from: a, to: b })
    const joined = path.join(dir, 'joined.json')
    fs.writeFileSync(joined, JSON.stringify({ version: 5, nextId: n + 1, items: rows(n), links }))
    const linked = apply(joined, 'link', n - 1, n)
    assert.equal(linked.status, 1)
    assert.equal(linked.out.error, 'link: a board holds at most 20,000 connectors')
    const turned = apply(joined, 'link', 2, 1)
    assert.equal(turned.status, 0, 'one already there can still be turned round: ' + turned.raw.slice(0, 200))

    // One written by something else is still read here, and validate says
    // why the board will not open it; taking some away is how it is mended.
    const crowded = path.join(dir, 'crowded.json')
    fs.writeFileSync(crowded, JSON.stringify({ version: 5, nextId: S.MAX_ITEMS + 2, items: rows(S.MAX_ITEMS + 1), links: [] }))
    const checked = run('validate', crowded)
    assert.equal(checked.status, 0)
    assert.equal(checked.out.items, S.MAX_ITEMS + 1, 'all of it is read')
    assert.deepEqual(checked.out.warnings, ['it has more than 5,000 items; the board opens read-only until there are fewer'])
    assert.equal(apply(crowded, 'remove', 1).status, 0)
    assert.deepEqual(run('validate', crowded).out.warnings, [], 'after which there is nothing to say')

    // And a file larger than the board will read at all.
    const heavy = path.join(dir, 'heavy.json')
    const small = JSON.stringify({ version: 5, nextId: 1, items: [], links: [] })
    fs.writeFileSync(heavy, small + ' '.repeat(S.MAX_BOARD_BYTES + 1 - small.length))
    assert.deepEqual(run('validate', heavy).out.warnings, ['it is larger than 32 MB; the board opens read-only until it is smaller'])
    fs.truncateSync(heavy, S.MAX_BOARD_BYTES)
    assert.deepEqual(run('validate', heavy).out.warnings, [], 'exactly the limit is not')
  }

  {
    // Nor is one written that large: the board would not open it again.
    const file = path.join(dir, 'growing.json')
    run('new', file, '--note', 'start')
    const before = fs.readFileSync(file, 'utf8')
    const notes = Array.from({ length: 33 }, () => ({ op: 'add', args: ['note', 0, 0, 220, 160, 'x'.repeat(S.MAX_NOTE_LENGTH)] }))
    const grown = pipe(JSON.stringify(notes), 'apply', file, '-')
    assert.equal(grown.status, 1)
    assert.equal(grown.out.error, file + ' would be larger than 32 MB')
    assert.equal(fs.readFileSync(file, 'utf8'), before, 'and the board is untouched')
  }

  {
    // A texture set from the command line is the one the board draws, and a
    // board carrying one is written in the format that keeps it.
    const file = path.join(dir, 'textured.json')
    run('new', file, '--note', 'a', '--note', 'b')
    assert.equal(pipe(JSON.stringify([{ op: 'setTexture', args: [2, 'hatch'] }]), 'apply', file, '-').status, 0)
    const written = JSON.parse(fs.readFileSync(file, 'utf8'))
    assert.equal(written.version, S.FORMAT_VERSION)
    assert.equal(written.items[1].texture, 'hatch')
    assert.equal(written.items[0].texture, undefined, 'plain is not written down')
    const unknown = pipe(JSON.stringify([{ op: 'setTexture', args: [1, 'tartan'] }]), 'apply', file, '-')
    assert.equal(unknown.status, 1, 'a texture this does not know is refused')
    const picture = path.join(dir, 'picture.json')
    fs.writeFileSync(picture, JSON.stringify({ version: 5, nextId: 2, links: [],
      items: [{ id: 1, kind: 'image', x: 0, y: 0, w: 100, h: 100, src: 'a.png' }] }))
    const refused = pipe(JSON.stringify([{ op: 'setTexture', args: [1, 'grid'] }]), 'apply', picture, '-')
    assert.equal(refused.status, 1, 'and so is a picture')
    assert.match(refused.raw, /picture/)
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

  {
    // A board Omarchyform 0.4.7 to 0.4.10 wrote with its history last: there is
    // nothing about it to report, and a run writes the board back without it.
    const file = path.join(dir, 'history.json')
    assert.equal(run('new', file, '--note', 'start').status, 0)
    const plain = fs.readFileSync(file, 'utf8')
    // Where those versions put it: the last key, on one line.
    const withHistory = history => plain.slice(0, -3) + ',\n  "history": ' + history + '\n}\n'
    fs.writeFileSync(file, withHistory('{"v":1,"lineage":"x","start":0,"base":{"items":[],"links":[],"nextId":1},"records":[]}'))
    const validation = run('validate', file)
    assert.equal(validation.status, 0, validation.raw)
    assert.equal(validation.out.history, undefined, 'no history is reported')
    assert.deepEqual(validation.out.warnings, [])
    const applied = pipe(JSON.stringify([{ op: 'add', args: ['note', 300, 0, 220, 160, 'second'] }]), 'apply', file)
    assert.equal(applied.status, 0, applied.raw)
    assert.equal(applied.out.history, undefined)
    const after = JSON.parse(fs.readFileSync(file, 'utf8'))
    assert.equal(after.history, undefined, 'written back without it')
    assert.equal(after.version, 5)
    assert.deepEqual(after.items.map(r => r.text), ['start', 'second'])
    // A history that is not JSON makes a file that is not JSON: refused, and
    // left as it was.
    const broken = withHistory('{"v":1,"records":[')
    fs.writeFileSync(file, broken)
    for (const result of [run('inspect', file), pipe(JSON.stringify([{ op: 'setText', args: [1, 'no'] }]), 'apply', file)]) {
      assert.equal(result.status, 1, result.raw)
      assert.match(result.out.error, /not a board this understands/)
    }
    assert.equal(fs.readFileSync(file, 'utf8'), broken, 'the file is untouched')
    console.log("ok — command line: a board's old history is read with it, and is not written again")
  }

  {
    // A board with its keys in another order, an old history among them: the
    // run changes what it was asked to and nothing else.
    const file = path.join(dir, 'sorted.json')
    assert.equal(run('new', file, '--note', 'one', '--note', 'two').status, 0)
    assert.equal(pipe(JSON.stringify([{ op: 'setTint', args: [1, 'accent'] }]), 'apply', file).status, 0)
    const before = JSON.parse(fs.readFileSync(file, 'utf8'))
    before.history = { v: 1, lineage: 'x', start: 0, base: { items: [], links: [], nextId: 1 }, records: [] }
    const moved = {}
    for (const key of ['kind', 'version', 'history', 'nextId', 'items', 'links']) moved[key] = before[key]
    fs.writeFileSync(file, JSON.stringify(moved, null, 2) + '\n')
    const applied = pipe(JSON.stringify([{ op: 'setText', args: [2, 'changed'] }]), 'apply', file)
    assert.equal(applied.status, 0, applied.raw)
    const after = JSON.parse(fs.readFileSync(file, 'utf8'))
    assert.deepEqual(after.items.map(r => [r.id, r.text, r.tint]), [[1, 'one', 'accent'], [2, 'changed', 'foreground']],
      'the one edit, and every item kept')
    assert.deepEqual(after.links, before.links)
    assert.equal(after.nextId, before.nextId)
    assert.equal(after.history, undefined)
    console.log('ok — command line: a board with its keys in another order loses nothing')

    // A newer format named after the history, on a line of its own or on the
    // history's, with or without a version in front: refused, and the file
    // left exactly as it was. The canvas after it is the canvas.
    const current = fs.readFileSync(file, 'utf8')
    const unversioned = current.replace(/  "version": \d+,\n/, '')
    assert.notEqual(unversioned, current)
    for (const front of [current, unversioned]) for (const gap of ['\n  ', ' ']) {
      const newer = front.slice(0, -3) + ',\n  "history": {"v":1},' + gap + '"version": 8\n}\n'
      fs.writeFileSync(file, newer)
      const refused = pipe(JSON.stringify([{ op: 'setText', args: [1, 'no'] }]), 'apply', file)
      assert.equal(refused.status, 1, refused.raw)
      assert.match(refused.raw, /newer than this understands/)
      assert.equal(fs.readFileSync(file, 'utf8'), newer, 'the file is untouched')
    }
    fs.writeFileSync(file, current.slice(0, -3) + ',\n  "history": {"v":1}, "items": [{"id": 9, "kind": "note", "text": "after"}]\n}\n')
    const inspected = run('inspect', file)
    assert.equal(inspected.status, 0, inspected.raw)
    assert.deepEqual(inspected.out.contents.map(r => r.text), ['after'], 'the items after the history are the items')
    console.log('ok — command line: a key after an old history counts, on any line')
  }

  {
    // Every position and size the command line is given is held to the
    // board's extent and size, and ops says what those are.
    const file = path.join(dir, 'limits.json')
    assert.equal(run('new', file).status, 0)
    const ops = run('ops').out
    assert.deepEqual([ops.maximumSize, ops.maximumCoordinate], [S.MAX_SIZE, S.MAX_COORD])
    const applied = pipe(JSON.stringify([{ op: 'add', args: ['ellipse', 1e300, -1e300, 1e300, 1] },
      { op: 'add', args: ['note', 0, 0] }, { op: 'move', args: [2, -1.7e308, 5] }, { op: 'resize', args: [2, 1e9, 1e9] }]),
      'apply', file)
    assert.equal(applied.status, 0, applied.raw)
    // What loading has to bring within the board, validate says.
    const wild = path.join(dir, 'wild.json')
    fs.writeFileSync(wild, JSON.stringify({ version: 5, nextId: 3, links: [], items: [
      { id: 1, kind: 'note', x: 1e300, y: 0, w: 220, h: 160 }, { id: 2, kind: 'note', x: 0, y: 0, w: 1e9, h: 160 }] }))
    assert.deepEqual(run('validate', wild).out.repairs, ["2 item(s) were brought within the board's size and extent"])
    // As written, not as the plugin would read it back: reading clamps as well.
    assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')).items.map(r => [r.x, r.y, r.w, r.h]),
      [[S.MAX_COORD, -S.MAX_COORD, S.MAX_SIZE, S.MIN_SIZE], [-S.MAX_COORD, 5, S.MAX_SIZE, S.MAX_SIZE]])
    console.log('ok — command line: positions and sizes stay within the board')
  }

  {
    // A board that came with an item at the largest id there is: what a run
    // adds gets ids the board keeps, so it and its connectors survive the
    // board being opened again.
    const file = path.join(dir, 'ceiling.json')
    const note = (id, x) => ({ id, kind: 'note', x, y: 0, w: 220, h: 160, tint: 'foreground', text: 'note ' + id })
    fs.writeFileSync(file, JSON.stringify({ version: 5, nextId: 7, items: [note(2, 0), note(S.MAX_ID, 300)],
                                            links: [{ from: 2, to: S.MAX_ID }] }, null, 2) + '\n')
    const applied = pipe(JSON.stringify([{ op: 'add', args: ['note', 0, 300] }, { op: 'add', args: ['note', 300, 300] },
      { op: 'link', args: [1, 3] }, { op: 'link', args: [S.MAX_ID, 1] }]), 'apply', file)
    assert.equal(applied.status, 0, applied.raw)
    assert.deepEqual(applied.out.applied.filter(r => r.op === 'add').map(r => r.added), [1, 3],
      'the smallest ids no item has')
    const loaded = asThePluginWouldLoad(file)
    assert.deepEqual(S.itemRows(loaded.items).map(r => r.id), [2, S.MAX_ID, 1, 3], 'every id kept on the way in')
    assert.equal(loaded.links.count, 3, 'and every connector')
    assert.ok(S.nextFreeId(loaded.items, JSON.parse(fs.readFileSync(file, 'utf8')).nextId) <= S.MAX_ID + 1)
    console.log('ok — command line: a board at the largest id still gets ids it keeps')
  }

  {
    // A flag that takes a value, given none. `apply --out` fell out of
    // path.resolve with a stack trace; every failure answers in JSON.
    const file = path.join(dir, 'flags.json')
    assert.equal(run('new', file, '--note', 'one').status, 0)
    const before = fs.readFileSync(file, 'utf8')
    for (const [args, what] of [
      [['apply', file, '-', '--out'], '--out with nothing after it'],
      [['apply', file, '-', '--out', '--dry-run'], '--out followed by another flag'],
      [['new', path.join(dir, 'flags-new.json'), '--note'], '--note with no text']
    ]) {
      const failed = pipe('[]', ...args)
      assert.equal(failed.status, 1, what + ' exits 1')
      assert.ok(failed.out && failed.out.ok === false && /needs/.test(failed.out.error), what + ' answers with JSON: ' + failed.raw)
    }
    assert.equal(fs.readFileSync(file, 'utf8'), before, 'the board is unchanged')
    assert.equal(fs.existsSync(path.join(dir, 'flags-new.json')), false, 'and nothing new is written')
    const dashes = run('new', path.join(dir, 'dashes.json'), '--note', '--- divider ---')
    assert.equal(dashes.status, 0, "a note's text may look like a flag")
    assert.equal(dashes.out.items, 1)
    console.log('ok — command line: a flag with no value is refused, as JSON')
  }

  {
    // Without Python the helper cannot start: the answer is still JSON, says
    // what is missing, and the board is left as it was.
    const file = path.join(dir, 'no-python.json')
    run('new', file, '--note', 'kept')
    const before = fs.readFileSync(file, 'utf8')
    const empty = fs.mkdtempSync(path.join(dir, 'path-'))
    const out = spawnSync(process.execPath, [cli, 'apply', file], { encoding: 'utf8',
      input: JSON.stringify([{ op: 'add', args: ['note', 0, 300] }]), env: { ...env, PATH: empty } })
    const answer = JSON.parse(out.stdout)
    assert.equal(out.status, 1)
    assert.equal(answer.ok, false)
    assert.equal(answer.error, 'python3 not found', out.stdout)
    assert.equal(fs.readFileSync(file, 'utf8'), before, 'the board is untouched')
    console.log('ok — command line: a missing python3 is named, as JSON')
  }
} finally {
  fs.rmSync(dir, { recursive: true, force: true })
}
