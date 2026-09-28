const assert = require('assert/strict')
const { EventEmitter } = require('events')
const { runHeld } = require('./held-runner')

const ready = 'console.log("SHOTS_DONE"); console.log("SHOTS_HOLDING")'
const done = 'console.log("SHOTS_HELD_DONE")'
async function scenario(name, source, expected, options = {}) {
  const signals = new EventEmitter(), lines = []
  let pid
  const code = await runHeld(process.execPath, ['-e', source], {
    signals, setupMs: 1500, killMs: 50, ...options,
    output(line) {
      lines.push(line)
      const match = /^SHOTS_CHILD_PID (\d+)$/.exec(line)
      if (match) pid = Number(match[1])
      if (options.interrupt && line === 'SHOTS_HOLDING') signals.emit(options.interrupt)
    }
  })
  assert.equal(code, expected, `${name}: ${lines.join('\n')}`)
  assert.equal(signals.listenerCount('SIGINT'), 0, name + ': SIGINT listener removed')
  assert.equal(signals.listenerCount('SIGTERM'), 0, name + ': SIGTERM listener removed')
  assert.ok(pid, name + ': exact child PID recorded')
  assert.throws(() => process.kill(pid, 0), { code: 'ESRCH' }, name + ': child reaped')
  console.log('ok — held runner: ' + name)
}

async function main() {
  await scenario('ready and completed', `${ready}; ${done}`, 0)
  await scenario('zero exit without readiness', '', 1)
  await scenario('timeout despite zero exit', 'console.log("SHOTS_TIMEOUT at scene 0")', 1)
  await scenario('ready without completion', ready, 1)
  await scenario('completion before readiness', `${done}; ${ready}`, 1)
  await scenario('explicit failure', `${ready}; console.log("SHOTS_HELD_FAILED bad write")`, 1)
  await scenario('nonzero exit after completion', `${ready}; ${done}; process.exitCode=2`, 1)
  await scenario('unexpected termination', `${ready}; process.kill(process.pid, 'SIGTERM')`, 1)
  await scenario('SIGINT is cancellation', `${ready}; setInterval(() => {}, 1000)`, 130,
    { interrupt: 'SIGINT' })
  await scenario('SIGTERM is cancellation', `${ready}; setInterval(() => {}, 1000)`, 143,
    { interrupt: 'SIGTERM' })
  await scenario('setup deadline kills an unresponsive child',
    'process.on("SIGTERM", () => {}); setInterval(() => {}, 1000)', 1, { setupMs: 200 })
  await scenario('split and unterminated output',
    'process.stdout.write("SHOTS_DO"); setTimeout(() => process.stdout.write("NE\\nSHOTS_HOLDING\\nSHOTS_HELD_DONE"), 20)', 0)
  const signals = new EventEmitter(), lines = []
  assert.equal(await runHeld('/nonexistent/omarchyform-review-qs', [], {
    signals, output: line => lines.push(line)
  }), 1)
  assert.ok(lines.some(line => line.includes('ENOENT')), 'spawn failure reason surfaced')
  assert.equal(signals.listenerCount('SIGINT'), 0)
  assert.equal(signals.listenerCount('SIGTERM'), 0)
  console.log('ok — held runner: spawn failure')
}

main().catch(error => { console.error(error); process.exitCode = 1 })
