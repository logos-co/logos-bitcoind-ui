import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

Item {
    id: root
    objectName: "bitcoindRoot"

    readonly property var backend: (typeof logos !== "undefined" && logos) ? logos.module("bitcoind_ui") : null
    readonly property bool ready: backend !== null

    function j(raw, fallback) { try { return raw ? JSON.parse(raw) : fallback } catch (e) { return fallback } }
    readonly property var networks: ready ? j(backend.networksJson, ["mainnet", "testnet4", "signet", "regtest"])
                                          : ["mainnet", "testnet4", "signet", "regtest"]
    readonly property string net: ready ? backend.network : "signet"
    readonly property var st: ready ? j(backend.statusJson, ({})) : ({})
    readonly property bool cfgRead: ready && backend.configJson !== ""
    readonly property var cfg: cfgRead ? j(backend.configJson, ({})) : ({})
    readonly property string nodeState: ready ? backend.state : "unavailable"
    readonly property bool running: nodeState === "running"
    readonly property bool flushing: nodeState === "flushing"
    readonly property bool stopped: nodeState === "stopped" || nodeState === "failed" || nodeState === "unavailable"
    readonly property bool active: nodeState === "starting" || running || flushing

    // The module reports -1 for a number it does not know yet.
    function num(v) { var n = Number(v); return (v === undefined || v === null || v === "" || !isFinite(n)) ? -1 : n }
    readonly property real blocks: num(st.blocks)
    readonly property real headers: num(st.headers)
    readonly property real progressRaw: num(st.verificationProgress)
    readonly property int peersOut: num(st.peersOut)
    readonly property real tipAgeSecs: num(st.tipAgeSecs)
    readonly property real uptime: num(st.uptimeSecs)
    readonly property bool initialSync: st.initialSync === true
    readonly property bool regtest: net === "regtest"
    // Blocks come every ten minutes on average; an hour without one means nothing is arriving.
    readonly property int staleAfterSecs: 3600
    // A node just started has no peers yet; give it this long before calling that a fault.
    readonly property int peerGraceSecs: 300

    // Pure, so a test can drive states a live node will not hold on demand. A node is
    // Synchronized only with an outbound peer and a tip under an hour old: Core's own
    // initial-sync flag stays false on a node that has lost its peers.
    function syncState(running, isRegtest, ibd, peers, tipAge, upSecs) {
        if (!running) return ""
        if (isRegtest) return "local"
        if (peers <= 0 && (ibd || upSecs < root.peerGraceSecs)) return "waiting"
        if (ibd) return "syncing"
        if (peers > 0 && tipAge >= 0 && tipAge < root.staleAfterSecs) return "synced"
        return peers > 0 ? "stalled" : "nopeers"
    }
    function fmtBehind(s) {
        var d = Math.floor(s / 86400)
        if (d >= 2) return d + " days"
        var h = Math.floor(s / 3600)
        return h + (h === 1 ? " hour" : " hours")
    }
    function syncLabel(s, tipAge) {
        var behind = tipAge > root.staleAfterSecs ? " · " + root.fmtBehind(tipAge) + " behind" : ""
        if (s === "synced") return "Synchronized"
        if (s === "stalled") return "Stalled" + behind
        if (s === "nopeers") return "No peers" + behind
        if (s === "waiting") return "Waiting for peers"
        if (s === "syncing") return "Syncing"
        return s === "local" ? "Local chain" : ""
    }
    readonly property string sync: syncState(running, regtest, initialSync, peersOut, tipAgeSecs, uptime)
    readonly property bool synced: sync === "synced" || sync === "local"
    readonly property bool trouble: sync === "waiting" || sync === "stalled" || sync === "nopeers"
    readonly property real percent: progressRaw >= 0 ? Math.min(100, progressRaw * 100) : -1

    function stateColour(s) {
        if (s === "running") return Theme.palette.success
        if (s === "starting" || s === "flushing" || s === "stopping") return Theme.palette.info
        if (s === "failed" || s === "unavailable") return Theme.palette.error
        return Theme.palette.textTertiary
    }
    function fmtNum(n) { return n < 0 ? "—" : Number(n).toLocaleString(Qt.locale(), "f", 0) }
    function fmtUptime(s) {
        s = Math.max(0, s)
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
        return h > 0 ? (h + "h " + m + "m") : (m + "m " + (s % 60) + "s")
    }
    function fmtBytes(b) {
        if (b < 0) return "—"
        if (b >= 1e9) return (b / 1e9).toFixed(1) + " GB"
        if (b >= 1e6) return (b / 1e6).toFixed(0) + " MB"
        return (b / 1e3).toFixed(0) + " kB"
    }
    function rpcPort(n) { return n === "mainnet" ? 8332 : n === "testnet4" ? 48332 : n === "signet" ? 38332 : 18443 }

    // ---- what the node opens to other programs ----
    readonly property bool exposed: active && cfg.exposeRpc === true
    readonly property string exposedLine: exposed ? "Core's RPC on 127.0.0.1:" + rpcPort(net) + ", with the cookie in the data directory"
                                                  : "Nothing. The wallet reaches the node over Logos IPC."

    // ---- the settings form ----
    // The form's copy of exposeRpc: the switch turns on only through its warning.
    property bool rpcOn: false

    function loadForm() {
        dataDirField.text = cfg.dataDir || ""
        pruneField.text = cfg.pruneMiB !== undefined ? String(cfg.pruneMiB) : ""
        dbcacheField.text = cfg.dbcacheMiB !== undefined ? String(cfg.dbcacheMiB) : ""
        mempoolField.text = cfg.maxMempoolMiB !== undefined ? String(cfg.maxMempoolMiB) : ""
        proxyField.text = cfg.proxy || ""
        categoriesField.text = (cfg.logCategories || []).join(", ")
        addNodesField.text = (cfg.addNodes || []).join(", ")
        root.rpcOn = cfg.exposeRpc === true
    }
    onCfgChanged: loadForm()

    function list(text) { return text.split(/[\s,]+/).filter(function (s) { return s !== "" }) }
    readonly property bool pruneValid: /^\d+$/.test(pruneField.text.trim())
        && (parseInt(pruneField.text.trim(), 10) === 0 || parseInt(pruneField.text.trim(), 10) >= 550)
    readonly property bool formValid: dataDirField.text.trim() !== "" && pruneValid
        && /^\d+$/.test(dbcacheField.text.trim())
        && /^\d+$/.test(mempoolField.text.trim()) && parseInt(mempoolField.text.trim(), 10) >= 5
        && !/[\s"]/.test(proxyField.text.trim()) && list(addNodesField.text).length <= 8

    function saveForm() {
        backend.saveConfig(JSON.stringify({
            dataDir: dataDirField.text.trim(),
            pruneMiB: parseInt(pruneField.text.trim(), 10),
            dbcacheMiB: parseInt(dbcacheField.text.trim(), 10),
            maxMempoolMiB: parseInt(mempoolField.text.trim(), 10),
            proxy: proxyField.text.trim(),
            logCategories: root.list(categoriesField.text),
            addNodes: root.list(addNodesField.text),
            exposeRpc: root.rpcOn
        }))
    }

    // Turning the port off needs no warning; turning it on does.
    function toggleRpc() {
        if (root.rpcOn) { root.rpcOn = false; return }
        exposeDialog.open()
    }
    function startNode() {
        if (root.net === "mainnet") { mainnetDialog.open(); return }
        backend.start()
    }

    Connections {
        target: (typeof logos !== "undefined") ? logos : null
        ignoreUnknownSignals: true
        function onIntentRequested(requestId, intent, params, requesterName) {
            if (intent !== "bitcoin.node.configure") return
            var n = params && params.network ? String(params.network) : ""
            if (n !== "" && root.networks.indexOf(n) < 0) { logos.respond(requestId, false, ({}), "bad_request"); return }
            if (n !== "" && root.stopped) backend.selectNetwork(n)
            logos.respond(requestId, true, ({}), "")
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    LogosScrollView {
        anchors.fill: parent
        anchors.margins: 20

        ColumnLayout {
            width: root.width - 40
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                LogosText { text: "Bitcoin node"; font.pixelSize: 22; font.weight: Theme.typography.weightBold }
                LogosBadge { objectName: "stateBadge"; text: root.nodeState || "checking"; color: root.stateColour(root.nodeState) }
                Item { Layout.fillWidth: true }
                LogosText { text: "Network"; color: Theme.palette.textTertiary }
                LogosComboBox {
                    objectName: "networkCombo"
                    model: root.networks
                    enabled: root.ready && root.stopped && !backend.busy
                    currentIndex: Math.max(0, root.networks.indexOf(root.net))
                    onActivated: function(index) { backend.selectNetwork(root.networks[index]) }
                }
            }

            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.large

                contentItem: ColumnLayout {
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        LogosText {
                            objectName: "heightText"
                            textFormat: Text.PlainText
                            font.weight: Theme.typography.weightBold
                            text: root.running ? "Block " + root.fmtNum(root.blocks)
                                                 + (root.headers > root.blocks ? " of " + root.fmtNum(root.headers) : "")
                                  : root.nodeState === "starting" ? "Starting…"
                                  : root.flushing ? "Writing the chain state to disk…"
                                  : root.nodeState === "stopping" ? "Stopping…"
                                  : root.nodeState === "" ? "Checking…" : "Not running"
                        }
                        Item { Layout.fillWidth: true }
                        LogosText {
                            objectName: "syncText"
                            textFormat: Text.PlainText
                            color: root.trouble ? Theme.palette.warning : Theme.palette.textTertiary
                            text: root.syncLabel(root.sync, root.tipAgeSecs)
                        }
                        LogosText {
                            objectName: "syncPercent"
                            visible: root.sync === "syncing" && root.percent >= 0
                            textFormat: Text.PlainText
                            text: (Math.floor(root.percent * 10) / 10) + "%"
                        }
                    }

                    LogosProgressBar {
                        objectName: "syncBar"
                        Layout.fillWidth: true
                        value: root.synced ? 1 : (root.percent >= 0 ? root.percent / 100 : 0)
                        trackColor: Theme.palette.borderSecondary
                        indeterminate: root.nodeState === "starting" || root.flushing || (root.running && root.percent < 0)
                        fillColor: root.synced ? Theme.palette.success : root.trouble ? Theme.palette.warning : Theme.palette.info
                    }

                    LogosText {
                        objectName: "peersNote"
                        Layout.fillWidth: true
                        visible: root.trouble
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        color: Theme.palette.textSecondary
                        text: root.sync === "waiting"
                              ? "No outbound peer yet, so nothing can arrive. Over Tor the first one has taken from seconds to about a minute."
                              : root.sync === "stalled"
                              ? "Peers are connected but no block has arrived for " + root.fmtBehind(root.tipAgeSecs)
                                + ". An hour without a block happens rarely; much longer means the node is not being fed."
                              : "No outbound peer is connected, so no new block can arrive until the node finds one."
                    }

                    LogosText {
                        objectName: "flushText"
                        Layout.fillWidth: true
                        visible: root.flushing
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        color: Theme.palette.textSecondary
                        text: "Writing the UTXO cache to disk before the node stops"
                              + (root.ready && backend.stopSecs > 0 ? ": " + backend.stopSecs + " s so far." : ".")
                              + " Mid-sync with a large cache this takes several seconds; at the tip, less than one."
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 20
                        rowSpacing: 4
                        LogosText { text: "Outbound peers"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "peersText"; textFormat: Text.PlainText; text: root.running ? root.fmtNum(root.peersOut) : "—" }
                        LogosText { text: "Uptime"; color: Theme.palette.textTertiary }
                        LogosText { textFormat: Text.PlainText; text: root.running ? root.fmtUptime(root.uptime) : "—" }
                        LogosText { text: "Last block"; color: Theme.palette.textTertiary }
                        LogosText {
                            objectName: "tipAgeText"
                            textFormat: Text.PlainText
                            text: !root.running || root.tipAgeSecs < 0 ? "—"
                                  : root.tipAgeSecs < 120 ? root.tipAgeSecs + " s ago"
                                  : root.tipAgeSecs < 7200 ? Math.floor(root.tipAgeSecs / 60) + " min ago"
                                  : root.fmtBehind(root.tipAgeSecs) + " ago"
                        }
                        LogosText { text: "Filter index"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "filterText"; textFormat: Text.PlainText; text: root.running ? root.fmtNum(root.num(root.st.filterIndexHeight)) : "—" }
                        LogosText { text: "Pruned below"; color: Theme.palette.textTertiary }
                        LogosText {
                            textFormat: Text.PlainText
                            text: !root.running ? "—" : root.num(root.st.pruneHeight) > 0 ? "block " + root.fmtNum(root.num(root.st.pruneHeight))
                                  : root.num(root.st.pruneHeight) === 0 ? "nothing pruned" : "—"
                        }
                        LogosText { text: "On disk"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "sizeText"; textFormat: Text.PlainText; text: root.running ? root.fmtBytes(root.num(root.st.sizeOnDisk)) : "—" }
                        LogosText { text: "Cache"; color: Theme.palette.textTertiary }
                        LogosText {
                            objectName: "cacheText"
                            textFormat: Text.PlainText
                            text: !root.active ? "—" : root.num(root.st.dbcacheMiB) > 0 ? root.num(root.st.dbcacheMiB) + " MiB" : "Core's default"
                        }
                        LogosText { text: "Version"; color: Theme.palette.textTertiary }
                        LogosText { Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText; text: root.st.version || "—" }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 20
                        LogosText { text: "Data directory"; color: Theme.palette.textTertiary }
                        LogosText {
                            objectName: "dataDirText"
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            wrapMode: Text.WrapAnywhere
                            text: root.cfg.dataDir || "—"
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 20
                        LogosText { text: "Open to other programs"; color: Theme.palette.textTertiary }
                        LogosText {
                            objectName: "exposedText"
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: root.exposed ? Theme.palette.warning : Theme.palette.text
                            text: root.active ? root.exposedLine : "—"
                        }
                    }

                    LogosNotice {
                        objectName: "exposedNotice"
                        Layout.fillWidth: true
                        severity: LogosNotice.Warning
                        shown: root.exposed
                        title: "An RPC port open to every program on this computer"
                        message: "Core's RPC server listens on 127.0.0.1:" + root.rpcPort(root.net)
                                 + ". Callers need the cookie in the data directory, but any program on this computer can reach the port, "
                                 + "and so can web pages in a browser on this computer."
                    }

                    LogosText {
                        objectName: "errorText"
                        Layout.fillWidth: true
                        visible: text !== ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Theme.palette.error
                        text: !root.ready ? "The node module is not available."
                              : root.nodeState === "unavailable" ? "bitcoind_module is not answering."
                              : (backend.lastError || root.st.lastError || "")
                    }

                    RowLayout {
                        spacing: 10
                        LogosButton {
                            objectName: "startButton"
                            text: "Start"
                            enabled: root.ready && root.stopped && !backend.busy
                            onClicked: root.startNode()
                        }
                        LogosButton {
                            objectName: "stopButton"
                            text: "Stop"
                            enabled: root.ready && (root.nodeState === "starting" || root.running) && !backend.busy
                            onClicked: backend.stop()
                        }
                        LogosSpinner { visible: root.ready && backend.busy; running: visible }
                    }
                }
            }

            LogosNotice {
                objectName: "mainnetNotice"
                Layout.fillWidth: true
                severity: LogosNotice.Warning
                shown: root.ready && root.net === "mainnet" && root.stopped
                title: "Before a mainnet start"
                message: "Pruned with block filters, the node keeps about 30 GB in " + (root.cfg.dataDir || "its data directory")
                         + ". Its first sync still downloads every block: about 774 GB, roughly 43 hours over Tor at 5 MB/s "
                         + "(an estimate)."
            }

            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.large

                contentItem: ColumnLayout {
                    objectName: "settingsForm"
                    spacing: 8
                    enabled: root.cfgRead && root.stopped && !backend.busy

                    LogosText { text: "Settings for " + root.net + " (apply on the next start)"; font.weight: Theme.typography.weightBold }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 8
                        LogosText { text: "Data directory"; color: Theme.palette.textTertiary }
                        LogosTextField { id: dataDirField; objectName: "dataDirField"; Layout.fillWidth: true }
                        LogosText { text: "Prune to (MiB)"; color: Theme.palette.textTertiary }
                        LogosTextField { id: pruneField; objectName: "pruneField"; Layout.fillWidth: true; placeholderText: "0 keeps every block; at least 550" }
                        LogosText { text: "Cache during sync (MiB)"; color: Theme.palette.textTertiary }
                        LogosTextField { id: dbcacheField; objectName: "dbcacheField"; Layout.fillWidth: true; placeholderText: "0 is Core's default; 300 once synced" }
                        LogosText { text: "Mempool (MiB)"; color: Theme.palette.textTertiary }
                        LogosTextField { id: mempoolField; objectName: "mempoolField"; Layout.fillWidth: true; placeholderText: "300" }
                        LogosText { text: "Tor proxy"; color: Theme.palette.textTertiary }
                        LogosTextField { id: proxyField; objectName: "proxyField"; Layout.fillWidth: true; placeholderText: "127.0.0.1:9050" }
                        LogosText { text: "Own peers"; color: Theme.palette.textTertiary }
                        LogosTextField { id: addNodesField; objectName: "addNodesField"; Layout.fillWidth: true; placeholderText: "host:port, up to 8" }
                        LogosText { text: "Log categories"; color: Theme.palette.textTertiary }
                        LogosTextField { id: categoriesField; objectName: "categoriesField"; Layout.fillWidth: true; placeholderText: "net, mempool" }
                    }

                    LogosText {
                        objectName: "proxyNote"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: proxyField.text.trim() === "" && root.net !== "regtest" ? Theme.palette.warning : Theme.palette.textSecondary
                        text: proxyField.text.trim() === "" && root.net !== "regtest"
                              ? "No proxy: the node connects over clearnet, and its peers see this computer's IP address running a Bitcoin node. Transactions are broadcast the ordinary way."
                              : "Through the proxy the node reaches only onion peers, and sends your transactions over short-lived Tor connections of their own."
                    }

                    LogosText { Layout.topMargin: 8; text: "Open to other programs on this computer"; font.weight: Theme.typography.weightBold }
                    LogosText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Theme.palette.textSecondary
                        text: "Off by default. The wallet does not need it: it reaches the node over Logos IPC. "
                            + "Turn it on only for another program on this computer that asks for it, such as bitcoin-cli."
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        LogosSwitch {
                            objectName: "exposeRpcSwitch"
                            Layout.preferredWidth: 200
                            text: "Core's RPC server"
                            checkable: false
                            checked: root.rpcOn
                            onClicked: root.toggleRpc()
                        }
                        LogosText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: root.rpcOn ? Theme.palette.warning : Theme.palette.textTertiary
                            text: root.rpcOn ? "127.0.0.1:" + root.rpcPort(root.net) + " on the next start: cookie authentication, the wallet's read methods and sendrawtransaction only."
                                             : "Closed."
                        }
                    }

                    RowLayout {
                        Layout.topMargin: 8
                        LogosButton { objectName: "saveButton"; text: "Save settings"; enabled: root.formValid; onClicked: root.saveForm() }
                        LogosButton { text: "Revert"; onClicked: root.loadForm() }
                    }
                }
            }

            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.large

                contentItem: ColumnLayout {
                    spacing: 6
                    LogosText { text: "Node log"; font.weight: Theme.typography.weightBold }
                    LogosText {
                        objectName: "logText"
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        font.family: Theme.typography.mono
                        font.pixelSize: 11
                        color: Theme.palette.textTertiary
                        text: root.ready && backend.logText ? backend.logText : "No log yet."
                    }
                }
            }
        }
    }

    LogosWarningDialog {
        id: exposeDialog
        objectName: "exposeDialog"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        title: "Open Core's RPC port to other programs?"
        message: "This opens Bitcoin Core's RPC server on 127.0.0.1:" + root.rpcPort(root.net) + " when the node next starts. "
                 + "Callers need the cookie Core writes in the data directory, and may use only the wallet's read methods "
                 + "and sendrawtransaction. Any program on this computer can reach the port, and so can web pages open in a "
                 + "browser on this computer. The wallet does not need it."
        leftActions: [ LogosButton { objectName: "exposeCancelButton"; text: "Cancel"; onClicked: exposeDialog.close() } ]
        rightActions: [ LogosButton { objectName: "exposeConfirmButton"; text: "Open the port"; onClicked: { root.rpcOn = true; exposeDialog.close() } } ]
    }

    LogosWarningDialog {
        id: mainnetDialog
        objectName: "mainnetDialog"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        title: "Start a mainnet node?"
        message: "Pruned with block filters, it keeps about 30 GB in " + (root.cfg.dataDir || "its data directory") + ". "
                 + "Its first sync still downloads every block: about 774 GB, roughly 43 hours over Tor at 5 MB/s "
                 + "(an estimate). You can stop it and carry on later."
        leftActions: [ LogosButton { objectName: "mainnetCancelButton"; text: "Cancel"; onClicked: mainnetDialog.close() } ]
        rightActions: [ LogosButton { objectName: "mainnetConfirmButton"; text: "Start"; onClicked: { mainnetDialog.close(); backend.start() } } ]
    }
}
