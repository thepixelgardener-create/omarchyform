const assert = require('assert/strict')
const fs = require('fs'), os = require('os'), path = require('path')
const {spawnSync} = require('child_process')
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'omarchyform-files-'))
try {
  const boards=path.join(dir,'boards'),trash=path.join(dir,'trash'),outside=path.join(dir,'outside')
  for (const d of [boards,trash,outside]) fs.mkdirSync(d)
  const run=(...args)=>spawnSync('bash',[path.join(__dirname,'../BoardFiles.sh'),...args],{encoding:'utf8'})
  fs.writeFileSync(path.join(trash,'old'),'old')
  fs.writeFileSync(path.join(boards,'a.json'),'new')
  assert.notEqual(run('move',trash,'old',boards,'a.json').status,0)
  assert.equal(fs.readFileSync(path.join(trash,'old'),'utf8'),'old')
  fs.mkdirSync(path.join(boards,'folder'))
  fs.mkdirSync(path.join(trash,'folder'))
  assert.notEqual(run('move',trash,'folder',boards,'folder').status,0)
  assert.equal(fs.existsSync(path.join(boards,'folder/folder')),false)
  assert.equal(run('move',trash,'old',boards,'nested/restored.json').status,0)
  assert.equal(fs.readFileSync(path.join(boards,'nested/restored.json'),'utf8'),'old')
  fs.symlinkSync(outside,path.join(boards,'escape'))
  fs.writeFileSync(path.join(trash,'another'),'keep')
  assert.notEqual(run('move',trash,'another',boards,'bad\nname.json').status,0)
  assert.notEqual(run('move',trash,'another',boards,'escape/board.json').status,0)
  assert.notEqual(run('purge',trash,'../boards').status,0)
  fs.symlinkSync(boards,path.join(trash,'link'))
  assert.notEqual(run('purge',trash,'link').status,0)
  assert.equal(run('backup',path.join(boards,'escape/a.json'),path.join(trash,'backup'),boards).status,3)
  assert.equal(fs.existsSync(path.join(boards,'a.json')),true)
  assert.equal(run('check',boards,'escape/a.json').status,3)
  assert.equal(run('check',boards,'a.json').status,0)
  assert.equal(run('check',boards,'not-yet/new.json').status,0)
  // A symlinked root is where the user keeps their data, not an escape.
  const linkedBoards=path.join(dir,'linked-boards'),linkedBackups=path.join(dir,'linked-backups')
  fs.mkdirSync(path.join(dir,'backups'))
  fs.symlinkSync(boards,linkedBoards)
  fs.symlinkSync(path.join(dir,'backups'),linkedBackups)
  assert.equal(run('backup',path.join(linkedBoards,'a.json'),path.join(linkedBackups,'a.json.bak'),linkedBoards,linkedBackups).status,0)
  assert.equal(fs.readFileSync(path.join(dir,'backups/a.json.bak'),'utf8'),'new')
  assert.equal(run('purge',trash,'another').status,0)
  const staged=path.join(dir,'staged.json')
  fs.writeFileSync(staged,'{"version":4,"items":[]}')
  const first=run('publish',boards,'untitled',staged)
  assert.equal(first.status,0)
  assert.equal(first.stdout,'untitled.json')
  fs.writeFileSync(staged,'second')
  const second=run('publish',boards,'untitled',staged)
  assert.equal(second.status,0)
  assert.equal(second.stdout,'untitled-2.json')
  assert.equal(JSON.parse(fs.readFileSync(path.join(boards,'untitled.json'))).version,4)
  fs.writeFileSync(staged,'export')
  assert.notEqual(run('export',staged,path.join(boards,'a.json'),boards).status,0)
  assert.equal(fs.readFileSync(path.join(boards,'a.json'),'utf8'),'new')
  assert.equal(run('export',staged,path.join(outside,'copy.json'),boards).status,0)
  assert.equal(fs.readFileSync(path.join(outside,'copy.json'),'utf8'),'export')

  // Pasting an image: the clipboard chooses the format, the script chooses the
  // name and the folder. A stub wl-paste stands in for the compositor.
  const images=path.join(dir,'images'),stubs=path.join(dir,'stubs')
  for (const d of [images,stubs]) fs.mkdirSync(d)
  fs.writeFileSync(path.join(stubs,'wl-paste'),
    '#!/usr/bin/env bash\nfor a in "$@"; do [[ $a == --list-types ]] && { printf \'%s\\n\' "$FAKE_TYPES"; exit 0; }; done\nprintf \'%s\' "$FAKE_BYTES"\n')
  fs.chmodSync(path.join(stubs,'wl-paste'),0o755)
  const paste=(types,bytes,root,name)=>spawnSync('bash',
    [path.join(__dirname,'../BoardFiles.sh'),'clipimage',root,name],
    {encoding:'utf8',env:{...process.env,PATH:stubs+':'+process.env.PATH,FAKE_TYPES:types,FAKE_BYTES:bytes}})

  assert.equal(paste('text/plain','hello',images,'paste-1').status,4,'no picture on the clipboard is not a failure')
  assert.deepEqual(fs.readdirSync(images),[],'and nothing is left behind')

  const png=paste('text/plain\nimage/png','PNGBYTES',images,'paste-1')
  assert.equal(png.status,0)
  assert.equal(png.stdout,'paste-1.png','the caller is told the name it got')
  assert.equal(fs.readFileSync(path.join(images,'paste-1.png'),'utf8'),'PNGBYTES')

  assert.equal(paste('image/jpeg','JPGBYTES',images,'paste-2').stdout,'paste-2.jpg','the format picks the extension')

  // An empty clipboard read must not leave a zero-byte image on the board.
  assert.equal(paste('image/png','',images,'paste-3').status,4)
  assert.equal(fs.existsSync(path.join(images,'paste-3.png')),false)

  for (const bad of ['../escape','a/b','.hidden','-dash'])
    assert.notEqual(paste('image/png','X',images,bad).status,0,bad)
  assert.deepEqual(fs.readdirSync(images).sort(),['paste-1.png','paste-2.jpg'],'no strays, no temporaries')

  // Copying out: a stub wl-copy records what it was handed, so the real
  // clipboard is never touched by a test run.
  fs.writeFileSync(path.join(stubs,'wl-copy'),
    '#!/usr/bin/env bash\nprintf \'%s\\n\' "$*" > "$COPY_LOG"\ncat >> "$COPY_LOG"\n')
  fs.chmodSync(path.join(stubs,'wl-copy'),0o755)
  const copyLog=path.join(dir,'copied.txt')
  const copy=(...args)=>spawnSync('bash',[path.join(__dirname,'../BoardFiles.sh'),...args],
    {encoding:'utf8',env:{...process.env,PATH:stubs+':'+process.env.PATH,COPY_LOG:copyLog}})

  assert.equal(copy('clipcopy','two\nlines').status,0)
  assert.match(fs.readFileSync(copyLog,'utf8'),/two\nlines/,'the text reaches the clipboard intact')
  // A note beginning with a dash is text, not an option.
  assert.equal(copy('clipcopy','--help').status,0)
  assert.match(fs.readFileSync(copyLog,'utf8'),/--help/)

  const pixels=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==','base64')
  fs.writeFileSync(path.join(images,'copy-me.png'),pixels)
  fs.writeFileSync(path.join(images,'not-a-picture.png'),'plain text')
  assert.equal(copy('clipcopyimage',images,'copy-me.png').status,0)
  assert.match(fs.readFileSync(copyLog,'utf8'),/--type image\/png/,'the type is read from the bytes')
  assert.equal(copy('clipcopyimage',images,'not-a-picture.png').status,4,'a file that is not a picture is refused')
  for (const bad of ['../escape.png','sub/dir.png'])
    assert.notEqual(copy('clipcopyimage',images,bad).status,0,bad)

  // Dropping a file in: the path is untrusted, the type comes from the content,
  // and the destination name is ours.
  const source=path.join(dir,'source')
  fs.mkdirSync(source)
  // A real two-pixel PNG, so `file` recognises it the way it will in earnest.
  const pngBytes=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==','base64')
  fs.writeFileSync(path.join(source,'shot.png'),pngBytes)
  fs.writeFileSync(path.join(source,'notes.txt'),'this is not a picture')
  fs.writeFileSync(path.join(source,'lying.png'),'still not a picture')
  const drop=(name,file)=>run('importimage',images,name,path.join(source,file))

  assert.equal(drop('drop-1','shot.png').status,0)
  assert.equal(drop('drop-1','shot.png').stdout,'drop-1.png','the caller is told the name it got')
  assert.deepEqual(fs.readFileSync(path.join(images,'drop-1.png')),pngBytes,'the bytes arrive unchanged')

  // A name already taken is never written over: callers generate unique names,
  // and silently replacing one board's picture from another would be worse.
  fs.writeFileSync(path.join(source,'other.png'),Buffer.concat([pngBytes,Buffer.from([0])]))
  drop('drop-1','other.png')
  assert.deepEqual(fs.readFileSync(path.join(images,'drop-1.png')),pngBytes,'the first one still stands')

  assert.equal(drop('drop-2','notes.txt').status,4,'a text file is not an image')
  assert.equal(drop('drop-3','lying.png').status,4,'and neither is one that says it is')
  assert.equal(fs.existsSync(path.join(images,'drop-3.png')),false)

  // The extension follows the content, not the name it arrived under.
  fs.copyFileSync(path.join(source,'shot.png'),path.join(source,'mislabelled.jpg'))
  assert.equal(drop('drop-4','mislabelled.jpg').stdout,'drop-4.png','content decides the extension')

  // Too large to sit on a board is refused before anything is copied.
  fs.writeFileSync(path.join(source,'huge.png'),Buffer.concat([pngBytes,Buffer.alloc(33554433-pngBytes.length)]))
  assert.equal(drop('drop-5','huge.png').status,5,'a distinct code, so the message can differ')
  assert.equal(fs.existsSync(path.join(images,'drop-5.png')),false)

  assert.equal(run('importimage',images,'drop-6',path.join(source,'absent.png')).status,4,'a path that is not there')
  assert.equal(run('importimage',images,'drop-7',source).status,4,'a directory is not a file')
  for (const bad of ['../escape','a/b','.hidden','-dash'])
    assert.notEqual(drop(bad,'shot.png').status,0,bad)

  assert.deepEqual(fs.readdirSync(images).filter(f=>f.startsWith('.')),[],'no temporaries left behind')

} finally {fs.rmSync(dir,{recursive:true,force:true})}
console.log('ok — filesystem confinement and restore collisions')
