// Portable checks for qml/Model.js. Run with: node --test tests/
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import vm from "node:vm"

// QML's `.pragma library` line is not JavaScript; drop it and load the rest as CommonJS.
const source = readFileSync(new URL("../qml/Model.js", import.meta.url), "utf8").replace(/^\.pragma library\s*$/m, "")
const sandbox = { module: { exports: {} } }
vm.runInNewContext(source, sandbox)
const M = sandbox.module.exports

const row = (key, text = key) => M.toRow({ key, role: "ai", name: "Ava", text, segments: [{ kind: "plain", text }], ts: 1 })

function apply(rows, ops) {
  const out = rows.slice()
  for (const o of ops) {
    if (o.op === "remove") out.splice(o.index, o.count)
    else if (o.op === "insert") out.splice(o.index, 0, ...o.rows)
    else if (o.op === "set") out[o.index] = o.row
  }
  return out
}

test("richText escapes markup and styles roleplay", () => {
  const html = M.richText(
    [
      { kind: "action", text: "waves <b>" },
      { kind: "plain", text: " & says " },
      { kind: "quote", text: '"hi"\nthere' },
      { kind: "bold", text: "!" },
    ],
    { action: { r: 0.5, g: 0.5, b: 0.5 }, quote: "#ff8800" },
  )
  assert.ok(html.includes("<i><span style=\"color:#808080\">waves &lt;b&gt;</span></i>"))
  assert.ok(html.includes(" &amp; says "))
  assert.ok(html.includes('<span style="color:#ff8800">&quot;hi&quot;<br>there</span>'))
  assert.ok(html.includes("<b>!</b>"))
  assert.ok(!/<img|<a /i.test(M.richText([{ kind: "plain", text: '<img src="x"><a href="y">' }], { action: "#000000", quote: "#000000" })))
})

test("cssColor drops alpha and rejects odd strings", () => {
  assert.equal(M.cssColor({ r: 1, g: 0, b: 0.5, a: 0.2 }), "#ff0080")
  assert.equal(M.cssColor("#a1b2c3"), "#a1b2c3")
  assert.equal(M.cssColor("red;background:url(x)"), "#ffffff")
})

test("toRow keeps only https image URLs", () => {
  const r = M.toRow({ key: "k", role: "ai", text: "x", images: ["https://cdn.example/a.png", "http://x/b.png", "javascript:alert(1)", 'https://x/"onerror'] })
  assert.equal(r.images, "https://cdn.example/a.png")
  assert.equal(M.isWebUrl("http://127.0.0.1:8787/mock/selfie.png"), true)
  assert.equal(M.isWebUrl("http://127.0.0.1.evil.example/x.png"), false)
  assert.equal(M.isWebUrl("http://example.com/x.png"), false)
})

test("syncPlan appends a new tail without touching the rest", () => {
  const a = [row("1"), row("2")]
  const b = [row("1"), row("2"), row("3")]
  const ops = M.syncPlan(a, b)
  assert.deepEqual(JSON.parse(JSON.stringify(ops)), [{ op: "insert", index: 2, rows: [JSON.parse(JSON.stringify(b[2]))] }])
  assert.deepEqual(apply(a, ops).map((r) => r.key), ["1", "2", "3"])
})

test("syncPlan handles a sliding window, edits, local rows replaced, and older history", () => {
  const cases = [
    [[row("1"), row("2"), row("3")], [row("2"), row("3"), row("4")]],
    [[row("1"), row("2")], [row("1"), row("2", "edited")]],
    [[row("1"), row("local:a"), row("local:b")], [row("1"), row("m2"), row("m3")]],
    [[row("3"), row("4")], [row("1"), row("2"), row("3"), row("4")]],
    [[row("1")], []],
    [[], [row("1"), row("2")]],
    [[row("a"), row("b")], [row("x"), row("y")]],
  ]
  for (const [from, to] of cases) {
    const result = apply(from, M.syncPlan(from, to))
    assert.deepEqual(result.map((r) => r.key + ":" + r.text), to.map((r) => r.key + ":" + r.text))
  }
  // Sliding forward is one removal at the front and one insert at the end, not a rebuild.
  const slide = M.syncPlan([row("1"), row("2"), row("3")], [row("2"), row("3"), row("4")])
  assert.equal(slide.map((o) => o.op).join(","), "remove,insert")
})

test("activityLabel and rateWaitSeconds", () => {
  assert.equal(M.activityLabel({ kind: "streaming", name: "Ava" }), "Ava is typing…")
  assert.equal(M.activityLabel({ kind: "idle" }), "")
  assert.equal(M.rateWaitSeconds({ queued: 1, waitMs: 5000, at: 1000 }, 2500), 4)
  assert.equal(M.rateWaitSeconds({ queued: 0, waitMs: 5000, at: 1000 }, 1000), 0)
})

test("findConversation by key, name and unique prefix", () => {
  const list = [
    { key: "kin:a", id: "a", name: "Ava" },
    { key: "kin:b", id: "b", name: "Avery" },
    { key: "group:g", id: "g", name: "Friends" },
  ]
  assert.equal(M.findConversation(list, "kin:b").name, "Avery")
  assert.equal(M.findConversation(list, "ava").key, "kin:a")
  assert.equal(M.findConversation(list, "fr").key, "group:g")
  assert.equal(M.findConversation(list, "Av"), null)
})

test("normalizeId matches kindroid-tui", () => {
  assert.equal(M.normalizeId(" abc "), "abc")
  assert.equal(M.normalizeId("https://kindroid.ai/v2/chat/group/G123/?x=1"), "G123")
})
