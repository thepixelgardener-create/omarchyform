// Qt Quick input/layout tests need no running desktop or Quickshell instance.
const path = require('path')
const { spawnSync } = require('child_process')
const runner = process.env.QMLTESTRUNNER || '/usr/lib/qt6/bin/qmltestrunner'
const result = spawnSync(runner, ['-input', path.join(__dirname, 'qt')], {
  stdio: 'inherit', timeout: 30000,
  env: {...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QPA_PLATFORMTHEME: '',
    QT_QUICK_CONTROLS_STYLE: 'Basic', QT_QUICK_BACKEND: 'software'}
})
if (result.error) console.error(result.error.message)
process.exit(result.status === 0 && !result.error ? 0 : 1)
