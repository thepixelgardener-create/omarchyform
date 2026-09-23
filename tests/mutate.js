#!/usr/bin/env node
// Mutation testing: break BoardStore.js on purpose, one edit at a time, and
// check the suite notices. A mutant the tests still pass is a hole in them.

const fs = require("fs")
const os = require("os")
const path = require("path")
const { execFileSync } = require("child_process")
const { STORE_PATH } = require("./harness")

// Order matters: longer operators first, so === is not eaten by ==.
const OPERATORS = [
  ["!==", "==="],
  ["===", "!=="],
  [">=", "<"],
  ["<=", ">"],
  ["&&", "||"],
  ["||", "&&"],
  [" + ", " - "],
  [" - ", " + "],
  [" * ", " / "],
  [" > ", " >= "],
  [" < ", " <= "],
  ["Math.max", "Math.min"],
  ["Math.min", "Math.max"],
  ["continue", "break"]
]

const source = fs.readFileSync(STORE_PATH, "utf8")
const lines = source.split("\n")

// Only mutate real code: a comment or a blank line is not behaviour.
function isCode(line) {
  const t = line.trim()
  return t.length > 0 && !t.startsWith("//") && !t.startsWith("*") && !t.startsWith("/*")
}

const mutants = []
for (let i = 0; i < lines.length; i++) {
  if (!isCode(lines[i])) continue
  for (const [from, to] of OPERATORS) {
    let at = lines[i].indexOf(from)
    while (at !== -1) {
      const mutatedLine = lines[i].slice(0, at) + to + lines[i].slice(at + from.length)
      if (mutatedLine !== lines[i]) {
        const copy = lines.slice()
        copy[i] = mutatedLine
        mutants.push({
          line: i + 1,
          from,
          to,
          before: lines[i].trim(),
          after: mutatedLine.trim(),
          source: copy.join("\n")
        })
      }
      at = lines[i].indexOf(from, at + 1)
    }
  }
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "omarchyform-mutants-"))
const runner = path.join(__dirname, "mutant-run.js")
const survivors = []
let killed = 0

for (let i = 0; i < mutants.length; i++) {
  const m = mutants[i]
  const file = path.join(dir, `m${i}.js`)
  fs.writeFileSync(file, m.source)
  try {
    // Exit 0 means the suite passed despite the mutation: it survived.
    execFileSync(process.execPath, [runner, file], { timeout: 15000, stdio: "ignore" })
    survivors.push(m)
  } catch (e) {
    // Non-zero exit or a timeout (an infinite loop is still a detected change).
    killed++
  }
}

fs.rmSync(dir, { recursive: true, force: true })

for (const m of survivors)
  console.log(`  SURVIVED  BoardStore.js:${m.line}  ${m.from} -> ${m.to}\n            ${m.before}`)

const total = mutants.length
const score = total === 0 ? 100 : Math.round((killed / total) * 1000) / 10
console.log(`\nmutation score ${score}% — ${killed}/${total} mutants killed, ${survivors.length} survived`)

// A survivor is a gap in the tests, not a broken build: report, do not fail.
process.exit(0)
