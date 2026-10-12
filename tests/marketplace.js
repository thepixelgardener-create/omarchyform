#!/usr/bin/env node
// What the marketplace's Automated Security Baseline will say about this
// plugin, before it is submitted: the marketplace's own scanner, at a pinned
// commit, run against the commit to be submitted. The GitHub requests the
// scanner makes are answered from git instead of the network, so it reads
// exactly what it would read on GitHub, and nothing of the plugin is executed,
// by it or by this.
//
//   npm run review:marketplace                   HEAD, against the pinned scanner
//   npm run review:marketplace -- --commit=SHA   another commit
//   npm run review:marketplace -- --latest       the marketplace's scanner as it is now
//   MARKETPLACE_CHECKOUT=/path npm run ...       a marketplace checkout already on disk
//
// It fails on any finding, on any capability not accepted below for the paths
// it is accepted for, and when the scan cannot complete. The scanner is
// fetched (only its scripts/ folder, about 2 MB) into the cache once per
// pinned commit. Only what is committed is scanned, as on GitHub.
//
// The marketplace's maintainers review the exact commit by hand as well; what
// they look for is in docs/security-review.md, "Before submitting".

const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')
const { pathToFileURL } = require('url')

const MARKETPLACE = 'https://github.com/omacom/omarchy-plugin-marketplace'
// The scanner this was last checked against, and the baseline policy version
// it implements. A newer policy is reported, so its rules can be read before
// the pin is moved: SECURITY.md, "Automated Security Baseline".
const PINNED = '05b8c4243b4c6b3e05e81cf654560e24d22852e9'
const POLICY = '3'

// Capabilities a maintainer is asked to accept, and why they can be: each only
// at the paths named. A new path or a new capability fails until it is either
// removed or added here with its reason, which is what the submission's
// maintainer notes then say.
const ACCEPTED = {
  installer: {
    paths: ['desktop/install.sh'],
    why: 'the optional launcher entry, run only by hand: it writes three files (launcher entry, file type, opener), ' +
      'replaces or removes one only while it is still its own and unchanged unless told --force, and checks every one ' +
      'before writing any (tests/desktop.js)'
  }
}

const repo = path.join(__dirname, '..')
const argument = name => (process.argv.find(a => a.startsWith(`--${name}=`)) || '').slice(name.length + 3)
const git = (cwd, ...args) => execFileSync('git', ['-C', cwd, ...args], { maxBuffer: 1 << 30 })

function scanner() {
  if (process.env.MARKETPLACE_CHECKOUT) return { dir: process.env.MARKETPLACE_CHECKOUT, commit: 'local checkout' }
  const latest = process.argv.includes('--latest')
  const cache = path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), '.cache'), 'omarchyform')
  const dir = path.join(cache, latest ? 'marketplace-latest' : `marketplace-${PINNED}`)
  if (latest || !fs.existsSync(path.join(dir, 'scripts', 'security-baseline-scanner.mjs'))) {
    fs.rmSync(dir, { recursive: true, force: true })
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 })
    git(dir, 'init', '-q')
    git(dir, 'remote', 'add', 'origin', MARKETPLACE)
    git(dir, 'sparse-checkout', 'set', '--no-cone', '/scripts/')
    git(dir, 'fetch', '-q', '--depth', '1', '--filter=blob:none', 'origin', latest ? 'main' : PINNED)
    git(dir, '-c', 'advice.detachedHead=false', 'checkout', '-q', '--detach', 'FETCH_HEAD')
  }
  return { dir, commit: git(dir, 'rev-parse', 'HEAD').toString().trim() }
}

// owner/name, off the end of the remote: github.com in CI, a proxy locally.
function slug() {
  if (argument('repo')) return argument('repo')
  const url = git(repo, 'remote', 'get-url', 'origin').toString().trim().replace(/\.git$/, '')
  return url.split(/[/:]/).slice(-2).join('/')
}

async function main() {
  const { dir, commit: scannerCommit } = scanner()
  const load = name => import(pathToFileURL(path.join(dir, 'scripts', name)).href)
  const { runSecurityBaseline } = await load('security-baseline-scanner.mjs')
  const { buildSecurityBaselineReport } = await load('security-baseline-report.mjs')
  const scope = await load('security-baseline-scope.mjs')
  const limits = await load('security-baseline-limits.mjs')

  const commit = git(repo, 'rev-parse', argument('commit') || 'HEAD').toString().trim()
  const [owner, name] = slug().split('/')
  const treeSha = git(repo, 'rev-parse', `${commit}^{tree}`).toString().trim()
  const tree = git(repo, 'ls-tree', '-r', '-t', '-l', '-z', commit).toString().split('\0').filter(Boolean).map(line => {
    const [meta, file] = line.split('\t')
    const [mode, type, sha, size] = meta.trim().split(/\s+/)
    return type === 'blob' ? { path: file, mode, type, sha, size: Number(size) } : { path: file, mode, type, sha }
  })
  const manifest = JSON.parse(git(repo, 'show', `${commit}:manifest.json`).toString())

  // The answers GitHub would give, from git.
  const json = value => new Response(JSON.stringify(value), { status: 200, headers: { 'content-type': 'application/json' } })
  async function fetchImpl(url, options = {}) {
    const u = new URL(url)
    if (u.hostname === 'api.github.com') {
      if (u.pathname === `/repos/${owner}/${name}`) return json({ private: false, disabled: false, archived: false })
      if (u.pathname === `/repos/${owner}/${name}/commits/${commit}`) return json({ sha: commit, commit: { tree: { sha: treeSha } } })
      if (u.pathname === `/repos/${owner}/${name}/git/trees/${treeSha}`) return json({ sha: treeSha, truncated: false, tree })
    }
    const prefix = `/${owner}/${name}/${commit}/`
    if (u.hostname === 'raw.githubusercontent.com' && u.pathname.startsWith(prefix)) {
      const bytes = git(repo, 'show', `${commit}:${decodeURIComponent(u.pathname.slice(prefix.length))}`)
      const range = /^bytes=0-(\d+)$/.exec((options.headers || {}).Range || '')
      if (!range) return new Response(bytes, { status: 200 })
      const end = Math.min(bytes.length - 1, Number(range[1]))
      return new Response(bytes.subarray(0, end + 1), { status: 206, headers: { 'content-range': `bytes 0-${end}/${bytes.length}` } })
    }
    return new Response('not found', { status: 404 })
  }

  const result = await runSecurityBaseline(`https://github.com/${owner}/${name}`, commit, {
    fetchImpl, token: '', requiredPaths: Object.values(manifest.entryPoints || {}),
    listedPlugins: [{ pluginId: manifest.id, manifestPathHint: 'manifest.json' }]
  })
  process.stdout.write(buildSecurityBaselineReport(result, { context: 'submission' }) + '\n')

  const problems = []
  if (result.baselineVersion !== POLICY)
    problems.push(`the marketplace's baseline policy is now ${result.baselineVersion}, not ${POLICY}: read SECURITY.md before moving the pin`)
  for (const finding of result.findings)
    problems.push(`finding ${finding.ruleId || finding.id}: ${(finding.evidence || [finding]).map(e => `${e.path}:${e.line}`).join(", ")}`)
  for (const capability of result.capabilities) {
    const accepted = ACCEPTED[capability.id]
    const paths = [...new Set((capability.evidence || []).map(e => e.path))]
    const unexpected = accepted ? paths.filter(p => !accepted.paths.includes(p)) : paths
    if (!accepted) problems.push(`capability ${capability.id} is not one this plugin has a reason for: ${paths.join(', ')}`)
    else if (unexpected.length) problems.push(`capability ${capability.id} at ${unexpected.join(', ')}, beyond ${accepted.paths.join(', ')}`)
    else console.log(`accepted: ${capability.id} (${paths.join(', ')}): ${accepted.why}`)
  }

  // How close the scan is to the limits past which it fails closed.
  const scanned = tree.filter(e => e.type === 'blob' && scope.isSecurityScanPath(e.path))
  const total = scanned.reduce((sum, e) => sum + e.size, 0)
  const largest = scanned.reduce((a, b) => (b.size > a.size ? b : a), { size: 0, path: '' })
  console.log(`scanned ${scanned.length} of ${limits.securitySnapshotFileLimit} files, ${Math.round(total / 1024)} of ` +
    `${limits.securitySnapshotByteLimit / 1024} KiB; largest ${largest.path}, ${Math.round(largest.size / 1024)} of ` +
    `${limits.securityFileByteLimit / 1024} KiB`)
  if (scanned.length > 0.75 * limits.securitySnapshotFileLimit || total > 0.75 * limits.securitySnapshotByteLimit ||
      largest.size > 0.75 * limits.securityFileByteLimit)
    problems.push('within a quarter of a limit the scan fails closed at: split or trim the largest files')

  const dirty = git(repo, 'status', '--porcelain', '--untracked-files=no').toString().trim()
  if (dirty && !argument('commit')) console.log('note: uncommitted changes are not scanned; only the commit is, as on GitHub')
  console.log(`scanner ${scannerCommit}, commit ${commit}`)
  if (problems.length) {
    for (const p of problems) console.error('  ' + p)
    console.error(`FAILED — ${problems.length} problem(s) the marketplace would raise`)
    process.exit(1)
  }
  console.log(`ok — marketplace baseline: ${result.outcome}, no findings, every capability accepted with its reason`)
}

main().catch(error => {
  console.error(`FAILED — the baseline could not complete: ${error.code || ''} ${error.message}`)
  process.exit(1)
})
