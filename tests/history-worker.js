// Run the production worker's entry point, with its Qt.include resolved to
// the production codec. Keep reply/token assertions shared across suites.
const assert = require('assert/strict')
const fs = require('fs')
const path = require('path')
const vm = require('vm')
const { loadStore } = require('../bin/store')

const read = name => fs.readFileSync(path.join(__dirname, '..', name), 'utf8')
const History = loadStore(read('BoardHistory.js'))

function historyWorker() {
  const replies = []
  const context = vm.createContext(Object.assign({
    WorkerScript: { sendMessage(message) { replies.push(message) } }
  }, History))
  vm.runInContext(read('BoardHistoryWorker.js').replace(/^Qt\.include\(.*\)$/m, ''), context)
  return {
    check: message => context.check(message),
    shorten: message => context.shorten(message),
    dispatch(message) {
      replies.length = 0
      context.WorkerScript.onMessage(message)
      assert.equal(replies.length, 1, 'every worker request receives one reply')
      assert.equal(replies[0].token, message.token, 'the reply retains its request token')
      return replies[0]
    }
  }
}

module.exports = { History, historyWorker }
