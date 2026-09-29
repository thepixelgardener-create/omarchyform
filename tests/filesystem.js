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
  assert.equal(fs.existsSync(path.join(boards,'a.json')),true)
  assert.equal(run('check',boards,'escape/a.json').status,3)
  assert.equal(run('check',boards,'a.json').status,0)
  assert.equal(run('check',boards,'not-yet/new.json').status,0)
  const snapshot = run('snapshot', path.join(boards, 'a.json'), path.join(dir, 'snapshot.lock'), boards)
  assert.equal(snapshot.status, 0)
  const split = snapshot.stdout.indexOf('\n')
  assert.equal(snapshot.stdout.slice(0, split), run('revision', path.join(boards, 'a.json')).stdout)
  assert.equal(snapshot.stdout.slice(split + 1), 'new', 'snapshot carries exact bytes with their revision')
  assert.notEqual(run('snapshot', path.join(boards, 'escape/a.json'), path.join(dir, 'snapshot.lock'), boards).status, 0)
  // A symlinked root is where the user keeps their data, not an escape.
  const linkedBoards=path.join(dir,'linked-boards'),linkedBackups=path.join(dir,'linked-backups')
  fs.mkdirSync(path.join(dir,'backups'))
  fs.symlinkSync(boards,linkedBoards)
  fs.symlinkSync(path.join(dir,'backups'),linkedBackups)
  assert.equal(spawnSync('bash',[path.join(__dirname,'../BoardFiles.sh'),'commit',
    path.join(linkedBoards,'a.json'),path.join(linkedBackups,'a.json.bak'),
    path.join(dir,'locks','linked.lock'),'-',linkedBoards,linkedBackups],
    {encoding:'utf8',input:'through a linked root'}).status,0)
  assert.equal(fs.readFileSync(path.join(dir,'backups/a.json.bak'),'utf8'),'new','the version it replaced')
  assert.equal(fs.readFileSync(path.join(boards,'a.json'),'utf8'),'through a linked root')
  fs.writeFileSync(path.join(boards,'a.json'),'new')
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
    '#!/usr/bin/env bash\nfor a in "$@"; do [[ $a == --list-types ]] && { printf \'%s\\n\' "$FAKE_TYPES"; exit 0; }; done\nif [[ -n ${FAKE_FILE:-} ]]; then cat "$FAKE_FILE"; else printf \'%s\' "$FAKE_BYTES"; fi\n')
  fs.chmodSync(path.join(stubs,'wl-paste'),0o755)
  const paste=(types,bytes,root,name,file)=>spawnSync('bash',
    [path.join(__dirname,'../BoardFiles.sh'),'clipimage',root,name],
    {encoding:'utf8',env:{...process.env,PATH:stubs+':'+process.env.PATH,FAKE_TYPES:types,FAKE_BYTES:bytes,
      FAKE_FILE:file===undefined?'':file}})

  assert.equal(paste('text/plain','hello',images,'paste-1').status,4,'no picture on the clipboard is not a failure')
  assert.deepEqual(fs.readdirSync(images),[],'and nothing is left behind')

  const png=paste('text/plain\nimage/png','PNGBYTES',images,'paste-1')
  assert.equal(png.status,0)
  assert.equal(png.stdout,'paste-1.png','the caller is told the name it got')
  assert.equal(fs.readFileSync(path.join(images,'paste-1.png'),'utf8'),'PNGBYTES')

  assert.equal(paste('image/jpeg','JPGBYTES',images,'paste-2').stdout,'paste-2.jpg','the format picks the extension')

  // The same rule for a paste: a name already on disk is not written over.
  assert.equal(paste('image/png','OTHERBYTES',images,'paste-1').status,6)
  assert.equal(fs.readFileSync(path.join(images,'paste-1.png'),'utf8'),'PNGBYTES','the first one still stands')

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

  const firstDrop=drop('drop-1','shot.png')
  assert.equal(firstDrop.status,0)
  assert.equal(firstDrop.stdout,'drop-1.png','the caller is told the name it got')
  assert.deepEqual(fs.readFileSync(path.join(images,'drop-1.png')),pngBytes,'the bytes arrive unchanged')

  // A name already taken is never written over, and says so with a code of its
  // own rather than depending on how this coreutils version reports it.
  fs.writeFileSync(path.join(source,'other.png'),Buffer.concat([pngBytes,Buffer.from([0])]))
  assert.equal(drop('drop-1','other.png').status,6,'the name is taken')
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

  // A picture is a picture however it arrived, so the clipboard is held to the
  // same limit. Checked here because the oversize fixture is written once.
  assert.equal(paste('image/png','',images,'paste-4',path.join(source,'huge.png')).status,5)
  assert.equal(fs.existsSync(path.join(images,'paste-4.png')),false)

  assert.equal(run('importimage',images,'drop-6',path.join(source,'absent.png')).status,4,'a path that is not there')
  assert.equal(run('importimage',images,'drop-7',source).status,4,'a directory is not a file')
  for (const bad of ['../escape','a/b','.hidden','-dash'])
    assert.notEqual(drop(bad,'shot.png').status,0,bad)

  // The coordinated write: under a lock, and only onto the revision the writer
  // last saw. Two writers that both read the same version is the whole point —
  // the second one has to be told rather than win by arriving later.
  const board=path.join(boards,'coordinated.json')
  const lock=path.join(dir,'locks','coordinated.lock')
  const backup=path.join(dir,'backups','coordinated.json.bak')
  // The board itself goes in on stdin: one process does the whole write, so
  // there is no half-written file of ours to leave behind.
  const commit=(text,expected)=>spawnSync('bash',
    [path.join(__dirname,'../BoardFiles.sh'),'commit',board,backup,lock,expected,boards,path.join(dir,'backups')],
    {encoding:'utf8',input:text})

  const wrote1=commit('one','')
  assert.equal(wrote1.status,0,'nothing there yet is the empty revision')
  assert.equal(fs.readFileSync(board,'utf8'),'one')
  assert.ok(wrote1.stdout.length>0,'and it answers with the revision it wrote')
  assert.equal(fs.existsSync(backup),false,'with nothing to keep the first time')

  const wrote2=commit('two',wrote1.stdout)
  assert.equal(wrote2.status,0)
  assert.equal(fs.readFileSync(board,'utf8'),'two')
  assert.equal(fs.readFileSync(backup,'utf8'),'one','the version it replaced is kept')
  assert.notEqual(wrote2.stdout,wrote1.stdout,'and the revision moves')

  // The stale write: the second writer read revision one and is still holding
  // it while someone else has moved the file on.
  const stale=commit('three',wrote1.stdout)
  assert.equal(stale.status,7,'a distinct code, so the caller can ask a person')
  assert.equal(fs.readFileSync(board,'utf8'),'two','and nothing was written')
  assert.equal(stale.stdout,wrote2.stdout,'it says what is there now')
  assert.deepEqual(fs.readdirSync(boards).filter(f=>f.startsWith('.omarchyform-')),[],
    'the refused content is not left lying in the boards folder')

  // `-` is the explicit overwrite: someone was asked and chose this version.
  const forced=commit('four','-')
  assert.equal(forced.status,0)
  assert.equal(fs.readFileSync(board,'utf8'),'four')
  assert.equal(fs.readFileSync(backup,'utf8'),'two','which still keeps what it replaced')

  // The same revision the commit answered with is what `check` reports, so a
  // board opened and a board written agree about what version they are on.
  const seen=run('check',boards,'coordinated.json')
  assert.equal(seen.status,0)
  assert.equal(seen.stdout,forced.stdout,'check and commit speak the same revision')
  assert.equal(run('revision',board).stdout,forced.stdout)
  assert.equal(run('revision',path.join(boards,'not-here.json')).stdout,'','and nothing has no revision')
  // Asked before a file is read into memory, so an absurd one can be refused
  // without being loaded.
  assert.equal(Number(run('filesize',board).stdout),fs.statSync(board).size)
  assert.equal(run('filesize',path.join(boards,'not-here.json')).stdout,'0')

  // And the same thing for real: two writers that both read the same revision,
  // started together. The lock decides which goes first; the revision check
  // decides that the other one is stale. Without the lock both could see the
  // revision they expected before either had written.
  const script=path.join(__dirname,'../BoardFiles.sh')
  const backupsDir=path.join(dir,'backups')
  const racer=(text,out)=>
    `printf %s ${JSON.stringify(text)} | bash ${JSON.stringify(script)} commit ${JSON.stringify(board)} `
    + `${JSON.stringify(backup)} ${JSON.stringify(lock)} ${JSON.stringify(run('revision',board).stdout)} `
    + `${JSON.stringify(boards)} ${JSON.stringify(backupsDir)} >${JSON.stringify(out)} 2>&1; `
    + `echo $? >${JSON.stringify(out + '.code')}`
  const outA=path.join(dir,'race-a'),outB=path.join(dir,'race-b')
  spawnSync('bash',['-c',`{ ${racer('racer A',outA)} ; } & { ${racer('racer B',outB)} ; } & wait`])
  const codes=[outA,outB].map(f=>Number(fs.readFileSync(f+'.code','utf8').trim()))
  assert.deepEqual(codes.slice().sort((x,y)=>x-y),[0,7],'exactly one of the two got through')
  const winner=codes[0]===0?'racer A':'racer B'
  assert.equal(fs.readFileSync(board,'utf8'),winner,'and the file holds that one, whole')
  assert.equal(fs.readFileSync(backup,'utf8'),'four','with the version it replaced kept')

  // The rules the old backup step had, kept: a path through a symlink is
  // refused before anything is written.
  const behindLink=spawnSync('bash',[path.join(__dirname,'../BoardFiles.sh'),'commit',
    path.join(boards,'escape/a.json'),backup,lock,'-',boards,path.join(dir,'backups')],{encoding:'utf8',input:'x'})
  assert.equal(behindLink.status,3)

  // A copy saved to share carries its pictures inside it, so the bytes come out
  // of the images folder here and go back into someone else's below.
  const bundle=(budget,...names)=>run('bundleimages',images,String(budget),...names)
  const carried=bundle(33554432,'drop-1.png','absent.png','copy-me.png')
  assert.equal(carried.status,0)
  const carriedLines=carried.stdout.replace(/\n$/,'').split('\n').map(l=>l.split('\t'))
  assert.deepEqual(carriedLines.map(l=>l[0]),['drop-1.png','absent.png','copy-me.png'],
    'one line each, in the order they were asked for')
  assert.equal(carriedLines[1][1],'!missing','a picture the board names and the folder does not have')
  assert.deepEqual(Buffer.from(carriedLines[0][1],'base64'),pngBytes,'and the bytes come back unchanged')
  for (const bad of ['../escape.png','sub/dir.png','.hidden.png'])
    assert.equal(bundle(33554432,bad).stdout.split('\t')[1].trim(),'!missing','no name a board would write: '+bad)

  // The whole set or none of it: half a board's pictures is not something the
  // person saving the copy could do anything about.
  const overBudget=bundle(4,'drop-1.png','copy-me.png')
  assert.equal(overBudget.status,0)
  assert.match(overBudget.stdout,/^!toolarge\t\d+\n$/,'and it says how much there was')
  assert.equal(overBudget.stdout.split('\t')[1].trim() > 4,true)

  // Back in. The name is the caller's, the extension comes from the decoded
  // bytes, and a picture that arrived inside a board is held to the same limit
  // as one dropped onto it.
  const staging=path.join(dir,'staged.b64')
  const unbundle=(name,body)=>{fs.writeFileSync(staging,body); return run('unbundleimage',images,staging,name)}
  const landed=unbundle('shared-1',pngBytes.toString('base64'))
  assert.equal(landed.status,0)
  assert.equal(landed.stdout,'shared-1.png','the caller is told the name it got')
  assert.deepEqual(fs.readFileSync(path.join(images,'shared-1.png')),pngBytes)
  assert.equal(fs.existsSync(staging),false,'and the staged bytes do not linger')

  assert.equal(unbundle('shared-1',pngBytes.toString('base64')).status,6,'a name already taken')
  assert.equal(unbundle('shared-2',Buffer.from('this is not a picture').toString('base64')).status,4,
    'bytes that decode to something that is not a picture')
  assert.equal(unbundle('shared-3','!! not base64 !!').status,4,'and bytes that do not decode at all')
  assert.equal(unbundle('shared-4',
    Buffer.concat([pngBytes,Buffer.alloc(33554433-pngBytes.length)]).toString('base64')).status,5,
    'too large for a board, whichever way it arrived')
  for (const bad of ['../escape','a/b','.hidden','-dash'])
    assert.notEqual(unbundle(bad,pngBytes.toString('base64')).status,0,bad)
  assert.deepEqual(fs.readdirSync(images).filter(f=>f.startsWith('shared-')),['shared-1.png'],
    'nothing else landed')

  // What a picture costs to draw is its pixels, and the byte limit above never
  // sees them: a PNG of one flat colour is a hundred kilobytes and half a
  // gigabyte decoded, which is under every other limit here and small enough to
  // travel inside a board somebody sends you.
  //
  // Built by patching the header of the real picture above rather than by
  // carrying a big one: the dimensions are read out of IHDR, so a header that
  // says twelve thousand square is the whole of what is under test. The CRC is
  // wrong afterwards and nothing here cares — `file` reads the signature and the
  // fields, and the picture is refused before anything would decode it.
  const claiming=(w,h)=>{
    const bomb=Buffer.from(pngBytes)
    bomb.writeUInt32BE(w,16)
    bomb.writeUInt32BE(h,20)
    return bomb
  }
  assert.equal(spawnSync('file',['-bL','--mime-type',path.join(source,'shot.png')],
    {encoding:'utf8'}).stdout.trim(),'image/png','the fixture is sniffed as a PNG')

  fs.writeFileSync(path.join(source,'bomb.png'),claiming(12000,12000))
  assert.equal(drop('drop-bomb','bomb.png').status,7,'a picture that decodes to half a gigabyte')
  assert.equal(fs.existsSync(path.join(images,'drop-bomb.png')),false,'and nothing lands')

  // The area alone would let a strip through, and a side alone would let a
  // square through, so both are held.
  fs.writeFileSync(path.join(source,'strip.png'),claiming(1,100000000))
  assert.equal(drop('drop-strip','strip.png').status,7,'one pixel by a hundred million')
  fs.writeFileSync(path.join(source,'wide.png'),claiming(30000,4))
  assert.equal(drop('drop-wide','wide.png').status,7,'thirty thousand by four')
  fs.writeFileSync(path.join(source,'zero.png'),claiming(0,0))
  assert.equal(drop('drop-zero','zero.png').status,7,'and a header claiming nothing at all')

  // It arrives inside a shared board by the same route, which is the one nobody
  // chose to open.
  assert.notEqual(unbundle('shared-bomb',claiming(12000,12000).toString('base64')).status,0,
    'nor from inside a board somebody sent')
  assert.equal(fs.existsSync(path.join(images,'shared-bomb.png')),false)

  // And what is merely large still goes on a board: this is a limit, not a
  // suspicion of big pictures.
  fs.writeFileSync(path.join(source,'big.png'),claiming(4000,4000))
  assert.equal(drop('drop-big','big.png').status,0,'sixteen megapixels is a picture, not a bomb')
  assert.equal(fs.existsSync(path.join(images,'drop-big.png')),true)

  assert.deepEqual(fs.readdirSync(images).filter(f=>f.startsWith('.')),[],'no temporaries left behind')

} finally {fs.rmSync(dir,{recursive:true,force:true})}
console.log('ok — filesystem confinement and restore collisions')
