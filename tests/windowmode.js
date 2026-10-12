// Bar preferences and the W toggle, using the workspace's production functions.
const assert = require('assert/strict')
const fs = require('fs')
const path = require('path')
const vm = require('vm')
const { controller } = require('./workspace-harness')

const payload = startWindowed => JSON.stringify({ settings: { startWindowed } })

// Exercise the real bar payload with both omitted and host-supplied defaults.
const bar = fs.readFileSync(path.join(__dirname, '..', 'BoardBar.qml'), 'utf8')
const barPayload = bar.match(/^  function payload\(\) \{\n([\s\S]*?)^  }/m)[1]
const widget = require('../manifest.json').barWidget
for (const settings of [{}, widget.defaults,
  Object.fromEntries(widget.schema.map(field => [field.key, field.defaultValue]))]) {
  const root = { setting: (key, fallback) => settings[key] === undefined ? fallback : settings[key] }
  const c = controller()
  c.workspace.applyState('')
  c.workspace.applyPayload(vm.runInNewContext(`(function () {${barPayload}})()`, { root }))
  assert.equal(c.workspace.windowMode, true, 'a fresh bar launch opens a tiled window')
}

for (const raw of ['', '{}', '{broken']) {
  const c = controller()
  c.workspace.applyState(raw)
  c.workspace.applyPayload('{}')
  assert.equal(c.workspace.windowMode, true, 'without a saved choice, keyboard launch defaults to tiled')
}
for (const windowed of [true, false]) {
  const c = controller()
  c.workspace.applyState(JSON.stringify({ windowMode: windowed, startWindowed: windowed }))
  c.workspace.applyPayload('{}')
  assert.equal(c.workspace.windowMode, windowed, 'keyboard launch restores an existing saved choice')
  const legacy = controller()
  legacy.workspace.applyState(JSON.stringify({ startWindowed: windowed }))
  assert.equal(legacy.workspace.windowMode, windowed, 'a legacy preference still decides the first surface')
}
console.log('ok — window mode: tiled defaults for bar and keyboard, existing and legacy choices preserved')

for (const windowed of [true, false]) {
  const c = controller()
  c.workspace.applyState(JSON.stringify({ windowMode: !windowed, startWindowed: !windowed }))
  c.workspace.applyPayload(payload(windowed))
  assert.equal(c.workspace.windowMode, windowed, 'a changed bar setting chooses the surface')
  c.workspace.writeState()
  const saved = c.states.at(-1)
  assert.equal(JSON.parse(saved).windowMode, windowed, 'the chosen surface is saved')
  assert.equal(JSON.parse(saved).startWindowed, windowed, 'the bar preference is saved')

  const restarted = controller()
  restarted.workspace.applyState(saved)
  restarted.workspace.applyPayload(payload(windowed))
  assert.equal(restarted.workspace.windowMode, windowed, 'the new mode survives a restart and reopen')

  restarted.workspace.toggleWindowMode()
  assert.equal(restarted.workspace.windowMode, !windowed, 'W still switches modes')
  restarted.workspace.applyPayload(payload(windowed))
  assert.equal(restarted.workspace.windowMode, !windowed, 'an unchanged bar setting preserves W')
  const toggled = controller()
  toggled.workspace.applyState(restarted.states.at(-1))
  toggled.workspace.applyPayload(payload(windowed))
  assert.equal(toggled.workspace.windowMode, !windowed, 'W remains remembered across restarts')
  console.log(`ok — window mode: bar changes to ${windowed ? 'windowed' : 'fullscreen'}, reopens and W`)
}

for (const windowed of [true, false]) {
  const c = controller()
  c.workspace.applyState('')
  c.workspace.applyPayload(payload(windowed))
  assert.equal(c.workspace.windowMode, windowed, 'the bar preference applies on the first open')
  for (const invalid of [undefined, null, 0, 1, 'true', 'false']) {
    c.workspace.applyPayload(payload(invalid))
    assert.equal(c.workspace.windowMode, windowed, 'missing or invalid settings preserve the surface')
    assert.equal(c.workspace.startWindowed, windowed, 'missing or invalid settings preserve the preference')
  }
  c.workspace.applyPayload('{}')
  assert.equal(c.workspace.windowMode, windowed, 'a keyboard summon preserves the surface')
}
console.log('ok — window mode: first open, keyboard summon and invalid settings')
