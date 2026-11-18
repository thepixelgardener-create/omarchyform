pragma Singleton
import QtQuick
import "Strings.js" as Strings
import "Numbers.js" as Numbers

// The strings the kit's own components show (Cancel, Search...), in the language picked under
// Setup > Language (`omarchy language`), with that language's direction and digits. The same
// interface as the Omarchy shell's I18n, backed by the few catalog entries bin/harvest-qt
// extracts instead of the shell's full catalogs. An app translates its own strings with qsTr.
//
// Set `lookup` to route the kit's keys through an app's own translator:
//   I18n.lookup = function(key, fallback) { return myTranslator.t(key) || fallback }
QtObject {
  id: root

  readonly property string language: languageCode(ThemeSource.languageText)
  readonly property var localeSettings: Strings.locales[root.language] || ({})
  readonly property string formatLocale: localeSettings.formatLocale || "en-US"
  readonly property string decimal: localeSettings.decimal || "."
  readonly property string zeroDigit: localeSettings.zeroDigit || "0"
  readonly property bool rightToLeft: localeSettings.direction === "rtl"

  property var lookup: null

  function languageCode(raw) {
    var code = String(raw || "").trim()
    if (!/^[a-z]{2,3}(-[A-Za-z]{2})?$/.test(code)) code = "en"
    return code
  }

  function t(key, fallback) {
    if (typeof root.lookup === "function") {
      var custom = root.lookup(key, fallback)
      if (typeof custom === "string" && custom.length > 0) return custom
    }
    var exact = Strings.catalog[root.language] || {}
    var base = Strings.catalog[root.language.split("-")[0]] || {}
    var english = Strings.catalog["en"] || {}
    var value = exact[key] || base[key] || english[key]
    if (value && typeof value === "object") value = value.other
    if (typeof value === "string" && value.length > 0) return value
    return fallback !== undefined ? fallback : key
  }

  function tn(key, count, fallback) {
    return t(key, fallback)
  }

  function formatNumber(value, decimals) {
    return Numbers.format(value, decimals, root.decimal, root.zeroDigit)
  }
}
