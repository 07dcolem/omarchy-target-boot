"use strict"

const assert = require("assert")
const Edit = require("../PlainEdit.js")

function insert(text, cursor, anchor, incoming, cap) {
  return Edit.insert(text, cursor, anchor, incoming, cap)
}

const mid = insert("ab", 1, 1, "XY", 32)
assert.strictEqual(mid.text, "aXYb")
assert.strictEqual(mid.cursor, 3)
assert.strictEqual(mid.anchor, 3)

const capped = insert("", 0, 0, "abcdefghijklmnopqrstuvwxyz0123456789", 32)
assert.strictEqual(capped.text.length, 32)
assert.strictEqual(capped.text, "abcdefghijklmnopqrstuvwxyz012345")

const controls = insert("a", 1, 1, "b\n\u0000c\u007fd", 32)
assert.strictEqual(controls.text, "abcd")

const replaced = insert("hello", 1, 4, "i", 32)
assert.strictEqual(replaced.text, "hio")
assert.strictEqual(replaced.cursor, 2)

const over = insert("abcd", 0, 2, "zzzz", 4)
assert.strictEqual(over.text, "zzcd")
assert.strictEqual(over.text.length, 4)

const nameCap = insert("", 0, 0, "n".repeat(120), 80)
assert.strictEqual(nameCap.text.length, 80)

const bs = Edit.backspace("ab", 2, 2)
assert.strictEqual(bs.text, "a")
assert.strictEqual(bs.cursor, 1)
const bsSel = Edit.backspace("hello", 1, 4)
assert.strictEqual(bsSel.text, "ho")
assert.strictEqual(bsSel.cursor, 1)
const bs0 = Edit.backspace("a", 0, 0)
assert.strictEqual(bs0.text, "a")
assert.strictEqual(bs0.cursor, 0)

const del = Edit.deleteForward("ab", 0, 0)
assert.strictEqual(del.text, "b")
assert.strictEqual(del.cursor, 0)
const delSel = Edit.deleteForward("hello", 4, 1)
assert.strictEqual(delSel.text, "ho")

const left = Edit.move("abcd", 2, 2, -1, false)
assert.strictEqual(left.cursor, 1)
assert.strictEqual(left.anchor, 1)
const extend = Edit.move("abcd", 2, 2, 1, true)
assert.strictEqual(extend.cursor, 3)
assert.strictEqual(extend.anchor, 2)
const clamped = Edit.move("ab", 0, 0, -5, false)
assert.strictEqual(clamped.cursor, 0)

const start = Edit.home("abcd", 3, true)
assert.strictEqual(start.cursor, 0)
assert.strictEqual(start.anchor, 3)
const finish = Edit.end("abcd", 0, false)
assert.strictEqual(finish.cursor, 4)
assert.strictEqual(finish.anchor, 4)

assert.strictEqual(Edit.usable("\n"), false)
assert.strictEqual(Edit.usable("#"), true)
assert.strictEqual(Edit.usable("<"), true)
