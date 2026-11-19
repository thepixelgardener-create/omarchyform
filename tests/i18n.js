#!/usr/bin/env node
// The board's catalogs, held to the source.
//
// Everything the board says is English in the source: written out where it is
// said, as t("…") or tn("one", "other", count), or kept in one of BoardStore's
// tables and said through tv(), which Store.displayStrings() lists. i18n/en.json
// lists every one of them, so whoever translates has one file to work from,
// and this fails when a string is added without it or one is left behind after
// it has gone. Every other catalog may translate only what en.json has, with
// the same %1, %2, the plural forms its language counts in, and no markup.
//
//   node tests/i18n.js                    check
//   node tests/i18n.js --write-english    write i18n/en.json from the source
//   node tests/i18n.js --pending          what each catalog has yet to translate
const fs = require('fs')
const path = require('path')
const assert = require('assert/strict')
const S = require('../bin/store').loadStore()

const root = path.join(__dirname, '..')
const folder = path.join(root, 'i18n')
const english = path.join(folder, 'en.json')

// A string literal as JSON reads it: QML's escapes in these files are JSON's.
const LITERAL = '"((?:[^"\\\\]|\\\\.)*)"'
const unquote = text => JSON.parse('"' + text + '"')

// Every string the views say, by where it is said.
function fromSource() {
  const plain = new Map(), counted = new Map()
  const files = fs.readdirSync(root).filter(f => f.endsWith('.qml')).sort()
  for (const file of files) {
    const source = fs.readFileSync(path.join(root, file), 'utf8')
    for (const m of source.matchAll(new RegExp('\\bt\\(\\s*' + LITERAL, 'g'))) {
      const text = unquote(m[1])
      if (!plain.has(text)) plain.set(text, file)
    }
    for (const m of source.matchAll(new RegExp('\\btn\\(\\s*' + LITERAL + '\\s*,\\s*' + LITERAL, 'g'))) {
      const one = unquote(m[1]), other = unquote(m[2])
      const known = counted.get(other)
      assert.ok(!known || known.one === one, `${file}: "${other}" is counted with two singulars, "${known && known.one}" and "${one}"`)
      counted.set(other, { one, other, file })
    }
  }
  for (const text of S.displayStrings()) if (!plain.has(text)) plain.set(text, 'BoardStore.js')
  for (const other of counted.keys())
    assert.ok(!plain.has(other), `"${other}" is said both counted and not: one catalog entry cannot be both`)
  return { plain, counted }
}

// What en.json should say: each string as itself, each counted one by its
// English forms, keyed by its plural.
function englishCatalog(found) {
  const out = {}
  const keys = [...found.plain.keys(), ...found.counted.keys()].sort()
  for (const key of keys)
    out[key] = found.counted.has(key) ? { one: found.counted.get(key).one, other: key } : key
  return out
}

const holes = text => [...String(text).matchAll(/%([1-9])/g)].map(m => m[1]).sort().join(',')

// Everything wrong with one language's catalog, by entry.
function catalogProblems(code, catalog, reference) {
  const problems = []
  if (!catalog || typeof catalog !== 'object' || Array.isArray(catalog)) return [`${code}: not a JSON object`]
  const needed = new Set()
  for (let n = 0; n <= 1000; n++) needed.add(S.pluralCategory(code, n))
  needed.add(S.pluralCategory(code, 1000000))
  for (const [key, value] of Object.entries(catalog)) {
    const where = `${code}: "${key}"`
    if (!Object.prototype.hasOwnProperty.call(reference, key)) { problems.push(`${where} is not in en.json`); continue }
    const source = reference[key]
    const forms = typeof source === 'string' ? null : source
    if (forms === null) {
      if (typeof value !== 'string') { problems.push(`${where} is a plain string in English`); continue }
      if (holes(value) !== holes(key)) problems.push(`${where} has ${holes(value) || 'no holes'}, English ${holes(key) || 'none'}`)
      checkText(where, value, key, problems)
    } else {
      if (!value || typeof value !== 'object' || Array.isArray(value)) { problems.push(`${where} is counted in English: give its forms`); continue }
      if (typeof value.other !== 'string') problems.push(`${where} has no "other" form`)
      for (const category of needed)
        if (typeof value[category] !== 'string') problems.push(`${where} has no "${category}" form, which ${code} counts in`)
      const allowed = new Set(holes(forms.other).split(',').filter(Boolean))
      for (const [category, form] of Object.entries(value)) {
        if (!['zero', 'one', 'two', 'few', 'many', 'other'].includes(category)) { problems.push(`${where}: "${category}" is not a plural form`); continue }
        if (typeof form !== 'string') { problems.push(`${where}: its "${category}" form is not a string`); continue }
        for (const hole of holes(form).split(',').filter(Boolean))
          if (!allowed.has(hole)) problems.push(`${where}: its "${category}" form has %${hole}, which English does not`)
        checkText(`${where} (${category})`, form, forms.other, problems)
      }
      if (typeof value.other === 'string' && holes(value.other) !== holes(forms.other))
        problems.push(`${where}: its "other" form has ${holes(value.other) || 'no holes'}, English ${holes(forms.other) || 'none'}`)
    }
  }
  return problems
}

// A translation is text: it may not bring markup the English does not have,
// since several lines are drawn as markup, nor anything that is not printable.
function checkText(where, text, english, problems) {
  if (text.trim() === '') problems.push(`${where} is empty`)
  if (/[<>&]/.test(text) && !/[<>&]/.test(english)) problems.push(`${where} brings markup characters`)
  if (/[\u0000-\u0009\u000b-\u001f\u007f]/.test(text)) problems.push(`${where} holds a control character`)
}

const found = fromSource()
const wanted = englishCatalog(found)

if (process.argv.includes('--write-english')) {
  fs.mkdirSync(folder, { recursive: true })
  fs.writeFileSync(english, JSON.stringify(wanted, null, 2) + '\n')
  console.log(`wrote ${Object.keys(wanted).length} strings to i18n/en.json`)
  process.exit(0)
}

const reference = JSON.parse(fs.readFileSync(english, 'utf8'))
const catalogs = fs.readdirSync(folder).filter(f => f.endsWith('.json') && f !== 'en.json').sort()

if (process.argv.includes('--pending')) {
  const total = Object.keys(reference).length
  for (const file of catalogs) {
    const catalog = JSON.parse(fs.readFileSync(path.join(folder, file), 'utf8'))
    const missing = Object.keys(reference).filter(k => !Object.prototype.hasOwnProperty.call(catalog, k))
    console.log(`${file.replace(/\.json$/, '')}: ${total - missing.length} of ${total}` + (missing.length ? '; missing:' : ''))
    for (const key of missing) console.log('  ' + JSON.stringify(key))
  }
  process.exit(0)
}

// The English catalog is the source's, exactly.
const written = Object.keys(reference), expected = Object.keys(wanted)
const unlisted = expected.filter(k => !written.includes(k)), stale = written.filter(k => !expected.includes(k))
assert.deepEqual(unlisted, [], 'said in the source and missing from i18n/en.json (node tests/i18n.js --write-english)')
assert.deepEqual(stale, [], 'in i18n/en.json and no longer said anywhere (node tests/i18n.js --write-english)')
assert.deepEqual(reference, wanted, 'i18n/en.json says each string as the source does (node tests/i18n.js --write-english)')

// Every catalog, each against the languages Omarchy has.
const problems = []
for (const file of catalogs) {
  const code = file.replace(/\.json$/, '')
  if (S.languageCode(code) !== code) { problems.push(`${file}: not a language code Omarchy uses`); continue }
  let catalog
  try { catalog = JSON.parse(fs.readFileSync(path.join(folder, file), 'utf8')) } catch (e) { problems.push(`${file}: ${e.message}`); continue }
  problems.push(...catalogProblems(code, catalog, reference))
}
assert.deepEqual(problems, [], 'catalogs that do not fit en.json')

// The checks above, on catalogs made to break them.
{
  const ref = { 'Saved as %1': 'Saved as %1', '%1 items': { one: '%1 item', other: '%1 items' }, 'a <b>': 'a <b>' }
  const say = (code, catalog) => catalogProblems(code, catalog, ref)
  assert.deepEqual(say('de', { 'Saved as %1': 'Gespeichert als %1', '%1 items': { one: '%1 Element', other: '%1 Elemente' } }), [])
  assert.equal(say('de', { 'Saved as %1': 'Gespeichert' }).length, 1, 'a hole left out')
  assert.equal(say('de', { 'Saved as %1': 'Gespeichert als %2' }).length, 1, 'a hole made up')
  assert.equal(say('de', { 'Unknown': 'x' }).length, 1, 'a string English does not have')
  assert.equal(say('de', { '%1 items': '%1 Elemente' }).length, 1, 'a counted string given one form')
  assert.equal(say('ru', { '%1 items': { one: '%1 a', other: '%1 b' } }).length, 2, 'Russian counts in few and many too')
  assert.equal(say('de', { 'Saved as %1': '<b>%1</b>' }).length, 1, 'markup brought in')
  assert.deepEqual(say('de', { 'a <b>': 'ein <b>' }), [], 'markup English has already')
  assert.equal(say('de', { 'Saved as %1': '%1\u0007' }).length, 1, 'a control character')
  assert.equal(say('de', { 'a <b>': ' ' }).length, 1, 'nothing at all')
  assert.equal(say('xx', []).length, 1, 'an array is not a catalog')
}

// What the board does with them, in the store the views call.
{
  const de = { 'Saved as %1': 'Gespeichert als %1', '%1 items': { one: '%1 Element', other: '%1 Elemente' } }
  assert.equal(S.translated(de, 'Saved as %1', ['x']), 'Gespeichert als x')
  assert.equal(S.translated(de, 'Not there', []), 'Not there', 'English where a catalog has nothing')
  assert.equal(S.translated(null, 'Saved as %1', ['%2']), 'Saved as %2', 'what is put in is not read for holes')
  assert.equal(S.translated({ constructor: 'x' }, 'toString', []), 'toString')
  assert.equal(S.translatedCount(de, 'de', '%1 item', '%1 items', 1), '1 Element')
  assert.equal(S.translatedCount(de, 'de', '%1 item', '%1 items', 4), '4 Elemente')
  assert.equal(S.translatedCount({}, 'de', '%1 item', '%1 items', 4), '4 items')
  assert.equal(S.translatedCount({ '%1 items': { other: '%1 Elemente' } }, 'de', '%1 item', '%1 items', 1), '1 Elemente',
    'a missing form falls back to "other", as the shell does')
  const ru = { '%1 items': { one: '%1 элемент', few: '%1 элемента', many: '%1 элементов', other: '%1 элемента' } }
  assert.deepEqual([1, 3, 5, 11, 21, 102].map(n => S.translatedCount(ru, 'ru', '%1 item', '%1 items', n)),
    ['1 элемент', '3 элемента', '5 элементов', '11 элементов', '21 элемент', '102 элемента'])
  assert.equal(S.languageCode('de\n'), 'de')
  assert.equal(S.languageCode('pt-BR'), 'pt-BR')
  assert.equal(S.languageCode('../../etc'), 'en', 'nothing that could be a path')
  assert.equal(S.languageCode(''), 'en')
  assert.deepEqual(S.languageChain('pt-BR'), ['pt-BR', 'pt'])
  assert.deepEqual(S.languageChain('en'), [])
  // A key lights its word only while the word still starts with it.
  assert.equal(S.hintMarkup('a', 'add board', '#fff', () => 'Tafel hinzufügen'), '<font color="#fff">a</font>: Tafel hinzufügen')
  assert.equal(S.hintMarkup('a', 'add board', '#fff', () => 'anlegen'), '<font color="#fff">a</font>nlegen')
}

const total = Object.keys(reference).length
console.log(`ok — languages: i18n/en.json holds the ${total} strings the board says; ` +
  (catalogs.length ? catalogs.map(f => f.replace(/\.json$/, '')).join(', ') + ' fit it' : 'no other catalog yet'))
