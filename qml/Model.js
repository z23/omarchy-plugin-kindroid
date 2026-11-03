.pragma library
// Pure helpers shared by the service and the panel. No QML types in here, so the
// portable tests in tests/ can load this file with plain Node.

// The helper protocol this plugin speaks. kindroid-tui sends its own in the
// `ready` event; anything else is refused rather than half-understood.
var PROTOCOL = 1

// --- rich text --------------------------------------------------------------

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
    .replace(/\r?\n/g, "<br>")
}

// A colour as #rrggbb. QML colours stringify as #aarrggbb when they carry alpha,
// which Qt's rich text does not read.
function cssColor(c) {
  if (typeof c === "string") return /^#[0-9a-fA-F]{6}$/.test(c) ? c : "#ffffff"
  function hex(v) {
    var n = Math.max(0, Math.min(255, Math.round(Number(v) * 255)))
    return (n < 16 ? "0" : "") + n.toString(16)
  }
  return "#" + hex(c.r) + hex(c.g) + hex(c.b)
}

// Kindroid roleplay text as Qt rich text: *actions* in italics and a softer
// colour, "dialogue" in the accent colour, **bold** in bold. Every piece of text
// is escaped, so nothing a message contains is ever read as markup.
function richText(segments, colors) {
  var action = cssColor(colors.action)
  var quote = cssColor(colors.quote)
  var out = ""
  for (var i = 0; i < segments.length; i++) {
    var seg = segments[i] || {}
    var t = escapeHtml(seg.text || "")
    if (seg.kind === "action") out += '<i><span style="color:' + action + '">' + t + "</span></i>"
    else if (seg.kind === "quote") out += '<span style="color:' + quote + '">' + t + "</span>"
    else if (seg.kind === "bold") out += "<b>" + t + "</b>"
    else out += t
  }
  return '<span style="white-space:pre-wrap">' + out + "</span>"
}

// --- messages ---------------------------------------------------------------

// A wire message as a flat ListModel row. ListModel turns nested arrays into
// sub-models, so lists travel as strings.
function toRow(m) {
  var row = {
    key: String(m.key),
    role: m.role === "user" ? "user" : "ai",
    name: String(m.name || ""),
    text: String(m.text || ""),
    segs: JSON.stringify(m.segments || []),
    ts: Number(m.ts) || 0,
    images: (m.images || []).filter(isWebUrl).join("\n"),
    notes: (m.notes || []).join("\n"),
    failed: m.failed ? String(m.failed) : "",
    notSent: !!m.notSent,
    local: !!m.local
  }
  row.sig = signature(row)
  return row
}

function signature(row) {
  return [row.role, row.name, row.text, row.images, row.notes, row.failed, row.notSent, row.local, row.ts].join("\u0001")
}

// https anywhere, or plain http to this machine (the mock API in development).
function isWebUrl(url) {
  if (typeof url !== "string" || /[\s"'<>]/.test(url)) return false
  return /^https:\/\/[^/]/i.test(url) || /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?\//i.test(url)
}

// The fewest ListModel operations that turn `oldRows` into `newRows`, so the list
// keeps its delegates (and its scroll position) as messages stream in. Handles
// the cases the helper actually produces: a window that slides forward, older
// history loaded at the front, edits in place, and a changed or new tail.
//
// Returns [{op: "remove"|"insert"|"set", index, count?, rows?, row?}], to be
// applied in order.
function syncPlan(oldRows, newRows) {
  var ops = []
  var cur = oldRows.slice()

  if (cur.length && newRows.length) {
    // Window slid forward: the old head is gone.
    var headInOld = indexOfKey(cur, newRows[0].key)
    if (headInOld > 0) {
      ops.push({ op: "remove", index: 0, count: headInOld })
      cur.splice(0, headInOld)
    } else if (headInOld < 0) {
      // Older history arrived at the front.
      var oldHeadInNew = indexOfKey(newRows, cur[0].key)
      if (oldHeadInNew > 0) {
        var front = newRows.slice(0, oldHeadInNew)
        ops.push({ op: "insert", index: 0, rows: front })
        cur = front.concat(cur)
      }
    }
  }

  var i = 0
  while (i < cur.length && i < newRows.length && cur[i].key === newRows[i].key) {
    if (cur[i].sig !== newRows[i].sig) ops.push({ op: "set", index: i, row: newRows[i] })
    i++
  }
  if (i < cur.length) ops.push({ op: "remove", index: i, count: cur.length - i })
  if (i < newRows.length) ops.push({ op: "insert", index: i, rows: newRows.slice(i) })
  return ops
}

function indexOfKey(rows, key) {
  for (var i = 0; i < rows.length; i++) if (rows[i].key === key) return i
  return -1
}

// --- status lines -----------------------------------------------------------

function activityLabel(activity) {
  var kind = activity && activity.kind ? activity.kind : "idle"
  switch (kind) {
  case "syncing": return "Syncing…"
  case "sending": return "Sending…"
  case "turn": return "Waiting for the next speaker…"
  case "streaming": return (activity.name || "They") + " is typing…"
  case "rewinding": return "Undoing…"
  case "breaking": return "Starting a chat break…"
  case "updating": return "Updating the scene…"
  default: return ""
  }
}

// Seconds the rate limiter still holds requests back, from a `limits` event.
function rateWaitSeconds(limits, nowMs) {
  if (!limits || !(limits.queued > 0) || !(limits.waitMs > 0)) return 0
  var left = limits.waitMs - Math.max(0, nowMs - (limits.at || nowMs))
  return left > 0 ? Math.ceil(left / 1000) : 0
}

// "today", "yesterday" or "older", for picking a time format.
function dayBucket(ms, nowMs) {
  if (!ms) return "older"
  var d = new Date(ms)
  var now = new Date(nowMs)
  if (d.toDateString() === now.toDateString()) return "today"
  var y = new Date(nowMs - 86400000)
  if (d.toDateString() === y.toDateString()) return "yesterday"
  return "older"
}

// --- conversations ----------------------------------------------------------

// Find a conversation by key, exact name, or a unique case-insensitive name prefix.
function findConversation(list, query) {
  var q = String(query || "").trim()
  if (!q) return null
  var lower = q.toLowerCase()
  var i
  for (i = 0; i < list.length; i++) if (list[i].key === q || list[i].id === q) return list[i]
  for (i = 0; i < list.length; i++) if (String(list[i].name).toLowerCase() === lower) return list[i]
  var hits = []
  for (i = 0; i < list.length; i++) if (String(list[i].name).toLowerCase().indexOf(lower) === 0) hits.push(list[i])
  return hits.length === 1 ? hits[0] : null
}

// Accept a bare ID or a pasted Kindroid web URL; mirrors normalizeId in kindroid-tui.
function normalizeId(raw) {
  var t = String(raw || "").trim()
  if (!/^https?:\/\//i.test(t) && t.indexOf("/") < 0) return t
  var path = t.replace(/[?#].*$/, "").replace(/\/+$/, "")
  return path.slice(path.lastIndexOf("/") + 1)
}

if (typeof module !== "undefined") {
  module.exports = {
    PROTOCOL: PROTOCOL,
    escapeHtml: escapeHtml,
    cssColor: cssColor,
    richText: richText,
    toRow: toRow,
    isWebUrl: isWebUrl,
    syncPlan: syncPlan,
    activityLabel: activityLabel,
    rateWaitSeconds: rateWaitSeconds,
    dayBucket: dayBucket,
    findConversation: findConversation,
    normalizeId: normalizeId
  }
}
