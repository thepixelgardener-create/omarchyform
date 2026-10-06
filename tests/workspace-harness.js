// The workspace, its panes and their documents, run from their QML sources
// with delayed I/O completions. The controller every view reads is a pane,
// BoardPane.qml; what is on a board is its document, BoardDocument.qml, with
// a BoardSession each; settings, files and the layout are the workspace's,
// Omarchyform.qml. Each object's functions are compiled where its own id names
// it, and the members one forwards from another are getters here, as they are
// bindings there.
const fs = require('fs')
const vm = require('vm')
const path = require('path')
const { loadStore, FakeModel } = require('./harness')

const read = name => fs.readFileSync(path.join(__dirname, '..', name), 'utf8')
const sources = {
  pane: read('BoardPane.qml'), workspace: read('Omarchyform.qml'), document: read('BoardDocument.qml'),
  session: read('BoardSession.qml'), library: read('BoardLibrary.qml')
}

function loadFunctions(target, qml, context) {
  for (const match of qml.matchAll(/^  function (\w+)\((.*?)\) \{\n([\s\S]*?)^  }/gm))
    target[match[1]] = vm.runInContext(`(function(${match[2]}) {${match[3]}})`, context)
  for (const match of qml.matchAll(/^  function (\w+)\((.*?)\) \{ (.*?) }$/gm))
    target[match[1]] = vm.runInContext(`(function(${match[2]}) {${match[3]}})`, context)
}

const forward = (target, from, keys) => {
  for (const key of keys) Object.defineProperty(target, key, { get: () => from()[key] })
}

// One open board: its models, its session and the writer under it. A write is
// held until the test completes or refuses it, the way a slow disk would.
function makeDocument(workspace, board, Store) {
  const items = new FakeModel(), links = new FakeModel()
  const doc = { workspace, items, links, nextId: 1, nextColor: 0, undoStack: [], redoStack: [],
    currentBoard: board, destroyed: false, editedBy: [],
    // The history the QML declares, at the values it starts with.
    historyHeader: '', historyRecords: '', historyCount: 0, historyBytes: 0, historyLast: 0, historyStart: 0,
    historyAsLoaded: '', historyChecking: false, historyWaiting: [], historyTrimming: false, historyTrimmed: false,
    historyToken: 0, head: null, loadedState: null, editLabel: '', editKey: '', changed: false, changedSince: 0,
    // Connections in the QML: every pane on this board but the one that
    // edited follows the edit.
    edited(by) {
      doc.editedBy.push(by)
      for (const pane of workspace.panes) if (pane.doc === doc && pane !== by) pane.followEdit()
    },
    destroy() { doc.destroyed = true } }
  const session = { ctl: doc, boardLoaded: true, damaged: false, pendingBoard: null,
    lastSavedCount: 0, lastSavedText: '', saveError: '', damageReason: '',
    // The conflict state the QML declares, mirrored here: an undeclared
    // property reads as undefined, which is not what a string property does.
    conflict: false, resolving: '', createWhenLoaded: false,
    revision: '', forceNextSave: false, diskReading: false }
  // The binding BoardSession.qml declares, term for term.
  Object.defineProperty(session, 'canEdit', {
    get: () => session.boardLoaded && !session.damaged && session.pendingBoard === null && !session.diskReading
  })
  const writes = []
  const persistence = { busy: false, contents: '',
    save(path, text, backup, root, backupRoot, lock, expected) {
      this.busy = true
      this.contents = text
      writes.push({ path, text, expected })
    } }
  // The session's binding of the same name.
  Object.defineProperty(session, 'busy', { get: () => persistence.busy || session.diskReading })
  // What the document reads off its session, and off the workspace for it.
  forward(doc, () => session, ['boardLoaded', 'damaged', 'damageReason', 'saveError', 'pendingBoard', 'canEdit'])
  Object.defineProperty(doc, 'diskChanged', { get: () => session.conflict })
  Object.defineProperty(doc, 'saving', { get: () => session.busy })
  Object.defineProperty(doc, 'boardPath', { get: () => '/boards/' + doc.currentBoard })
  Object.defineProperty(doc, 'boardTitle', { get: () => Store.displayName({ path: doc.currentBoard, dir: false }) })
  forward(doc, () => workspace, ['autosaveMs', 'stateReady', 'boardsDir', 'backupsDir', 'library'])
  // The history worker answers when the test says so: what the document
  // asked it is kept, and `answer` plays the reply back the way onMessage does.
  const historyWorker = { asked: [], sendMessage(m) { historyWorker.asked.push(m) } }
  const aside = { path: '', written: [], setText(text) { aside.written.push({ path: aside.path, text }) } }
  const History = loadStore(fs.readFileSync(path.join(__dirname, '..', 'BoardHistory.js'), 'utf8'))
  const context = vm.createContext({ doc, session, persistence, Store, History, historyWorker, aside,
    itemModel: items, linkModel: links, Date, Qt: { callLater(f) { f() } },
    saveTimer: { running: false, stop() {}, restart() {} } })
  loadFunctions(doc, sources.document, context)
  // A signal is a function to call in QML; the harness's own stands in for it.
  doc.edited = doc.edited.bind(doc)
  loadFunctions(session, sources.session, context)
  // Two of the session's functions reach for a FileView and a Process. What
  // they fetch is what matters here, so they fetch it from the test instead.
  session.diskText = ''
  session.readDisk = () => session.diskText
  session.requestDisk = resolve => session.acceptDisk(doc.currentBoard,
    doc.fileText(), resolve, 'rev-fresh\n' + session.diskText)
  let revisions = 0
  return { doc, session, persistence, items, links, writes, worker: historyWorker, aside,
    // What the worker would say back, delivered the way onMessage delivers it.
    answer(reply) {
      if (reply.token !== doc.historyToken) return
      if (reply.kind === 'checked') doc.checkedHistory(reply)
      else if (reply.kind === 'trimmed') doc.trimmedHistory(reply)
    },
    complete() {
      const write = writes[writes.length - 1]
      persistence.busy = false
      session.savedBoard(write.path, write.text, 'rev-' + (++revisions))
    },
    // The helper refused the write: the file is no longer what this session
    // last saw. `disk` is what is there instead.
    refuse(disk) {
      const write = writes[writes.length - 1]
      persistence.busy = false
      session.diskText = disk
      session.staleSave(write.path, 'rev-external')
    } }
}

// One view, with the camera, selection and modes the QML pane starts with.
function makePane(workspace, exchange, Store) {
  const root = { workspace, doc: null, selectedIndex: -1, editIndex: -1, linkingFrom: -1, cursorId: -1,
    camX: 0, camY: 0, zoom: 1, activeBoard: null, markedIds: [], showPinned: false, arranging: false,
    finding: false, findQuery: '', findCount: 0, imageQueue: [], leaving: false, textEditor: null,
    menuVisible: false, zoomMenuVisible: false, menuIndex: 0, helpVisible: false,
    paletteVisible: false, paletteQuery: '', paletteIndex: 0, paletteRows: 9,
    conflictVisible: false, conflictIndex: 0, paletteScope: 'all', imageBusy: false,
    statusText: '', failureText: '', failureKind: '', pendingFirstNote: '', forgetArmedAt: 0,
    worldStep: 40, minItemSize: 60, viewW: 1000, viewH: 700 }
  const empty = new FakeModel()
  // What the pane reads off its document and the workspace.
  for (const key of ['items', 'links'])
    Object.defineProperty(root, key, { get: () => root.doc ? root.doc[key] : empty })
  Object.defineProperty(root, 'nextId', { get: () => root.doc ? root.doc.nextId : 1 })
  for (const key of ['boardLoaded', 'damaged', 'diskChanged', 'saving'])
    Object.defineProperty(root, key, { get: () => !!root.doc && root.doc[key] })
  for (const key of ['damageReason', 'saveError', 'currentBoard', 'boardTitle'])
    Object.defineProperty(root, key, { get: () => root.doc ? root.doc[key] : '' })
  Object.defineProperty(root, 'pendingBoard', { get: () => root.doc ? root.doc.pendingBoard : null })
  Object.defineProperty(root, 'boardPath', { get: () => root.doc ? root.doc.boardPath : '' })
  // The harness has always read canEdit as the session's own answer: the
  // library and an export pausing it are tested where they happen.
  Object.defineProperty(root, 'canEdit', { get: () => !!root.doc && root.doc.canEdit && !root.leaving })
  forward(root, () => workspace, ['opened', 'stateReady', 'step', 'showGrid', 'canvasPattern', 'library',
    'dataDir', 'boardsDir', 'imagesDir', 'split'])
  Object.defineProperty(root, 'active', { get: () => workspace.activePane === root })
  Object.defineProperty(root, 'browsing', { get: () => root.active && workspace.library.showing })
  // Mirrors the QML binding of the same name: the harness loads functions, not
  // bindings, so a derived property has to be declared here.
  Object.defineProperty(root, 'findDimming', { get: () => root.finding && root.findQuery !== '' })
  Object.defineProperty(root, 'findNeedle', { get: () => root.findQuery.toLowerCase() })
  Object.defineProperty(root, 'paletteMatches', { get: () =>
    root.paletteVisible ? Store.matchCommands(root.paletteQuery, root.paletteScope) : [] })
  Object.defineProperty(root, 'exchangeBusy', { get: () => !!exchange.busy })
  // The binding the failure timer runs on, which the QML declares and this
  // harness would otherwise not have. Same shape as the original, so a change
  // to one shows up as a difference from the other.
  Object.defineProperty(root, 'failureVisible', { get: () =>
    Store.statusTier(root.statusState()) === 'failure' })
  // The binding the status line reads while a connector is being drawn.
  Object.defineProperty(root, 'linkOutcome', { get: () => {
    if (root.linkingFrom < 0 || !root.canEdit) return 'none'
    if (root.selectedIndex < 0 || root.selectedIndex >= root.items.count) return 'none'
    const n = root.items.get(root.selectedIndex)
    if (!n || n.ipinned) return 'none'
    return Store.linkAt(root.links, root.linkingFrom, n.iid).outcome
  } })
  Object.defineProperty(root, 'markedLookup', { get: () => {
    const lookup = {}
    for (const id of root.markedIds) lookup[id] = true
    return lookup
  } })
  // onSelectedIndexChanged, which the QML has and a plain field does not.
  let selected = -1
  Object.defineProperty(root, 'selectedIndex', {
    get: () => selected,
    set: value => { if (value === selected) return; selected = value; root.cursorId = root.idAt(value) }
  })
  const context = vm.createContext({ root, Store,
    statusTimer: { restart() {} }, failureTimer: { restart() {} } })
  loadFunctions(root, sources.pane, context)
  return root
}

function controller() {
  // One copy of BoardStore for everything, so a test that changes a table in
  // it changes it for every object reading it, as the one import does in QML.
  const Store = loadStore()
  const workspace = { opened: true, stateReady: true, windowMode: false, autosaveMs: 700, step: 40,
    showGrid: true, canvasPattern: 'Dots', canvasBackgroundChosen: false, startWindowed: false,
    boardsDir: '/boards', backupsDir: '/backups', dataDir: '/data', imagesDir: '/data/images',
    locksDir: '/data/locks', helperScript: '/BoardFiles.sh', launchNewBoard: false, launchOpenPath: '',
    copyingFor: null, documents: [], panes: [], layout: 'single', splitRatio: 0.5, pendingLeave: null }
  Object.defineProperty(workspace, 'split', { get: () => workspace.layout !== 'single' })
  Object.defineProperty(workspace, 'imageBusy', { get: () => workspace.paneSlots.some(p => p.imageBusy) })
  const states = []
  // Stands in for BoardExchange: the controller hands it filtered paths and
  // never learns what happens to them.
  const exchange = { imported: [], copied: [], copies: [], chosen: [], busy: false, dialogOpen: false,
    // The file dialog belongs to the desktop; what the controller does with it
    // is ask for one, which is the part worth watching here.
    choose(action) { exchange.chosen.push(action) },
    importDropped(entries) { exchange.imported.push(...entries) },
    copyItems(indices) { exchange.copied.push(Array.from(indices)) },
    saveCopy(text, name) { exchange.copies.push({ text, name }); return true } }
  workspace.exchange = exchange
  const first = makePane(workspace, exchange, Store), second = makePane(workspace, exchange, Store)
  workspace.paneSlots = [first, second]
  workspace.panes = [first, second]
  workspace.activePane = first
  // Every document the workspace makes, with the handles a test drives it by.
  const made = new Map()
  const documentComponent = { createObject(parent, props) {
    const d = makeDocument(workspace, props.currentBoard, Store)
    // Component.onCompleted, which the harness does not run.
    if (props.fresh) d.session.createWhenLoaded = true
    d.doc.fresh = props.fresh === true
    made.set(d.doc, d)
    return d.doc
  } }
  const opened = makeDocument(workspace, 'a.json', Store)
  made.set(opened.doc, opened)
  first.doc = opened.doc
  workspace.documents = [opened.doc]
  // The library, run from BoardLibrary.qml and wired to the workspace the way
  // Omarchyform.qml wires it. What it is told and its bindings are mirrored.
  const library = { boardsDir: '/boards', trashDir: '/trash', trashIndexPath: '/trash/index.json',
    helperScript: '/BoardFiles.sh', showing: false, dir: '', query: '', index: 0, entries: [],
    searching: false, promptLabel: '', input: '', action: '', pendingDelete: '', message: '', inTrash: false,
    trashEntries: [], trashIndexSaving: false, trashIndexLoading: true, trashIndexNeedsRead: true, trashIndexError: '' }
  Object.defineProperty(library, 'currentBoard', { get: () => workspace.activePane.currentBoard })
  Object.defineProperty(library, 'openBoards', { get: () => workspace.documents.map(d => d.currentBoard) })
  Object.defineProperty(library, 'boardConflicted', { get: () => workspace.documents.some(d => d.diskChanged) })
  Object.defineProperty(library, 'boardSettled', { get: () =>
    workspace.documents.every(d => !d.saving && d.saveError === '') })
  // The listing, the trash index and the helper's runs; none of them is the
  // subject of these tests, so each is present and inert.
  const trashIndexFile = { reload() {}, setText() {} }
  const inert = () => ({ running: false, command: [] })
  const scanProc = inert(), mkdirProc = inert(), moveProc = inert()
  const trashProc = inert(), restoreProc = inert(), purgeProc = inert()
  Object.defineProperty(library, 'busy', { get: () => mkdirProc.running || moveProc.running || trashProc.running
    || restoreProc.running || purgeProc.running || library.trashIndexSaving || library.trashIndexLoading })
  Object.defineProperty(library, 'rows', { get: () => library.inTrash
    ? Store.sortedTrash(library.trashEntries) : Store.filterEntries(library.entries, library.dir, library.query) })
  library.openRequested = (path, fresh) => workspace.activePane.openBoard(path, fresh)
  library.openBoardMoved = (from, to) => {
    const doc = workspace.documentAt(from)
    if (doc) doc.currentBoard = to
    workspace.writeState()
  }
  library.notice = message => workspace.activePane.flash(message)
  library.closed = () => workspace.activePane.focusKeys()
  library.aboutToRename = () => {
    workspace.activePane.flushSave()
    for (const doc of workspace.documents) if (doc !== workspace.activePane.doc) doc.flushSave()
  }
  workspace.library = library
  loadFunctions(library, sources.library, vm.createContext({ library, Store, trashIndexFile,
    scanProc, mkdirProc, moveProc, trashProc, restoreProc, purgeProc }))
  loadFunctions(workspace, sources.workspace, vm.createContext({ root: workspace, Store, boardExchange: exchange,
    documentComponent, stateFile: { setText(text) { states.push(text) } } }))
  return { root: first, second, doc: opened.doc, workspace, session: opened.session, library,
    items: opened.items, links: opened.links, writes: opened.writes, states, persistence: opened.persistence,
    exchange, store: Store, complete: opened.complete, refuse: opened.refuse,
    worker: opened.worker, aside: opened.aside, answer: opened.answer,
    // The handles for any document the workspace has made since.
    of: doc => made.get(doc) }
}

module.exports = { controller }
