// Qt Quick input/layout tests need no running desktop or Quickshell instance.
const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')
const { write } = require('./png')
const { unexpectedWarnings } = require('./qt-warnings')
const runner = process.env.QMLTESTRUNNER || '/usr/lib/qt6/bin/qmltestrunner'
// What tst_export.qml photographs: a picture big enough that a board of them
// takes longer to decode than an export used to wait. Made here and thrown away
// afterwards rather than kept in the repository.
const generated = path.join(__dirname, 'qt', 'generated')
fs.rmSync(generated, { recursive: true, force: true })
fs.mkdirSync(generated)
write(path.join(generated, 'slow.png'), 4000, 3000, 0xd02828)
let result
try {
  result = spawnSync(runner, ['-input', path.join(__dirname, 'qt')], {
    encoding: 'utf8', timeout: 30000,
    env: {...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: '',
      QT_QUICK_CONTROLS_STYLE: 'Basic', QT_QUICK_BACKEND: 'software'}
  })
} finally { fs.rmSync(generated, { recursive: true, force: true }) }
const output = (result.stdout || '') + (result.stderr || '')
process.stdout.write(output)
if (result.error) console.error(result.error.message)
const unexpected = unexpectedWarnings(output)
if (unexpected.length) console.error(`\n${unexpected.length} warning${unexpected.length === 1 ? '' : 's'} nobody expected (tests/qt-warnings.js lists the ones that are):\n` + unexpected.join('\n'))
process.exit(result.status === 0 && !result.error && !unexpected.length && !/TypeError|ReferenceError|Binding loop/.test(output) ? 0 : 1)
