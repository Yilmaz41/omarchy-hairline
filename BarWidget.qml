import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Read-only load and temperature readout. Every colour comes from the live
// theme, so a theme switch restyles it with the rest of the bar.
//
//   [label] load%  temp°     load is underlined by a hairline gauge;
//   ‾‾‾‾‾‾‾‾‾‾‾‾‾‾          temp warms from muted to urgent as it heats.
BarWidget {
  id: root
  moduleName: "io.github.yilmaz41.hairline"

  readonly property color fg: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color hot: Commons.Color.urgent
  readonly property color gauge: Commons.Color.accent
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property int size: Style.font.bodySmall

  function mix(a, b, t) {
    t = Math.max(0, Math.min(1, t))
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
  }

  Component.onCompleted: Sampler.start(setting("interval", 2000), setting("gpu", "auto"))

  implicitWidth: row.implicitWidth + Style.space(8) * 2
  implicitHeight: vertical ? row.implicitHeight + Style.space(8) * 2 : barSize

  // Widest possible values, so the bar never reflows as numbers change.
  TextMetrics { id: pctWidth; font.family: root.family; font.pixelSize: root.size; text: "100%" }
  TextMetrics { id: degWidth; font.family: root.family; font.pixelSize: root.size; text: "100°" }

  component Reading: Item {
    id: reading
    property string label
    property int load: -1
    property int temp: -1
    property bool showTemp: true
    property real coolAt: 60
    property real hotAt: 90

    implicitWidth: line.implicitWidth
    implicitHeight: line.implicitHeight + 4

    Row {
      id: line
      spacing: Style.space(4)

      Text {
        text: reading.label
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 0.6
        y: loadText.baselineOffset - baselineOffset
      }

      Item {
        width: pctWidth.advanceWidth
        height: loadText.implicitHeight

        Text {
          id: loadText
          anchors.right: parent.right
          text: reading.load < 0 ? "–" : reading.load + "%"
          color: root.fg
          font.family: root.family
          font.pixelSize: root.size
        }

        // Hairline gauge under the load figure.
        Rectangle {
          anchors.top: loadText.bottom
          anchors.topMargin: 1
          width: parent.width
          height: 2
          radius: 1
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

          Rectangle {
            height: parent.height
            radius: 1
            width: parent.width * Math.max(0, Math.min(100, reading.load)) / 100
            color: reading.load >= 90 ? root.hot : root.gauge
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
          }
        }
      }

      Text {
        visible: reading.showTemp
        width: degWidth.advanceWidth
        horizontalAlignment: Text.AlignRight
        text: reading.temp < 0 ? "–" : reading.temp + "°"
        color: reading.temp < 0 ? root.dim
          : root.mix(root.dim, root.hot, (reading.temp - reading.coolAt) / (reading.hotAt - reading.coolAt))
        font.family: root.family
        font.pixelSize: root.size
      }
    }
  }

  Grid {
    id: row
    anchors.centerIn: parent
    flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
    columns: root.vertical ? 1 : 3
    columnSpacing: Style.space(14)
    rowSpacing: Style.space(8)

    Reading { label: "CPU"; load: Sampler.cpu; temp: Sampler.cpuTemp; coolAt: 60; hotAt: 90 }
    Reading { label: "GPU"; load: Sampler.gpu; temp: Sampler.gpuTemp; coolAt: 60; hotAt: 85; visible: Sampler.gpuAvailable }
    Reading { label: "RAM"; load: Sampler.mem; showTemp: false }
  }
}
