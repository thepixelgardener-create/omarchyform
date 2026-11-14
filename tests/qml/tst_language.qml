import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

// The board's language the whole way through Quickshell: it follows the file
// Setup > Language writes, while it is open, from nothing to German to a
// language there is only a parent catalog for, and back to English for one
// there is none for, one whose catalog is broken, and a file that names
// nothing a language could be. tests/persistence.js writes the catalogs and
// points OMARCHY_LANGUAGE_FILE at a file in the scenario's folder.
ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int stage: 0
  property int ticks: 0
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  FileView { id: chosen; path: test.dir + "/language"; atomicWrites: true; printErrors: false }
  function choose(code) { Qt.callLater(function () { chosen.setText(code + "\n") }) }
  function next(stage) { test.stage = stage; test.ticks = 0 }

  BoardLanguage { id: language }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      test.ticks++
      if (test.stage === 0 && test.ticks > 4) {
        test.check(language.code === "en", "with no choice made the board speaks English: " + language.code)
        test.check(language.t("Saved as %1", "plan") === "Saved as plan", "as written, with what goes in put in")
        test.check(language.tn("%1 item", "%1 items", 1) === "1 item" && language.tn("%1 item", "%1 items", 3) === "3 items",
                   "counted the English way")
        test.choose("de")
        test.next(1)
      } else if (test.stage === 1 && language.code === "de") {
        test.check(language.t("Saved as %1", "plan") === "Gespeichert als plan", "German once German is chosen: " + language.t("Saved as %1", "plan"))
        test.check(language.tn("%1 item", "%1 items", 1) === "1 Element" && language.tn("%1 item", "%1 items", 3) === "3 Elemente",
                   "counted the German way")
        test.check(language.t("Not translated") === "Not translated", "and English for what the catalog lacks")
        test.choose("pt-BR")
        test.next(2)
      } else if (test.stage === 2 && language.code === "pt-BR") {
        test.check(language.t("Saved as %1", "plan") === "Salvo como plan", "pt-BR without a catalog of its own reads pt's")
        test.choose("fi")
        test.next(3)
      } else if (test.stage === 3 && language.code === "en" && test.ticks > 4) {
        test.check(language.t("Saved as %1", "plan") === "Saved as plan", "a catalog that is not one is passed over")
        test.choose("de")
        test.next(4)
      } else if (test.stage === 4 && language.code === "de") {
        test.choose("../../etc/passwd")
        test.next(5)
      } else if (test.stage === 5 && language.code === "en" && test.ticks > 2) {
        test.check(language.t("Saved as %1", "plan") === "Saved as plan", "a file naming no language is English")
        test.choose("ja")
        test.next(6)
      } else if (test.stage === 6 && test.ticks > 6) {
        test.check(language.code === "en", "a language there is no catalog for is English: " + language.code)
        console.log("LANGUAGE_TESTS_PASSED")
        Qt.quit()
      } else if (test.ticks > 120) test.check(false, "stuck at stage " + test.stage + " in " + language.code)
    }
  }
}
