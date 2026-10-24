// What a measurement was taken on. A frame time means nothing without it —
// the same board is vsync-bound at 60Hz and drops frames at 144 — and a figure
// quoted in a changelog a year from now is only checkable against the machine
// that produced it. Everything here is read from what is already installed and
// every probe is allowed to fail: a missing tool costs one row, not a run.
const { spawnSync } = require('child_process')

const omarchy = process.env.OMARCHY_PATH || '/usr/share/omarchy'

function ask(command) {
  try {
    const out = spawnSync('sh', ['-c', command], { encoding: 'utf8', timeout: 5000 })
    const text = (out.stdout || '').trim()
    return text === '' ? null : text.split('\n')[0]
  } catch { return null }
}

// The screen the numbers were measured on, scale included. A fractionally
// scaled display draws more pixels than its resolution says, and that is the
// first thing to check when a frame time will not reproduce elsewhere.
function display() {
  try {
    const out = spawnSync('hyprctl', ['-j', 'monitors'], { encoding: 'utf8', timeout: 5000 })
    const monitors = JSON.parse(out.stdout || '[]')
    if (monitors.length === 0) return null
    const one = monitors.find(m => m.focused) || monitors[0]
    const scale = Number(one.scale)
    return `${one.width}\u00d7${one.height} at ${scale}x, `
      + (monitors.length > 1 ? `${monitors.length} outputs` : 'single output')
  } catch { return null }
}

// screen: false for a measurement taken offscreen, which no display touches.
function provenance(screen = true) {
  return [
    ['Qt', ask('qmake6 -query QT_VERSION || /usr/lib/qt6/bin/qmake6 -query QT_VERSION')],
    ['Quickshell', ask(`qs --version 2>&1 | sed 's/^Quickshell //; s/ *(revision.*//'`)],
    ...(screen ? [
      ['Compositor', ask(`hyprctl version -j 2>/dev/null | sed -n 's/.*"version": *"\\([^"]*\\)".*/Hyprland \\1/p'`)],
      ['Refresh', ask(`hyprctl monitors -j 2>/dev/null | sed -n 's/.*"refreshRate": *\\([0-9]*\\.[0-9]\\).*/\\1 Hz/p'`)],
      ['GPU', ask(`lspci 2>/dev/null | grep -iE 'vga|3d' | head -1 | sed 's/.*: //'`)]
    ] : []),
    ['CPU', ask(`sed -n 's/^model name[ \t]*: //p' /proc/cpuinfo | head -1`)],
    ['OS', ask(`. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME"`)],
    // The two ways this machine names its Omarchy disagree — the version file
    // says the release, the package says the revision. A bug report carries the
    // package version, so that is the one recorded here and in docs/install.md.
    ['Omarchy', ask(`omarchy-version 2>/dev/null || cat ${omarchy}/version 2>/dev/null`)],
    ...(screen ? [['Display', display()]] : [])
  ].filter(row => row[1])
}

module.exports = { provenance }
