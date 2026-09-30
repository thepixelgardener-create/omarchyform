// Rebuild the editable showcase through the same CLI used for real boards.
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const cli = path.join(__dirname, '../bin/omarchyform')
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'omarchyform-showcase-'))
const board = path.join(scratch, 'From spark to shipped.omarchyform.json')
function run(args, input) {
  const result = spawnSync(process.execPath, [cli, ...args], {
    input: input === undefined ? undefined : JSON.stringify(input), encoding: 'utf8',
    env: { ...process.env, HOME: scratch }
  })
  if (result.status !== 0) throw new Error(result.stderr || result.stdout)
  return JSON.parse(result.stdout)
}
try {
  run(['new', board])
  const cards = [
    ['note', 0, 0, 1020, 90, '# From spark to shipped\nA little space to think. A clear next step. Everything stays on your desktop.', 'accent'],
    ['note', 0, 130, 300, 145, '# 01 / Capture\nStart with one good question.\n\nPress `n`. Write it down.\nKeep the thought *small*.'],
    ['note', 360, 130, 300, 145, '# 02 / Arrange\nGive related ideas a place.\n\nMove with `shift + hjkl`.\nConnect the dots with `x`.'],
    ['note', 720, 130, 300, 145, '# 03 / Ship\nMake the next step obvious.\n\nExport a picture with `ctrl+e`.\nShare the board with `ctrl+shift+s`.'],
    ['ellipse', 50, 325, 200, 100, 'A small\nidea'],
    ['diamond', 405, 315, 210, 120, 'Worth\nbuilding?'],
    ['rect', 770, 325, 200, 100, '*Make it real*\nOne useful thing.', 'accent'],
    ['note', 0, 475, 300, 145, '# Say it your way\n*Bold* for the point.\n_Italic_ for a quiet aside.\n[accent]A little colour[/] for emphasis.\n\nWhile typing, try `ctrl+p`.'],
    ['note', 360, 475, 300, 145, '# Feels like home\nYour font. Your theme.\nSharp edges. Room to breathe.\n\nPlain JSON, saved locally.'],
    ['note', 720, 475, 300, 145, '# Keep the scope small\n[urgent]One risk:[/] too much at once.\n\nChoose one thing to finish.\nLeave the rest for tomorrow.', 'urgent'],
    ['rect', 0, 665, 1020, 60, '`b` boards     /     `f` fit everything     /     `?` all the keys', 'muted']
  ]
  const added = run(['apply', board, '-'], cards.map(args => ({ op: 'add', args })))
  const ids = added.applied.map(row => row.added)
  if (ids.some(id => !Number.isInteger(id))) throw new Error('Missing item IDs from CLI')
  run(['apply', board, '-'], [
    { op: 'link', args: [ids[4], ids[5]] },
    { op: 'link', args: [ids[5], ids[6]] }
  ])
  const validation = run(['validate', board])
  const target = path.join(__dirname, path.basename(board))
  fs.copyFileSync(board, target)
  console.log(JSON.stringify({file: target, validation}, null, 2))
} finally {
  fs.rmSync(scratch, {recursive: true, force: true})
}
