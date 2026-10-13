// Pure helpers for the reboot-into panel. No QML and no processes, so the
// countdown copy and the firmware payload can be tested on their own.

function holdMs() {
  return 1500
}

function typeMs() {
  return 16
}

function flickMs() {
  return 90
}

function poofMs() {
  return 400
}

function countdownStart() {
  return 4
}

function poofText() {
  return "˚ ✦ poof ✦ ˚"
}

function normalizeId(id) {
  var text = String(id || "").replace(/^\s+|\s+$/g, "").toUpperCase()
  return /^[0-9A-F]{4}$/.test(text) ? text : ""
}

function plain(text) {
  return String(text || "").replace(/[<>]/g, "")
}

// Display names are short labels typed in the panel. Cap the read and the
// stored result so a huge shell.json value cannot land in the row model.
function cleanName(text) {
  var value = String(text || "")
  if (value.length > 200) value = value.slice(0, 200)
  value = value.replace(/[\u0000-\u001F\u007F]/g, "").replace(/[<>]/g, "").replace(/^\s+|\s+$/g, "")
  if (value.length > 80) value = value.slice(0, 80).replace(/\s+$/g, "")
  return value
}

function firmwareLabel(entry) {
  return String(entry && entry.label || "").replace(/^\s+|\s+$/g, "")
}

function keyCount(map) {
  var count = 0
  for (var key in map) count++
  return count
}

function copyWithout(map, drop) {
  var out = {}
  for (var key in map) {
    if (key !== drop) out[key] = map[key]
  }
  return out
}

function asList(raw) {
  if (Array.isArray(raw)) return raw
  if (raw && typeof raw === "object" && typeof raw.length === "number") {
    var out = []
    var n = raw.length > 256 ? 256 : raw.length
    for (var i = 0; i < n; i++) out.push(raw[i])
    return out
  }
  return []
}

function iconFor(entry, names) {
  var file = String(entry && entry.file || "")
  var path = String(entry && entry.path || "")
  var blob = (displayLabel(entry, names || {}) + " " + firmwareLabel(entry) + " " + file + " " + path).toLowerCase()
  if (blob.indexOf("windows") !== -1 || blob.indexOf("microsoft") !== -1 || blob.indexOf("bootmgfw") !== -1)
    return "󰖳"
  if (blob.indexOf("omarchy") !== -1) return omarchyIcon()
  return "󰋊"
}

function sanitizeNames(raw) {
  var out = {}
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
  var seen = 0
  var kept = 0
  for (var key in raw) {
    seen++
    if (seen > 256 || kept >= 64) break
    var id = normalizeId(key)
    if (!id || out[id]) continue
    if (typeof raw[key] !== "string") continue
    var name = cleanName(raw[key])
    if (!name) continue
    out[id] = name
    kept++
  }
  return out
}

function sanitizeHidden(raw) {
  var out = []
  var list = asList(raw)
  var seen = {}
  var n = list.length > 256 ? 256 : list.length
  for (var i = 0; i < n && out.length < 64; i++) {
    var id = normalizeId(list[i])
    if (!id || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

function displayLabel(entry, names) {
  var id = normalizeId(entry && entry.id)
  var map = names && typeof names === "object" && !Array.isArray(names) ? names : {}
  var mapped = id && typeof map[id] === "string" ? cleanName(map[id]) : ""
  if (mapped) return mapped
  var label = firmwareLabel(entry)
  if (label) return label
  return id || "Operating system"
}

// Blank, or a name equal to the firmware label, clears the remap.
function storedName(firmwareText, typed) {
  var cleaned = cleanName(typed)
  var firmware = cleanName(firmwareText)
  if (!cleaned || (firmware && cleaned === firmware)) return ""
  return cleaned
}

function withName(names, id, name) {
  var next = sanitizeNames(names)
  var clean = normalizeId(id)
  if (!clean) return next
  var label = cleanName(name)
  if (!label) return copyWithout(next, clean)
  if (next[clean] === undefined && keyCount(next) >= 64) return next
  next[clean] = label
  return next
}

function withHidden(hidden, id, hide) {
  var next = sanitizeHidden(hidden)
  var clean = normalizeId(id)
  if (!clean) return next
  var idx = next.indexOf(clean)
  if (hide) {
    if (idx === -1 && next.length < 64) next.push(clean)
    return next
  }
  if (idx !== -1) next.splice(idx, 1)
  return next
}

function visibleEntries(firmware, showInactive, hiddenIds) {
  var entries = firmware && Array.isArray(firmware.entries) ? firmware.entries : []
  var hiddenList = sanitizeHidden(hiddenIds)
  var hidden = {}
  for (var h = 0; h < hiddenList.length; h++) hidden[hiddenList[h]] = true
  var out = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (!entry) continue
    if (!showInactive && entry.active !== true) continue
    var id = normalizeId(entry.id)
    if (id && hidden[id]) continue
    out.push(entry)
  }
  return out
}

function hiddenEntries(firmware, hiddenIds) {
  var wanted = sanitizeHidden(hiddenIds)
  var want = {}
  for (var w = 0; w < wanted.length; w++) want[wanted[w]] = true
  var entries = firmware && Array.isArray(firmware.entries) ? firmware.entries : []
  var out = []
  var seen = {}
  for (var i = 0; i < entries.length; i++) {
    var id = normalizeId(entries[i] && entries[i].id)
    if (!id || !want[id] || seen[id]) continue
    seen[id] = true
    out.push(entries[i])
  }
  for (var j = 0; j < wanted.length; j++) {
    if (seen[wanted[j]]) continue
    seen[wanted[j]] = true
    out.push({
      id: wanted[j],
      label: "",
      active: false,
      current: false,
      next: false,
      missing: true
    })
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

function rowDetail(entry, names) {
  if (!entry) return ""
  var bits = []
  if (entry.current === true) bits.push("This boot")
  if (entry.next === true) bits.push("Next boot")
  if (entry.active !== true && entry.missing !== true) bits.push("Inactive")
  if (entry.file) bits.push(String(entry.file))
  var firmware = firmwareLabel(entry)
  var shown = displayLabel(entry, names)
  if (firmware && shown !== firmware) bits.push(firmware)
  if (entry.missing === true) bits.push("Not in the firmware menu")
  return bits.join("  ·  ")
}

// Four beats, one per second-and-a-half of the hold. The last beat stays
// on screen while the reboot itself starts.
function departingLine(countdown, label) {
  var name = String(label || "").replace(/^\s+|\s+$/g, "")
  if (!name) name = "this operating system"
  var step = Number(countdown)
  if (step >= 4) return "Next boot will be " + name + ", just this once"
  if (step === 3) return "Setting next boot to " + name
  if (step === 2) return "The saved boot order stays as it is"
  return "Rebooting into " + name
}

// 4 → 3 → 2 → 1, and the step away from 1 is the commit. The hold between
// steps is what the panel waits before it writes BootNext.
function stepCountdown(countdown) {
  var current = Number(countdown)
  if (!(current >= 2)) return { countdown: 0, commit: true }
  return { countdown: current - 1, commit: false }
}

// 0 is Stay here, 1 is Go now. Left and up select Stay. Right and down select Go.
// A negative axis wins when both are set. Zero movement leaves the choice.
function moveDepartChoice(choice, dx, dy) {
  if (Number(dx) < 0 || Number(dy) < 0) return 0
  if (Number(dx) > 0 || Number(dy) > 0) return 1
  return Number(choice) === 1 ? 1 : 0
}

// Numerals Go now still shows, one flick each, before the poof. The beat
// already on screen is not repeated. An empty list means poof immediately.
function rushPlan(countdown) {
  var shown = []
  var current = Number(countdown)
  var guard = 0
  while (guard < 8) {
    guard++
    var step = stepCountdown(current)
    if (step.commit) return shown
    shown.push(step.countdown)
    current = step.countdown
  }
  return shown
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

function omarchyIcon() {
  return "omarchy"
}

// The square Omarchy mark, taken from the green logo. 1 is ink.
function omarchyMarkRows() {
  return [
    "111111111111111",
    "100000010000001",
    "101111100011101",
    "101000000000101",
    "101000000000101",
    "101000000000101",
    "101000000000101",
    "111000000000101",
    "101000000000101",
    "101000000000101",
    "101000000000101",
    "101000000000101",
    "101111111111101",
    "100000010000001",
    "111111101111111"
  ]
}

function offerLine(label) {
  var name = cleanName(label) || "this operating system"
  return "This boot is " + name + ". Call it Omarchy in this menu?"
}

// The current boot, once, until the person answers or it is already Omarchy.
function offerTarget(firmware, names, seen) {
  if (seen === true) return null
  var entries = firmware && Array.isArray(firmware.entries) ? firmware.entries : []
  var current = null
  for (var i = 0; i < entries.length; i++) {
    if (entries[i] && entries[i].current === true) current = entries[i]
  }
  if (!current) return null
  var id = normalizeId(current.id)
  if (!id) return null
  if (iconFor(current, names) === omarchyIcon()) return null
  return { id: id, label: displayLabel(current, names) }
}

if (typeof module !== "undefined") {
  module.exports = {
    holdMs: holdMs,
    typeMs: typeMs,
    flickMs: flickMs,
    poofMs: poofMs,
    countdownStart: countdownStart,
    poofText: poofText,
    normalizeId: normalizeId,
    plain: plain,
    cleanName: cleanName,
    firmwareLabel: firmwareLabel,
    sanitizeNames: sanitizeNames,
    sanitizeHidden: sanitizeHidden,
    displayLabel: displayLabel,
    storedName: storedName,
    withName: withName,
    withHidden: withHidden,
    iconFor: iconFor,
    omarchyIcon: omarchyIcon,
    omarchyMarkRows: omarchyMarkRows,
    offerLine: offerLine,
    offerTarget: offerTarget,
    visibleEntries: visibleEntries,
    hiddenEntries: hiddenEntries,
    entryById: entryById,
    indexOfCurrent: indexOfCurrent,
    moveIndex: moveIndex,
    rowDetail: rowDetail,
    departingLine: departingLine,
    stepCountdown: stepCountdown,
    moveDepartChoice: moveDepartChoice,
    rushPlan: rushPlan,
    parsePayload: parsePayload
  }
}
