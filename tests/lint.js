#!/usr/bin/env node
// Static checks for the scripts that are not QML or the board's JavaScript:
// the file helper (BoardFiles.sh, BoardFiles.py), which does every write,
// backup and clipboard transfer, and the desktop and test scripts beside it.
// The tests run them; this reads all of them, including branches no test
// reaches.
//
//   shellcheck, at every severity, on every tracked shell script. Findings
//   that are meant are disabled on the line with the reason beside them.
//   Python is parsed, not run and not byte-compiled: no __pycache__ is left
//   in the tree.
//
// shellcheck is required where CI or OMARCHYFORM_STRICT is set (npm run
// check:local). Elsewhere a missing one is said loudly and the scripts are
// only syntax-checked with bash -n. SHELLCHECK names another binary.
const { spawnSync } = require('child_process')
const fs = require('fs'), path = require('path')

const root = path.resolve(__dirname, '..')
const tracked = spawnSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8' })
  .stdout.split('\0').filter(f => f && fs.existsSync(path.join(root, f)))

function firstLine(f) {
  const fd = fs.openSync(path.join(root, f), 'r')
  try {
    const buf = Buffer.alloc(128)
    const n = fs.readSync(fd, buf, 0, 128, 0)
    return buf.subarray(0, n).toString('utf8').split('\n')[0]
  } finally { fs.closeSync(fd) }
}

// By extension or by the line that says how it runs, so a new script with no
// extension is not missed.
const shell = tracked.filter(f => f.endsWith('.sh') || /^#!.*\b(ba)?sh\b/.test(firstLine(f)))
const python = tracked.filter(f => f.endsWith('.py') || /^#!.*\bpython3?\b/.test(firstLine(f)))

let failed = 0

const shellcheck = process.env.SHELLCHECK || 'shellcheck'
const sc = spawnSync(shellcheck, ['--version'], { encoding: 'utf8' })
const strict = !!(process.env.CI || process.env.OMARCHYFORM_STRICT)
if (sc.error) {
  if (strict) { console.error('shellcheck is required here and is not installed (pacman -S shellcheck)'); failed++ }
  else {
    console.error(`SKIPPED — shellcheck is not installed; ${shell.length} shell scripts only syntax-checked ` +
                  '(install shellcheck, or set SHELLCHECK)')
    for (const f of shell) {
      const r = spawnSync('bash', ['-n', f], { cwd: root, encoding: 'utf8' })
      if (r.status !== 0) { process.stderr.write(r.stderr); failed++ }
    }
  }
} else {
  const r = spawnSync(shellcheck, ['--format=gcc', ...shell], { cwd: root, encoding: 'utf8' })
  if (r.status !== 0) { process.stderr.write(r.stdout + r.stderr); failed++ }
  else console.log(`ok — shellcheck: ${shell.join(', ')}`)
}

const parse = 'import ast, sys\nfor f in sys.argv[1:]:\n    ast.parse(open(f, "rb").read(), f)\n'
const py = spawnSync('python3', ['-I', '-c', parse, ...python], { cwd: root, encoding: 'utf8' })
if (py.error || py.status !== 0) { process.stderr.write((py.stderr || String(py.error)) + '\n'); failed++ }
else console.log(`ok — python parses: ${python.join(', ')}`)

process.exit(failed ? 1 : 0)
