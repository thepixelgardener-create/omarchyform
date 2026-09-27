// The picture at the top of the README, made the same way every time.
//
//   npm run preview              the theme you are using
//   npm run preview -- rose-pine  another one
//
// The shot harness photographs the `13-preview` scene along with every other
// state, at whatever size the compositor gave the window. That scene pulls the
// board up against the header, so the top of the window is the picture: this
// crops it to 16:9 and writes preview.png beside the README.
//
// It exists because the preview that shipped before was arranged by hand and
// never written down, and so went on advertising a hint row that had since
// moved to the other end of the window.
const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

const repo = path.join(__dirname, '..')
const target = { width: 1600, height: 900 }

function magick(args) {
  const run = spawnSync('magick', args, { encoding: 'utf8' })
  if (run.error && run.error.code === 'ENOENT') {
    console.error('This needs ImageMagick: the crop is the only thing it does.')
    process.exit(2)
  }
  if (run.status !== 0) {
    console.error((run.stderr || '').trim())
    process.exit(1)
  }
  return (run.stdout || '').trim()
}

const shots = spawnSync('node', [path.join(__dirname, 'shots.js'), ...process.argv.slice(2)],
  { encoding: 'utf8' })
process.stdout.write(shots.stdout || '')
if (shots.status !== 0) {
  process.stderr.write(shots.stderr || '')
  process.exit(shots.status === null ? 1 : shots.status)
}

// The harness says where it put them. One theme makes one preview; asking for
// several says which one it used rather than picking quietly.
const dirs = [...(shots.stdout || '').matchAll(/pictures in (.+)$/gm)].map(m => m[1])
if (dirs.length === 0) {
  console.error('The shot harness did not say where it put the pictures.')
  process.exit(1)
}
if (dirs.length > 1) console.log('More than one theme photographed — the preview is the first.')

const source = path.join(dirs[0], '13-preview.png')
if (!fs.existsSync(source)) {
  console.error('No preview scene in ' + dirs[0] + ' — is the 13-preview scene still in shot.qml?')
  process.exit(1)
}

// Crop the top of the window to the shape of the picture, then scale. Which
// side is cropped depends on the window the compositor handed out: a tall one
// loses its bottom, a wide one loses its edges.
const [width, height] = magick([source, '-format', '%w %h', 'info:']).split(' ').map(Number)
const ratio = target.width / target.height
let crop
if (width / height > ratio) {
  const w = Math.round(height * ratio)
  crop = `${w}x${height}+${Math.round((width - w) / 2)}+0`
} else {
  crop = `${width}x${Math.round(width / ratio)}+0+0`
}

const out = path.join(repo, 'preview.png')
magick([source, '-crop', crop, '+repage', '-resize', `${target.width}x${target.height}`,
  '-strip', out])
console.log(`preview.png — ${target.width}x${target.height}, cropped ${crop} from a ${width}x${height} window`)
