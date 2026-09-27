"use strict"

const assert = require("assert")
const Model = require("../Model.js")

function entry(partial) {
  return Object.assign({
    id: "0001",
    active: true,
    label: "Example",
    file: "",
    path: "",
    current: false,
    next: false
  }, partial)
}

assert.strictEqual(Model.normalizeId("000a"), "000A")
assert.strictEqual(Model.normalizeId(" 0005 "), "0005")
assert.strictEqual(Model.normalizeId("00015"), "")
assert.strictEqual(Model.normalizeId("0001;reboot"), "")
assert.strictEqual(Model.normalizeId("next"), "")

assert.strictEqual(Model.plain("Windows <img>"), "Windows img")

assert.strictEqual(Model.iconFor(entry({ label: "Windows Boot Manager" })), "󰖳")
assert.strictEqual(Model.iconFor(entry({ file: "\\EFI\\MICROSOFT\\BOOT\\BOOTMGFW.EFI", label: "OS" })), "󰖳")
assert.strictEqual(Model.iconFor(entry({ label: "Limine" })), "󰋊")

const firmware = {
  entries: [
    entry({ id: "0005", label: "Limine", current: true }),
    entry({ id: "0001", label: "Windows Boot Manager" }),
    entry({ id: "0007", label: "Hidden", active: false })
  ]
}
assert.deepStrictEqual(Model.visibleEntries(firmware, false).map((item) => item.id), ["0005", "0001"])
assert.deepStrictEqual(Model.visibleEntries(firmware, true).map((item) => item.id), ["0005", "0001", "0007"])
assert.deepStrictEqual(
  Model.visibleEntries(firmware, true, ["0001", "nope", "0001"]).map((item) => item.id),
  ["0005", "0007"]
)
assert.deepStrictEqual(Model.hiddenEntries(firmware, ["0001", "9999", "0007"]).map((item) => item.id), ["0001", "0007", "9999"])
assert.strictEqual(Model.hiddenEntries(firmware, ["9999"])[0].missing, true)
assert.strictEqual(Model.entryById(firmware.entries, "0001").label, "Windows Boot Manager")
assert.strictEqual(Model.entryById(firmware.entries, "nope"), null)
assert.strictEqual(Model.indexOfCurrent(Model.visibleEntries(firmware, false)), 0)
assert.strictEqual(Model.moveIndex(0, -1, 3), 0)
assert.strictEqual(Model.moveIndex(2, 1, 3), 2)
assert.strictEqual(Model.moveIndex(1, 1, 3), 2)

assert.strictEqual(
  Model.rowDetail(entry({ current: true, file: "\\EFI\\LIMINE\\LIMINE_X64.EFI" })),
  "This boot  ·  \\EFI\\LIMINE\\LIMINE_X64.EFI"
)
assert.strictEqual(Model.rowDetail(entry({ active: false, next: true })), "Next boot  ·  Inactive")
assert.strictEqual(
  Model.rowDetail(entry({ id: "0001", label: "Windows Boot Manager", current: true }), { "0001": "Work" }),
  "This boot  ·  Windows Boot Manager"
)
assert.strictEqual(
  Model.rowDetail({ id: "9999", label: "", missing: true, active: false }),
  "Not in the firmware menu"
)

assert.strictEqual(Model.cleanName("  Work\n<box>  "), "Workbox")
assert.strictEqual(Model.cleanName("x".repeat(90)).length, 80)
assert.strictEqual(Model.displayLabel(entry({ id: "0001", label: "Windows Boot Manager" }), { "0001": "Work" }), "Work")
assert.strictEqual(Model.displayLabel(entry({ id: "0001", label: "Windows Boot Manager" }), {}), "Windows Boot Manager")
assert.strictEqual(Model.displayLabel({ id: "9999", label: "", missing: true }, {}), "9999")
assert.strictEqual(Model.storedName("Windows Boot Manager", "  Windows Boot Manager "), "")
assert.strictEqual(Model.storedName("Windows Boot Manager", "Work"), "Work")
assert.strictEqual(Model.storedName("", "   "), "")

assert.deepStrictEqual(Model.sanitizeNames({ "0001": "Work", "bad": "Nope", "0002": 4, "0003": "  " }), { "0001": "Work" })
assert.deepStrictEqual(Model.sanitizeHidden(["0001", "0001", "zz", "000A"]), ["0001", "000A"])
assert.deepStrictEqual(Model.withName({ "0001": "Work" }, "0001", ""), {})
assert.deepStrictEqual(Model.withName({}, "0001", "Work"), { "0001": "Work" })
assert.deepStrictEqual(Model.withName({}, "next", "Work"), {})
assert.deepStrictEqual(Model.withHidden(["0001"], "0005", true), ["0001", "0005"])
assert.deepStrictEqual(Model.withHidden(["0001", "0005"], "0001", false), ["0005"])
assert.deepStrictEqual(Model.withHidden(["0001"], "0001", true), ["0001"])

const many = {}
for (let n = 0; n < 64; n++) many[n.toString(16).toUpperCase().padStart(4, "0")] = "Name"
assert.strictEqual(Object.keys(Model.withName(many, "0040", "Extra")).length, 64)
assert.strictEqual(Model.withName(many, "0000", "Renamed")["0000"], "Renamed")
assert.strictEqual(Model.withHidden(Object.keys(many), "0040", true).length, 64)

assert.strictEqual(Model.departingLine(3, "Windows Boot Manager"), "Setting next boot to Windows Boot Manager")
assert.strictEqual(Model.departingLine(2, "Windows Boot Manager"), "The saved boot order stays as it is")
assert.strictEqual(Model.departingLine(1, "Windows Boot Manager"), "Rebooting into Windows Boot Manager")
assert.strictEqual(Model.departingLine(0, "Windows Boot Manager"), "Rebooting into Windows Boot Manager")
assert.strictEqual(Model.departingLine(3, "  "), "Setting next boot to this operating system")

let step = { countdown: Model.countdownStart(), commit: false }
const seen = [step.countdown]
while (!step.commit) {
  step = Model.stepCountdown(step.countdown)
  seen.push(step.countdown)
}
assert.deepStrictEqual(seen, [3, 2, 1, 0])
assert.strictEqual(step.commit, true)
assert.ok(Model.holdMs() >= 1000)
assert.ok(Model.typeMs() > 0)

const payload = Model.parsePayload('{"ok":true,"bootOrder":["0005"],"entries":[{"id":"0005"}]}')
assert.strictEqual(payload.ok, true)
assert.strictEqual(payload.entries[0].id, "0005")
assert.strictEqual(Model.parsePayload('{"ok":false,"error":"nope"}').error, "nope")
assert.strictEqual(Model.parsePayload("").ok, false)
assert.strictEqual(Model.parsePayload("{").ok, false)

console.log("model.test.js ok")
