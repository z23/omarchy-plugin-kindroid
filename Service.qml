import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "qml/Model.js" as Model

// Owns the kindroid-tui helper (`kindroid-tui serve`) and the chat state every
// panel shows. One per shell, kept loaded across hot reloads so a reply keeps
// streaming while the bar reloads.
//
// The helper does all of the talking to Kindroid: the API key, the rate limiter,
// the daily history budget and the history cache stay in that process and in
// kindroid-tui's own files. This side only ever sees chat state. Nothing here
// reaches Kindroid on a timer; every request starts from something you did in
// the panel or over IPC.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "io.github.z23.kindroid"
  readonly property string home: Quickshell.env("HOME") || ""

  // --- helper status ---------------------------------------------------------

  // idle: not started (nothing has asked for it yet) · starting · ready ·
  // missing: no kindroid-tui found · incompatible: wrong protocol · failed: exited
  property string helperStatus: "idle"
  property string helperDetail: ""
  property string helperVersion: ""
  property var stderrTail: []

  // Optional ~/.config/omarchy/kindroid.json: {"helper": ["/path/to/kindroid-tui"],
  // "config": "/path/config.toml", "dataDir": "/path"}. For development and for
  // a kindroid-tui installed somewhere unusual.
  property var overrides: ({})

  // --- config, from the helper ------------------------------------------------

  property bool configLoaded: false
  property bool hasKey: false
  property string configPath: ""
  property var warnings: []
  property var conversations: []
  property string activeKey: ""
  readonly property var activeEntry: entryFor(activeKey)
  readonly property bool activeIsGroup: !!activeEntry && activeEntry.kind === "group"

  // --- the active conversation ----------------------------------------------

  property alias messageModel: messageModel
  property var activity: ({ kind: "idle" })
  property var draft: null
  property string error: ""
  property string notice: ""
  property var scene: null
  property bool canLoadOlder: false
  property real lastSyncedAt: 0
  readonly property bool busy: activity && activity.kind !== "idle"
  readonly property bool streaming: activity && (activity.kind === "streaming" || activity.kind === "sending" || activity.kind === "turn")

  // Every conversation's merged state, including ones not on screen. Plain JS:
  // only the properties above notify.
  property var states: ({})
  property var busyKeys: ({})
  // Conversations with a reply on its way (sending, streaming or a group turn).
  property var replyingKeys: ({})
  property var unreadKeys: ({})
  readonly property bool anyBusy: Object.keys(busyKeys).length > 0
  readonly property bool anyReplying: Object.keys(replyingKeys).length > 0
  readonly property bool anyUnread: Object.keys(unreadKeys).length > 0
  // Unsent composer text per conversation, for this shell session only.
  property var drafts: ({})

  property var limits: null
  property real now: Date.now()
  readonly property int rateWait: Model.rateWaitSeconds(limits, now)

  property int panelsOpen: 0

  ListModel { id: messageModel }

  // --- requests ---------------------------------------------------------------

  property int nextRequestId: 1
  property var pending: ({})
  property var queued: []

  function request(method, params, callback) {
    var id = nextRequestId++
    if (helperStatus === "incompatible") {
      if (callback) callback({ ok: false, error: helperDetail })
      return id
    }
    if (callback) pending[id] = callback
    var line = JSON.stringify({ id: id, method: method, params: params || {} }) + "\n"
    if (helperStatus === "ready") helper.write(line)
    else {
      queued.push(line)
      ensureRunning()
    }
    return id
  }

  function failPending(reason) {
    var callbacks = pending
    pending = ({})
    queued = []
    for (var id in callbacks) {
      try { callbacks[id]({ ok: false, error: reason }) } catch (e) {}
    }
  }

  // --- public actions (the panel and IPC call these) --------------------------

  function panelOpened() {
    panelsOpen++
    idleStop.stop()
    ensureRunning()
    if (activeKey !== "") {
      clearUnread(activeKey)
      openConversation(activeKey)
    }
  }

  function panelClosed() {
    panelsOpen = Math.max(0, panelsOpen - 1)
    if (panelsOpen === 0) idleStop.restart()
  }

  function selectConversation(key) {
    if (!entryFor(key)) return false
    if (key !== activeKey) {
      activeKey = key
      showState(key)
      request("setActive", { key: key })
    }
    clearUnread(key)
    openConversation(key)
    return true
  }

  function openConversation(key) {
    if (!hasKey || !entryFor(key)) return
    request("open", { key: key })
  }

  function send(text) {
    var body = String(text || "").trim()
    if (body === "" || activeKey === "") return false
    request("send", { key: activeKey, text: body }, reportFailure)
    return true
  }

  function stop() { if (activeKey !== "") request("stop", { key: activeKey }) }
  function regenerate() { if (activeKey !== "" && !activeIsGroup) request("regenerate", { key: activeKey }, reportFailure) }
  function continueGroup() { if (activeIsGroup) request("continue", { key: activeKey }, reportFailure) }
  function sync() { if (activeKey !== "") request("sync", { key: activeKey }, reportFailure) }
  function loadOlder() { if (activeKey !== "") request("loadOlder", { key: activeKey, count: 100 }) }
  function dismiss() {
    if (activeKey !== "") request("dismiss", { key: activeKey })
    error = ""
    notice = ""
  }
  function undoPreview(steps, callback) { request("undoPreview", { key: activeKey, steps: steps }, callback) }
  function undo(steps, callback) { request("undo", { key: activeKey, steps: steps }, callback) }
  function setScene(text, callback) { request("scene", { key: activeKey, text: text }, callback) }
  function chatBreak(greeting, wipe, callback) { request("chatBreak", { key: activeKey, greeting: greeting, wipe: !!wipe }, callback) }
  function lookup(kind, id, callback) { request("lookup", { kind: kind, id: id }, callback) }
  function addConversation(kind, id, name, callback) {
    request("add", { kind: kind, id: id, name: name }, function(res) {
      if (res.ok && res.result && res.result.key) selectConversation(res.result.key)
      if (callback) callback(res)
    })
  }
  function reload() { request("reload", {}) }

  // After a failure the helper has already exited; start it again.
  function restartHelper() {
    if (helper.running || probe.running) return
    helperStatus = "idle"
    helperDetail = ""
    ensureRunning()
  }

  function editConfig() {
    if (configPath === "") return
    Util.execArgv(["omarchy-launch-editor", configPath])
  }

  function openImage(url) {
    if (Model.isWebUrl(url)) Util.execArgv(["xdg-open", url])
  }

  function draftFor(key) { return drafts[key] || "" }
  function setDraftFor(key, text) {
    if (!key) return
    if (text) drafts[key] = text
    else delete drafts[key]
  }

  function entryFor(key) {
    for (var i = 0; i < conversations.length; i++) if (conversations[i].key === key) return conversations[i]
    return null
  }

  function togglePanel() {
    if (shell && typeof shell.toggle === "function") return shell.toggle(pluginId, "")
    return false
  }

  function summonPanel() {
    if (shell && typeof shell.summon === "function") return shell.summon(pluginId, "")
    return false
  }

  // --- helper process -----------------------------------------------------------

  function ensureRunning() {
    // An incompatible helper stays stopped until restartHelper(), after an update.
    // While one is stopping, its exit starts the next if anything is waiting.
    if (["ready", "starting", "stopping", "incompatible"].indexOf(helperStatus) >= 0) return
    helperStatus = "starting"
    helperDetail = ""
    stderrTail = []
    var custom = overrides && Array.isArray(overrides.helper) ? overrides.helper : null
    if (custom && custom.length > 0 && String(custom[0]).indexOf("/") === 0) {
      launch(custom.map(String))
      return
    }
    probe.running = true
  }

  function launch(argv) {
    var cmd = argv.concat(["serve"])
    if (overrides && typeof overrides.config === "string" && overrides.config.indexOf("/") === 0)
      cmd = cmd.concat(["--config", overrides.config])
    helper.command = cmd
    helper.environment = helperEnvironment()
    helper.running = true
    startTimeout.restart()
  }

  // Only what kindroid-tui needs to find its files (and bun, when the helper is
  // run from source). KINDROID_API_KEY passes through when the session has it.
  function helperEnvironment() {
    var env = { HOME: home }
    var pass = ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_RUNTIME_DIR", "KINDROID_API_KEY", "KINDROID_TUI_CONFIG", "KINDROID_TUI_DATA", "PATH"]
    for (var i = 0; i < pass.length; i++) {
      var v = Quickshell.env(pass[i])
      if (v) env[pass[i]] = v
    }
    if (overrides && typeof overrides.dataDir === "string" && overrides.dataDir.indexOf("/") === 0)
      env.KINDROID_TUI_DATA = overrides.dataDir
    return env
  }

  function stopHelper() {
    if (helper.running) helper.running = false
  }

  function onHelperLine(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (!msg || typeof msg !== "object") return
    if (msg.event) handleEvent(msg)
    else if (msg.id !== undefined && msg.id !== null) {
      var cb = pending[msg.id]
      if (cb) {
        delete pending[msg.id]
        try { cb(msg) } catch (e) { console.warn("kindroid: callback failed:", e) }
      }
    }
  }

  function handleEvent(msg) {
    switch (msg.event) {
    case "ready":
      if (msg.protocol !== Model.PROTOCOL) {
        helperStatus = "incompatible"
        helperDetail = "kindroid-tui " + (msg.version || "?") + " speaks protocol " + msg.protocol
          + "; this plugin needs " + Model.PROTOCOL + ". Update both to matching versions."
        failPending(helperDetail)
        stopHelper()
        return
      }
      startTimeout.stop()
      helperVersion = String(msg.version || "")
      helperStatus = "ready"
      var lines = queued
      queued = []
      for (var i = 0; i < lines.length; i++) helper.write(lines[i])
      break
    case "config":
      applyConfig(msg)
      break
    case "limits":
      limits = msg
      now = Date.now()
      break
    case "conversation":
      applyConversation(String(msg.key), msg.state || {}, msg.full === true)
      break
    }
  }

  function applyConfig(msg) {
    configLoaded = true
    hasKey = msg.hasKey === true
    configPath = String(msg.path || "")
    warnings = Array.isArray(msg.warnings) ? msg.warnings : []
    conversations = Array.isArray(msg.conversations) ? msg.conversations : []
    var keep = entryFor(activeKey) ? activeKey : (entryFor(msg.active) ? String(msg.active) : (conversations.length ? conversations[0].key : ""))
    // The helper drops conversations whose client or title changed; forget their state too.
    var known = ({})
    for (var i = 0; i < conversations.length; i++) known[conversations[i].key] = true
    for (var k in states) if (!known[k]) delete states[k]
    if (keep !== activeKey) {
      activeKey = keep
      showState(keep)
    }
    if (panelsOpen > 0 && activeKey !== "") openConversation(activeKey)
  }

  function applyConversation(key, patch, full) {
    var prev = states[key] || {}
    var next = full ? {} : Object.assign({}, prev)
    for (var f in patch) next[f] = patch[f]
    states[key] = next

    var wasBusy = prev.activity && prev.activity.kind !== "idle"
    var isBusy = next.activity && next.activity.kind !== "idle"
    if (wasBusy !== isBusy || (isBusy && !busyKeys[key])) {
      var b = Object.assign({}, busyKeys)
      if (isBusy) b[key] = true
      else delete b[key]
      busyKeys = b
    }
    // A reply ends streaming -> syncing -> idle, so remember it was replying
    // until the conversation settles.
    var replyingNow = !!next.activity && ["sending", "streaming", "turn"].indexOf(next.activity.kind) >= 0
    if (replyingNow && !replyingKeys[key]) {
      var r = Object.assign({}, replyingKeys)
      r[key] = true
      replyingKeys = r
    } else if (!isBusy && replyingKeys[key]) {
      var r2 = Object.assign({}, replyingKeys)
      delete r2[key]
      replyingKeys = r2
      if (panelsOpen === 0 || key !== activeKey) {
        var u = Object.assign({}, unreadKeys)
        u[key] = true
        unreadKeys = u
      }
    }

    if (key === activeKey) applyToScreen(patch, full)
  }

  function showState(key) {
    applyToScreen(states[key] || { messages: [], draft: null, activity: { kind: "idle" }, error: null, notice: null, scene: null, canLoadOlder: false, lastSyncedAt: null }, true)
  }

  function applyToScreen(patch, full) {
    if (full || "messages" in patch) syncMessages(patch.messages || [])
    if (full || "draft" in patch) draft = patch.draft || null
    if (full || "activity" in patch) activity = patch.activity || { kind: "idle" }
    if (full || "error" in patch) error = patch.error || ""
    if (full || "notice" in patch) notice = patch.notice || ""
    if (full || "scene" in patch) scene = patch.scene || null
    if (full || "canLoadOlder" in patch) canLoadOlder = patch.canLoadOlder === true
    if (full || "lastSyncedAt" in patch) lastSyncedAt = Number(patch.lastSyncedAt) || 0
  }

  function syncMessages(list) {
    var rows = []
    for (var i = 0; i < list.length; i++) rows.push(Model.toRow(list[i]))
    var current = []
    for (var j = 0; j < messageModel.count; j++) {
      var r = messageModel.get(j)
      current.push({ key: r.key, sig: r.sig })
    }
    var ops = Model.syncPlan(current, rows)
    for (var o = 0; o < ops.length; o++) {
      var op = ops[o]
      if (op.op === "remove") messageModel.remove(op.index, op.count)
      else if (op.op === "set") messageModel.set(op.index, op.row)
      else if (op.op === "insert") for (var n = 0; n < op.rows.length; n++) messageModel.insert(op.index + n, op.rows[n])
    }
  }

  function clearUnread(key) {
    if (!unreadKeys[key]) return
    var u = Object.assign({}, unreadKeys)
    delete u[key]
    unreadKeys = u
  }

  function reportFailure(res) {
    if (res && res.ok === false && res.error) error = String(res.error)
  }

  function onHelperExited(code) {
    busyKeys = ({})
    replyingKeys = ({})
    if (activity && activity.kind !== "idle") activity = { kind: "idle" }
    draft = null

    if (helperStatus === "stopping") {
      // Stopped on purpose (idle). If the panel came back meanwhile, start again
      // and send what queued up while this one was on its way out.
      helperStatus = "idle"
      if (destroying) return
      if (queued.length > 0 || panelsOpen > 0) {
        ensureRunning()
        if (panelsOpen > 0 && activeKey !== "") openConversation(activeKey)
      } else {
        failPending("kindroid-tui stopped")
      }
      return
    }
    startTimeout.stop()
    if (helperStatus === "ready" || helperStatus === "starting") {
      helperStatus = "failed"
      var tail = stderrTail.join(" ")
      // kindroid-tui before 0.2.0 has no serve command and rejects the argument.
      helperDetail = /serve/.test(tail) && /[Uu]nexpected|[Uu]nknown/.test(tail)
        ? "This kindroid-tui has no serve command. Update it to 0.2.0 or newer."
        : "kindroid-tui exited (" + code + ")" + (tail ? ": " + tail.slice(-300) : "")
    }
    failPending(helperDetail || "kindroid-tui stopped")
  }

  // Stop on purpose: new requests queue until the exit, instead of going to a
  // process that is on its way out.
  function stopQuietly() {
    if (!helper.running) return
    helperStatus = "stopping"
    stopHelper()
  }

  property bool destroying: false

  Process {
    id: probe
    // Find kindroid-tui: the usual install spots first, then PATH.
    command: ["/bin/sh", "-c",
      'for p in "$@"; do [ -x "$p" ] && { printf "%s\\n" "$p"; exit 0; }; done; command -v kindroid-tui || exit 1',
      "sh", root.home + "/.local/bin/kindroid-tui", "/usr/local/bin/kindroid-tui", "/usr/bin/kindroid-tui"]
    environment: ({ PATH: Quickshell.env("PATH") || "/usr/bin:/bin" })
    clearEnvironment: true
    stdout: StdioCollector { id: probeOut }
    onExited: function(code) {
      var path = probeOut.text.trim().split("\n")[0] || ""
      if (code !== 0 || path.indexOf("/") !== 0) {
        root.helperStatus = "missing"
        root.helperDetail = "kindroid-tui isn't installed. Build it (bun run build) and copy dist/kindroid-tui to ~/.local/bin."
        root.failPending(root.helperDetail)
        return
      }
      root.launch([path])
    }
  }

  Process {
    id: helper
    clearEnvironment: true
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.onHelperLine(line) } }
    stderr: SplitParser {
      onRead: function(line) {
        // The helper never writes chat text to stderr; keep a short tail for errors.
        var tail = root.stderrTail.slice(-4)
        tail.push(String(line).slice(0, 200))
        root.stderrTail = tail
      }
    }
    onExited: function(code) { root.onHelperExited(code) }
  }

  // Quickshell reports no exit for a binary that never started, so give up on a
  // helper that hasn't said hello in time.
  Timer {
    id: startTimeout
    interval: 10000
    onTriggered: {
      if (root.helperStatus !== "starting") return
      var cmd = helper.command && helper.command.length ? String(helper.command[0]) : "kindroid-tui"
      var wasRunning = helper.running
      root.helperStatus = "failed"
      root.helperDetail = wasRunning
        ? "kindroid-tui started but never answered. Is it 0.2.0 or newer?"
        : "Couldn't start " + cmd + "."
      if (wasRunning) root.stopHelper()
      root.failPending(root.helperDetail)
    }
  }

  // With every panel closed and nothing streaming, stop the helper after a while.
  // It costs nothing to restart; the cache makes reopening instant.
  Timer {
    id: idleStop
    interval: 15 * 60 * 1000
    onTriggered: {
      if (root.panelsOpen > 0) return
      if (root.anyBusy) { restart(); return }
      root.stopQuietly()
    }
  }

  // Ticks only while the rate limiter is holding a request, for the countdown.
  Timer {
    interval: 1000
    repeat: true
    running: root.limits !== null && root.limits.queued > 0 && root.limits.waitMs > 0 && root.rateWait > 0
    onTriggered: root.now = Date.now()
  }

  FileView {
    path: root.home + "/.config/omarchy/kindroid.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var v = JSON.parse(text())
        root.overrides = v && typeof v === "object" && !Array.isArray(v) ? v : ({})
      } catch (e) {
        root.overrides = ({})
      }
    }
    onLoadFailed: root.overrides = ({})
  }

  Component.onDestruction: {
    destroying = true
    stopQuietly()
  }

  ShellIpc {
    target: root.pluginId

    function toggle(): string { return root.togglePanel() ? "ok" : "unavailable" }
    function open(): string { return root.summonPanel() ? "ok" : "unavailable" }
    // Switch to a conversation by name (unique prefix is enough), key or ID, and open the panel.
    function chat(name: string): string {
      var entry = Model.findConversation(root.conversations, name)
      if (!entry) {
        if (!root.configLoaded) root.ensureRunning()
        return root.configLoaded ? "unknown conversation" : "not ready; try again"
      }
      root.selectConversation(entry.key)
      root.summonPanel()
      return "ok"
    }
    function stop(): string { root.stop(); return "ok" }
    function reload(): string { root.reload(); return "ok" }
    function status(): string {
      return JSON.stringify({
        helper: root.helperStatus,
        version: root.helperVersion,
        active: root.activeEntry ? root.activeEntry.name : null,
        activity: root.activity ? root.activity.kind : "idle",
        unread: Object.keys(root.unreadKeys).length
      })
    }
  }
}
