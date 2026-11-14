import QtQuick
import Quickshell
import Quickshell.Io
import "BoardStore.js" as Store

// The language the board speaks, which is the one Omarchy is set to.
//
// Setup > Language writes its choice to ~/.config/omarchy/language, and
// Omarchy's own apps follow that file; so does this, while it is open, so a
// switch shows without a restart. The catalogs are in i18n/ beside this file,
// one JSON object for each language, from the English text to its
// translation. English has none to load: it is the text in the source, and
// whatever a catalog lacks is said in English, string by string.
//
// Everything on screen asks t() or tn() here, through its controller. Both
// read `catalog`, so a binding that calls one is evaluated again when the
// language changes; what was said once and kept, a message already on the
// line, stays as it was said.
Item {
  id: language

  // "en" until a catalog for something else has been read.
  property string code: "en"
  property var catalog: ({})

  function t(text, a, b, c) { return Store.translated(language.catalog, text, [a, b, c]) }
  function tn(one, other, count, a, b) {
    return Store.translatedCount(language.catalog, language.code, one, other, count, [a, b])
  }

  readonly property string folder: decodeURIComponent(Qt.resolvedUrl("i18n").toString().replace(/^file:\/\//, ""))
  // OMARCHY_LANGUAGE_FILE names another file, as it does for the shell and
  // for omarchy-i18n, so a test can pin a language whatever the machine uses.
  readonly property string chosenPath: Quickshell.env("OMARCHY_LANGUAGE_FILE")
    || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/language")

  // The language being loaded, and the catalogs still to try for it: the
  // most particular first, pt-BR and then pt.
  property string wanted: "en"
  property var trying: []

  function follow(raw) {
    var code = Store.languageCode(raw)
    if (code === language.wanted) return
    language.wanted = code
    language.trying = Store.languageChain(code)
    language.tryNext()
  }

  function tryNext() {
    if (language.trying.length === 0) {
      // English, or a language there is no catalog for: the source's own text.
      language.catalog = ({})
      language.code = "en"
      catalogFile.path = ""
      return
    }
    var next = language.trying[0]
    language.trying = language.trying.slice(1)
    catalogFile.loading = next
    catalogFile.path = ""
    catalogFile.path = language.folder + "/" + next + ".json"
  }

  FileView {
    path: language.chosenPath
    watchChanges: true
    printErrors: false
    onLoaded: language.follow(text())
    // No file is no choice made, which is English.
    onLoadFailed: language.follow("")
    onFileChanged: reload()
  }

  FileView {
    id: catalogFile
    property string loading: ""
    watchChanges: false
    printErrors: false
    onLoaded: {
      // This program's own file, read as anything else is: bounded, and one
      // that is not a catalog is passed over rather than half used.
      var read = null
      try { read = Store.parseJson(text()) } catch (e) { read = null }
      if (!read || typeof read !== "object" || Array.isArray(read)) { Qt.callLater(language.tryNext); return }
      language.catalog = read
      language.code = language.wanted
    }
    // The next catalog is asked for on the next turn: a path changed inside
    // this FileView's own answer is not one it goes on to read.
    onLoadFailed: Qt.callLater(language.tryNext)
  }
}
