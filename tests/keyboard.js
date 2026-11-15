// Gluing, ungluing, following and lining up done from the keyboard alone:
// the board's own key handler, compiled from Board.qml, against the pane and
// document compiled from their QML sources (tests/workspace-harness.js). Each
// keystroke goes in the way Qt hands it over, key code, text and modifiers,
// so what is checked is what a key does, not what a function does when
// called. Nothing here touches the pointer.
const assert = require('assert/strict')
const fs = require('fs')
const path = require('path')
const vm = require('vm')
const { controller } = require('./workspace-harness')

// Qt's key codes and modifiers, the ones the handler reads. Anything else it
// asks for is a mistake in this file, not a key it can ignore.
const KEYS = { Key_Escape: 0x01000000, Key_Tab: 0x01000001, Key_Backtab: 0x01000002, Key_Backspace: 0x01000003,
  Key_Return: 0x01000004, Key_Enter: 0x01000005, Key_Delete: 0x01000007, Key_Left: 0x01000012, Key_Up: 0x01000013,
  Key_Right: 0x01000014, Key_Down: 0x01000015, Key_PageUp: 0x01000016, Key_PageDown: 0x01000017,
  Key_Control: 0x01000021, Key_F1: 0x01000030, Key_F2: 0x01000031, Key_F11: 0x0100003a, Key_Space: 0x20,
  ShiftModifier: 0x02000000, ControlModifier: 0x04000000, MetaModifier: 0x10000000 }
for (const letter of 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') KEYS['Key_' + letter] = letter.charCodeAt(0)
const Qt = new Proxy(KEYS, { get(target, name) {
  if (!(name in target)) throw new Error('the key handler reads Qt.' + String(name) + ', which this test does not define')
  return target[name]
} })

// The key handler, its direction table and its letter commands, as written.
const source = fs.readFileSync(path.join(__dirname, '..', 'Board.qml'), 'utf8')
const grab = (re, what) => { const m = source.match(re); assert.ok(m, 'Board.qml still has ' + what); return m[1] }
const direction = grab(/^    (function direction\(key, text\) \{[\s\S]*?^    \})$/m, 'its direction keys')
const commands = grab(/^    readonly property var commands: (\(\{[\s\S]*?^    \}\))$/m, 'its command table')
const pressed = grab(/^    Keys\.onPressed: (function \(event\) \{[\s\S]*?^    \})$/m, 'its key handler')

function keyboard(c) {
  const board = { ctl: c.root,
    paletteKey() { throw new Error('the palette is not part of this test') },
    findKey() { throw new Error('finding is not part of this test') } }
  const keys = { ctrlHeld: false }
  const context = vm.createContext({ board, keys, Qt, help: { scroll() {} } })
  keys.direction = vm.runInContext('(' + direction + ')', context)
  keys.commands = vm.runInContext(commands, context)
  const handler = vm.runInContext('(' + pressed + ')', context)
  // "ctrl+shift+h", "z", "G", "space", "Tab": what a person presses.
  return function press(spec) {
    const parts = spec.split('+'), name = parts.pop()
    const ctrl = parts.includes('ctrl'), shift = parts.includes('shift')
    let key, text
    if (name.length === 1) {
      key = Qt['Key_' + name.toUpperCase()]
      text = ctrl ? String.fromCharCode(name.toUpperCase().charCodeAt(0) - 64) : shift ? name.toUpperCase() : name
    } else if (name === 'space') { key = Qt.Key_Space; text = ' ' }
    else { key = Qt['Key_' + name]; text = '' }
    const event = { key, text, accepted: false,
      modifiers: (ctrl ? Qt.ControlModifier : 0) | (shift ? Qt.ShiftModifier : 0) }
    handler(event)
    return event.accepted
  }
}

const note = (id, x, y) => ({ id, kind: 'note', x, y, w: 220, h: 160, tint: 'foreground', text: 'note ' + id, pinned: false, src: '' })
function opened(items) {
  const c = controller()
  c.session.loadBoard(JSON.stringify({ kind: 'omarchyform.board', version: 8, nextId: 10, links: [], items }), false)
  c.press = keyboard(c)
  return c
}
const S = opened([]).store
const round = p => [Math.round(p.x * 100) / 100, Math.round(p.y * 100) / 100]
const end = (c, i, which) => round(S.lineEndPoint(c.items.get(i), which))
// Presses `spec` until `done`, at most `limit` times; answers how many it took.
function until(c, spec, done, limit) {
  for (let n = 1; n <= limit; n++) { c.press(spec); if (done()) return n }
  assert.fail(`${spec} pressed ${limit} times and it never happened`)
}
const presses = []

// Note one at (0, 0); note two down and to the right at (700, 360).
{
  const c = opened([note(1, 0, 0), note(2, 700, 360)])
  const one = () => c.items.get(0), two = () => c.items.get(1)

  // Tab to note one, z for an arrow beside it.
  c.press('Tab')
  assert.equal(c.root.selectedIndex, 0, 'tab: note one')
  c.press('z')
  assert.equal(c.items.count, 3, 'z: an arrow')
  assert.equal(c.items.get(2).kind, 'arrow')
  assert.equal(c.root.selectedIndex, 2, 'and it is the one in hand')
  if (c.root.editIndex >= 0) c.root.stopEditing()

  // ctrl+shift+h steps the tail back onto note one, where it is glued.
  const tailSteps = until(c, 'ctrl+shift+h', () => c.items.get(2).aon === 1, 10)
  presses.push(`tail onto the note beside it: ${tailSteps}× ctrl+shift+h`)
  assert.equal(end(c, 2, 0)[0], one().ix + one().iw, 'the tail sits on note one\'s right side')

  // ctrl+j then ctrl+l carry the head to note two, where it is glued.
  let headSteps = 0
  while (!c.items.get(2).bon && headSteps < 40) {
    const head = S.lineEndPoint(c.items.get(2), 1)
    c.press(head.y < two().iy + 40 ? 'ctrl+j' : 'ctrl+l')
    headSteps++
  }
  assert.equal(c.items.get(2).bon, 2, 'the head is glued to note two')
  presses.push(`head across to the other note: ${headSteps}× ctrl+j / ctrl+l`)
  const head = end(c, 2, 1)
  const onTwo = head[0] === two().ix || head[1] === two().iy
  assert.ok(onTwo, 'on the side of note two it reached, not inside it: ' + head)

  // Pushed further in, a glued end stays on the side it is on.
  const before = end(c, 2, 1)
  c.press('ctrl+l')
  assert.equal(c.items.get(2).bon, 2, 'stepped further into the note, it stays glued')
  const after = end(c, 2, 1)
  assert.ok(after[0] === two().ix || after[1] === two().iy, 'and on the side it was on: ' + before + ' → ' + after)

  // Tab to note two; shift+h and shift+k move it, and the head goes with it.
  until(c, 'Tab', () => c.root.selectedIndex === 1, 5)
  c.press('shift+h'); c.press('shift+k')
  assert.equal(c.items.get(2).bon, 2, 'note two moved; the head is still glued')
  const moved = end(c, 2, 1)
  assert.ok(moved[0] === two().ix || moved[1] === two().iy || moved[0] === two().ix + two().iw || moved[1] === two().iy + two().ih,
    'and on its outline where it went: ' + moved)
  assert.equal(c.items.get(2).aon, 1, 'the tail did not let go of note one')

  // Back to the arrow: stepping the head out of note two lets go of it, and
  // stepping back on glues it again.
  until(c, 'Tab', () => c.root.selectedIndex === 2, 5)
  const awayKey = end(c, 2, 1)[0] === two().ix ? 'ctrl+h' : 'ctrl+k'
  const backKey = awayKey === 'ctrl+h' ? 'ctrl+l' : 'ctrl+j'
  c.press(awayKey)
  assert.equal(c.items.get(2).bon, 0, `${awayKey}: stepped off note two, the head lets go`)
  assert.equal(c.items.get(2).aon, 1, 'the tail stays')
  c.press(backKey)
  assert.equal(c.items.get(2).bon, 2, `${backKey}: back on, glued again`)

  // shift+j carries the whole arrow away: it lets go of both. u brings it
  // back, glued.
  c.press('shift+j')
  assert.deepEqual([c.items.get(2).aon, c.items.get(2).bon], [0, 0], 'the arrow moved on its own lets go of both')
  c.press('u')
  assert.deepEqual([c.items.get(2).aon, c.items.get(2).bon], [1, 2], 'u: glued to both again')

  // Lining up from the keyboard: mark note one and note two with space, g
  // then k puts their tops level, and the arrow follows both.
  c.press('Escape')
  until(c, 'Tab', () => c.root.selectedIndex === 0, 5)
  c.press('space')
  until(c, 'Tab', () => c.root.selectedIndex === 1, 5)
  c.press('space')
  c.press('g')
  assert.equal(c.root.arranging, true, 'g: waiting for which way')
  c.press('k')
  assert.equal(one().iy, two().iy, 'g k: tops level')
  assert.deepEqual([c.items.get(2).aon, c.items.get(2).bon], [1, 2], 'the arrow is still glued to both')
  assert.equal(end(c, 2, 0)[0], one().ix + one().iw, 'its tail on note one')
  c.press('g'); c.press('h')
  assert.equal(one().ix, two().ix, 'g h: left sides in line')
  c.press('g'); c.press('c')
  assert.equal(one().ix + one().iw / 2, two().ix + two().iw / 2, 'g c: middles in line, across')
  assert.deepEqual([c.items.get(2).aon, c.items.get(2).bon], [1, 2], 'and still glued after every one')
  c.press('g'); c.press('x')
  assert.equal(c.root.arranging, false, 'g then a key it does not know does nothing and leaves')
}

// The arrow marked along with the notes it joins, lined up as one, keeps both
// ends; three notes spread evenly with g then shift+l.
{
  const c = opened([note(1, 0, 0), note(2, 500, 40), note(3, 1300, 70)])
  c.press('Tab'); c.press('z')
  if (c.root.editIndex >= 0) c.root.stopEditing()
  until(c, 'ctrl+shift+h', () => c.items.get(3).aon === 1, 10)
  until(c, 'ctrl+l', () => c.items.get(3).bon === 2, 20)
  c.press('a')
  c.press('g'); c.press('j')
  assert.deepEqual([c.items.get(3).aon, c.items.get(3).bon], [1, 2], 'aligned with everything marked, the arrow keeps both ends')
  c.press('g'); c.press('shift+l')
  const at = [0, 1, 2].map(i => c.items.get(i)).sort((a, b) => a.ix - b.ix)
  const gaps = [at[1].ix - (at[0].ix + at[0].iw), at[2].ix - (at[1].ix + at[1].iw)]
  assert.ok(Math.abs(gaps[0] - gaps[1]) < 1e-9, 'g shift+l: evenly spaced, ' + gaps)
  assert.deepEqual([c.items.get(3).aon, c.items.get(3).bon], [1, 2], 'and the arrow is still glued')
}

console.log('ok — keyboard: an arrow is glued, followed, let go of and lined up without the pointer (' + presses.join('; ') + ')')
