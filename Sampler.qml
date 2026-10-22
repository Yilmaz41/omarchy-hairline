pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One sampler shared by every bar surface (one per monitor), so several bars
// cost the same as one. CPU, memory, CPU temperature and AMD GPUs are plain
// file reads from /proc and /sys — no processes. NVIDIA is a single
// long-lived nvidia-smi that prints a line per interval, instead of spawning
// one per tick.
Singleton {
  id: root

  property int interval: 2000
  // "auto" | "nvidia" | "amd" | "off". Auto skips the GPU on machines with a
  // battery: polling a hybrid laptop's dGPU keeps it from runtime-suspending.
  property string gpuMode: "auto"

  property int cpu: -1
  property int cpuTemp: -1
  property int mem: -1
  property int gpu: -1
  property int gpuTemp: -1
  property bool gpuAvailable: false

  property bool _started: false
  property var _lastCpu: null
  property string _cpuTempPath: ""
  property string _amdBusyPath: ""
  property string _amdTempPath: ""
  property bool _nvidia: false
  property bool _nvidiaSeen: false

  function start(interval, gpuMode) {
    if (_started) return
    _started = true
    root.interval = Math.max(500, interval)
    root.gpuMode = gpuMode
    probe.running = true
  }

  function _parseStat(raw) {
    var f = raw.substring(0, raw.indexOf("\n")).split(/\s+/)
    var total = 0
    for (var i = 1; i <= 8 && i < f.length; i++) total += Number(f[i])
    var idle = Number(f[4]) + Number(f[5])
    if (_lastCpu) {
      var dt = total - _lastCpu.total
      if (dt > 0) cpu = Math.round(100 * (1 - (idle - _lastCpu.idle) / dt))
    }
    _lastCpu = { total: total, idle: idle }
  }

  function _parseMeminfo(raw) {
    var total = Number((raw.match(/MemTotal:\s+(\d+)/) || [])[1])
    var avail = Number((raw.match(/MemAvailable:\s+(\d+)/) || [])[1])
    if (total > 0) mem = Math.round(100 * (total - avail) / total)
  }

  function _applyProbe(out) {
    var lines = out.split("\n")
    var found = {}
    for (var i = 0; i < lines.length; i++) {
      var sp = lines[i].indexOf(" ")
      if (sp > 0) found[lines[i].substring(0, sp)] = lines[i].substring(sp + 1)
    }
    _cpuTempPath = found.cpu || ""

    var mode = gpuMode
    if (mode === "auto") mode = found.battery ? "off" : (found.nvidia ? "nvidia" : "amd")
    if (mode === "nvidia" && found.nvidia) _nvidia = true
    else if (mode === "amd" && found.amdbusy) {
      _amdBusyPath = found.amdbusy
      _amdTempPath = found.amdtemp || ""
      gpuAvailable = true
    }
  }

  // hwmon and DRM indices shuffle between boots, so look the sensors up by
  // driver name once. temp1 is Tctl on k10temp/zenpower, Package on coretemp
  // and the edge sensor on amdgpu.
  Process {
    id: probe
    command: ["sh", "-c",
      "for h in /sys/class/hwmon/hwmon*; do case $(cat $h/name 2>/dev/null) in k10temp|zenpower|coretemp) echo cpu $h/temp1_input; break;; esac; done;" +
      "for d in /sys/class/drm/card*/device; do [ -r $d/gpu_busy_percent ] || continue; echo amdbusy $d/gpu_busy_percent;" +
      " for h in $d/hwmon/hwmon*; do [ -r $h/temp1_input ] && echo amdtemp $h/temp1_input; break; done; break; done;" +
      "command -v nvidia-smi >/dev/null && echo nvidia 1;" +
      "for b in /sys/class/power_supply/BAT*; do [ -e $b ] && echo battery 1; break; done; true"]
    stdout: StdioCollector { onStreamFinished: root._applyProbe(text) }
  }

  Timer {
    interval: root.interval
    running: root._started
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      statFile.reload()
      memFile.reload()
      if (root._cpuTempPath !== "") cpuTempFile.reload()
      if (root._amdBusyPath !== "") amdBusyFile.reload()
      if (root._amdTempPath !== "") amdTempFile.reload()
    }
  }

  FileView { id: statFile; path: "/proc/stat"; onLoaded: root._parseStat(text()) }
  FileView { id: memFile; path: "/proc/meminfo"; onLoaded: root._parseMeminfo(text()) }
  FileView { id: cpuTempFile; path: root._cpuTempPath; onLoaded: root.cpuTemp = Math.round(Number(text()) / 1000) }
  FileView { id: amdBusyFile; path: root._amdBusyPath; onLoaded: root.gpu = Number(text()) }
  FileView { id: amdTempFile; path: root._amdTempPath; onLoaded: root.gpuTemp = Math.round(Number(text()) / 1000) }

  Process {
    id: gpuProc
    running: root._nvidia
    command: ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu",
              "--format=csv,noheader,nounits", "--id=0", "-lms", String(root.interval)]
    stdout: SplitParser {
      onRead: function(line) {
        // --id=0: one line per tick even on multi-GPU machines.
        var f = line.split(",")
        if (f.length < 2 || isNaN(Number(f[0]))) return
        root.gpu = Number(f[0])
        root.gpuTemp = Number(f[1])
        root.gpuAvailable = true
        root._nvidiaSeen = true
      }
    }
    // A driver update or GPU reset kills nvidia-smi; retry only if it ever
    // worked, so a machine without a usable NVIDIA GPU doesn't loop.
    onExited: if (root._nvidiaSeen) gpuRestart.start()
  }

  Timer { id: gpuRestart; interval: 30000; onTriggered: gpuProc.running = true }
}
