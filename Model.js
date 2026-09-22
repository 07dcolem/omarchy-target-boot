// Pure helpers for the reboot-into panel. No QML and no processes, so the
// countdown copy and the firmware payload can be tested on their own.

function holdMs() {
  return 1500
}

function typeMs() {
  return 16
}

function countdownStart() {
  return 3
}

function normalizeId(id) {
  var text = String(id || "").replace(/^\s+|\s+$/g, "").toUpperCase()
  return /^[0-9A-F]{4}$/.test(text) ? text : ""
}

function plain(text) {
  return String(text || "").replace(/[<>]/g, "")
}

function iconFor(entry) {
  var label = String(entry && entry.label || "")
  var file = String(entry && entry.file || "")
  var path = String(entry && entry.path || "")
  var blob = (label + " " + file + " " + path).toLowerCase()
  if (blob.indexOf("windows") !== -1 || blob.indexOf("microsoft") !== -1 || blob.indexOf("bootmgfw") !== -1)
    return "󰖳"
  return "󰋊"
}

function visibleEntries(firmware, showInactive) {
  var entries = firmware && Array.isArray(firmware.entries) ? firmware.entries : []
  if (showInactive) return entries.slice()
  var out = []
  for (var i = 0; i < entries.length; i++) {
    if (entries[i] && entries[i].active === true) out.push(entries[i])
  }
  return out
}

function entryById(entries, id) {
  var want = normalizeId(id)
  var list = Array.isArray(entries) ? entries : []
  if (!want) return null
  for (var i = 0; i < list.length; i++) {
    if (list[i] && normalizeId(list[i].id) === want) return list[i]
  }
  return null
}

function indexOfCurrent(entries) {
  var list = Array.isArray(entries) ? entries : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].current === true) return i
  }
  return -1
}

function moveIndex(index, delta, length) {
  if (!(length > 0)) return 0
  var next = Number(index) + Number(delta)
  if (next < 0) return 0
  if (next >= length) return length - 1
  return next
}

function rowDetail(entry) {
  if (!entry) return ""
  var bits = []
  if (entry.current === true) bits.push("This boot")
  if (entry.next === true) bits.push("Next boot")
  if (entry.active !== true) bits.push("Inactive")
  if (entry.file) bits.push(String(entry.file))
  return bits.join("  ·  ")
}

// Three beats, one per second-and-a-half of the hold. The last beat stays
// on screen while the reboot itself starts.
function departingLine(countdown, label) {
  var name = String(label || "").replace(/^\s+|\s+$/g, "")
  if (!name) name = "this operating system"
  var step = Number(countdown)
  if (step >= 3) return "Setting next boot to " + name
  if (step === 2) return "The saved boot order stays as it is"
  return "Rebooting into " + name
}

// 3 → 2 → 1, and the step away from 1 is the commit. The hold between
// steps is what the panel waits before it writes BootNext.
function stepCountdown(countdown) {
  var current = Number(countdown)
  if (!(current >= 2)) return { countdown: 0, commit: true }
  return { countdown: current - 1, commit: false }
}

function parsePayload(raw) {
  var text = String(raw || "").replace(/^\s+|\s+$/g, "")
  if (!text) return { ok: false, error: "No response from the helper", entries: [] }
  try {
    var data = JSON.parse(text)
    if (!data || typeof data !== "object")
      return { ok: false, error: "Could not read the helper response", entries: [] }
    if (data.ok !== true)
      return { ok: false, error: data.error || "Could not set next boot", entries: [] }
    if (!Array.isArray(data.entries)) data.entries = []
    return data
  } catch (e) {
    return { ok: false, error: "Could not read the helper response", entries: [] }
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    holdMs: holdMs,
    typeMs: typeMs,
    countdownStart: countdownStart,
    normalizeId: normalizeId,
    plain: plain,
    iconFor: iconFor,
    visibleEntries: visibleEntries,
    entryById: entryById,
    indexOfCurrent: indexOfCurrent,
    moveIndex: moveIndex,
    rowDetail: rowDetail,
    departingLine: departingLine,
    stepCountdown: stepCountdown,
    parsePayload: parsePayload
  }
}
