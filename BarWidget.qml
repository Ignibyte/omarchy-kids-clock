import QtQuick
import qs.Commons
import qs.Ui

// The bar face: the sun by day and the moon by night for home, in the bar's
// own foreground so it re-tints with the theme. Click opens the big clock.
BarWidget {
  id: root
  moduleName: "ignibyte.kids-clock"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(root.moduleName) : null

  readonly property string glyph: service ? service.barGlyph : ""
  readonly property string tooltip: service ? service.tooltip : "Sun Clock"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    fontSize: Style.font.icon
    tooltipText: root.tooltip
    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton && root.service) root.service.resetScrub()
      else root.bar.run("omarchy-shell shell toggle ignibyte.kids-clock '{}'")
    }
  }
}
