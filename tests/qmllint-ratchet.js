#!/usr/bin/env node
// qmllint, as a ratchet. Most of what it reports here is known and accepted:
// Node.qml stays unbound for Qt 6.4's Loader (see its header), so every outer
// id a delegate reads is "unqualified"; the shell's own types are not visible
// to it at all. Failing on every warning would fail on all of those forever,
// so CI used to fail on one category only and let the rest grow unseen.
//
// This runs the same qmllint over the base commit and over the working tree,
// counts warnings per file and kind, and fails when any count went up. Both
// sides are linted by the same binary on the same machine, so a Qt that
// reports differently (CI has 6.4, a desktop newer) moves both counts alike
// and needs no baseline file kept in step with it.
//
// One kind fails outright, whatever the base had: a property overriding a
// final one stops the shell loading the whole file, and only this sees it
// before a live desktop does.
//
//   node tests/qmllint-ratchet.js [base]
//
// The base is QMLLINT_BASE, else the argument, else where HEAD left
// origin/main (or main).
const { spawnSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const root = path.resolve(__dirname, '..')
const qmllint = process.env.QMLLINT || '/usr/lib/qt6/bin/qmllint'

function git(args, opts) {
  const r = spawnSync('git', args, Object.assign({ cwd: root, encoding: 'utf8' }, opts))
  return r.status === 0 ? r.stdout.trim() : null
}

function baseRef() {
  // A push that opens a branch has no before: forty zeros. Then HEAD's parent.
  const given = process.env.QMLLINT_BASE
  if (given && !/^0+$/.test(given)) return given
  if (given) return git(['rev-parse', 'HEAD~1'])
  if (process.argv[2]) return process.argv[2]
  for (const main of ['origin/main', 'main']) {
    const at = git(['merge-base', 'HEAD', main])
    if (at) return at
  }
  return null
}

// "Warning: Board.qml:12:3: Unqualified access [unqualified]". Older qmllint
// leaves the [kind] off; then the message, with names and numbers taken out,
// stands for it, which is as stable between the two sides as the kind is.
const LINE = /^(Warning|Critical|Info): ([^:]+\.qml):(\d+):(\d+): (.*?)(?: \[([\w.-]+)\])?$/
function kindOf(m) {
  return m[6] || m[5].replace(/"[^"]*"|'[^']*'|\d+/g, '…').trim()
}

function lint(dir) {
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.qml')).sort()
  if (files.length === 0) return { counts: new Map(), lines: [] }
  const r = spawnSync(qmllint, files, { cwd: dir, encoding: 'utf8', maxBuffer: 64 << 20 })
  if (r.error) throw new Error('cannot run ' + qmllint + ': ' + r.error.message)
  const counts = new Map(), lines = []
  for (const text of (r.stdout + '\n' + r.stderr).split('\n')) {
    const m = LINE.exec(text)
    if (!m || m[1] === 'Info') continue
    const key = path.basename(m[2]) + ' · ' + kindOf(m)
    counts.set(key, (counts.get(key) || 0) + 1)
    lines.push({ key, text })
  }
  return { counts, lines }
}

function main() {
  if (!fs.existsSync(qmllint)) {
    console.error(`qmllint is not at ${qmllint}; set QMLLINT, or install Qt's declarative tools`)
    process.exit(2)
  }
  const head = lint(root)

  const overrides = head.lines.filter(l => /property-override|overrid\w* .*final/i.test(l.text))
  if (overrides.length) {
    console.error('A property overrides a final one; the shell would not load the file:')
    for (const l of overrides) console.error('  ' + l.text)
    process.exit(1)
  }

  const base = baseRef()
  if (!base || !git(['rev-parse', '--verify', base + '^{commit}'])) {
    // A copy with no history (an unpacked release) has nothing to compare
    // with: it still gets the final-property check above. Where a base was
    // asked for, or everything must run, a missing one is a failure.
    const required = process.env.QMLLINT_BASE || process.env.OMARCHYFORM_STRICT
    console.error(`${required ? '' : 'SKIPPED — '}no base commit to compare qmllint with (${base || 'none found'}); ` +
                  'fetch main or set QMLLINT_BASE')
    process.exit(required ? 2 : 0)
  }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-qmllint-'))
  try {
    const archive = spawnSync('git', ['archive', '--format=tar', base], { cwd: root, maxBuffer: 1 << 30 })
    if (archive.status !== 0) throw new Error('git archive ' + base + ' failed')
    const untar = spawnSync('tar', ['-x', '-C', dir], { input: archive.stdout })
    if (untar.status !== 0) throw new Error('could not unpack ' + base)
    const before = lint(dir)

    const worse = []
    for (const [key, n] of head.counts) {
      const was = before.counts.get(key) || 0
      if (n > was) worse.push({ key, was, n })
    }
    const better = [...before.counts].filter(([key, n]) => (head.counts.get(key) || 0) < n)
    const total = m => [...m.values()].reduce((a, b) => a + b, 0)
    const summary = `qmllint: ${total(head.counts)} warnings here, ${total(before.counts)} at ${base.slice(0, 12)}`
    if (worse.length) {
      console.error(summary)
      console.error('More warnings than the base has, by file and kind:')
      for (const w of worse) {
        console.error(`  ${w.key}: ${w.was} → ${w.n}`)
        for (const l of head.lines.filter(l => l.key === w.key)) console.error('      ' + l.text)
      }
      console.error('Fix the new ones; the listing shows all of that kind in the file, old and new.')
      process.exit(1)
    }
    console.log(`ok — ${summary}` + (better.length ? `; ${better.length} kind(s) went down` : ''))
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
}

main()
