// Supervise a held screenshot process without blocking signal handling or
// treating a successful process exit as proof that the fixture was ready.
const { spawn } = require('child_process')
const { createInterface } = require('readline')

function runHeld(command, args, {
  env = process.env, setupMs = 120000, killMs = 3000,
  output = line => console.log(line), signals = process
} = {}) {
  return new Promise(resolve => {
    const child = spawn(command, args, { env, stdio: ['ignore', 'pipe', 'pipe'] })
    let photographed = false, ready = false, completed = false
    let failed = false, interrupted = 0, killing = null
    const stop = () => {
      if (killing) return
      child.kill('SIGTERM')
      killing = setTimeout(() => child.kill('SIGKILL'), killMs)
    }
    const fail = reason => {
      if (!failed) output(`Held run failed: ${reason}`)
      failed = true
    }
    const setup = setTimeout(() => {
      fail('setup did not reach readiness before the deadline')
      stop()
    }, setupMs)
    const interrupt = (signal, code) => {
      if (interrupted) return
      interrupted = code
      output(`${signal} — closing the board`)
      stop()
    }
    const onInt = () => interrupt('SIGINT', 130)
    const onTerm = () => interrupt('SIGTERM', 143)
    signals.on('SIGINT', onInt)
    signals.on('SIGTERM', onTerm)
    child.on('spawn', () => output(`SHOTS_CHILD_PID ${child.pid}`))
    child.on('error', error => fail(error.message))

    const readers = [child.stdout, child.stderr].map(stream => {
      const reader = createInterface({ input: stream })
      reader.on('line', line => {
        output(line)
        if (/\bSHOTS_(?:TIMEOUT|HELD_FAILED)\b/.test(line)) {
          fail('the child reported a failure')
          stop()
        }
        if (/\bSHOTS_DONE\b/.test(line)) photographed = true
        if (/\bSHOTS_HOLDING\b/.test(line)) {
          if (!photographed) fail('held board became ready before screenshots finished')
          else { ready = true; clearTimeout(setup) }
        }
        if (/\bSHOTS_HELD_DONE\b/.test(line)) {
          if (!ready) fail('completion arrived before readiness')
          else completed = true
        }
      })
      return reader
    })
    // close, unlike exit, waits for the output pipes to drain. The final marker
    // may still be buffered when the process exits.
    child.on('close', (code, signal) => {
      clearTimeout(setup)
      if (killing) clearTimeout(killing)
      signals.off('SIGINT', onInt)
      signals.off('SIGTERM', onTerm)
      for (const reader of readers) reader.close()
      if (interrupted && !failed) { resolve(interrupted); return }
      if (signal) fail(`child terminated by ${signal}`)
      else if (code !== 0) fail(`child exited with code ${code}`)
      if (!ready || !completed) fail('missing readiness or completion marker')
      resolve(failed ? 1 : 0)
    })
  })
}

module.exports = { runHeld }
