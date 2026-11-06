import QtQuick

// Drives the view's pure sync and private-sends functions through every state a live node will not
// hold on demand, and prints STATES-OK or the cases that disagree.
Item {
    width: 1024; height: 768
    Loader {
        id: view
        anchors.fill: parent
        source: "../src/qml/Main.qml"
        onStatusChanged: {
            if (status !== Loader.Ready) { if (status === Loader.Error) console.log("STATES-FAIL load"); return }
            var v = view.item
            // running, regtest, initial sync, peers out, tip age, uptime -> label
            var cases = [
                [false, false, true, 0, -1, 0, ""],
                [true, false, true, 0, 9000000, 40, "Waiting for peers"],
                [true, false, true, 4, 9000000, 400, "Syncing"],
                [true, false, false, 0, 300, 30, "Waiting for peers"],
                [true, false, false, 8, 300, 900, "Synchronized"],
                [true, false, false, 8, 3700, 900, "Stalled · 1 hour behind"],
                [true, false, false, 8, 200000, 900, "Stalled · 2 days behind"],
                [true, false, false, 0, 600, 900, "No peers"],
                [true, false, false, 0, 7300, 900, "No peers · 2 hours behind"],
                [true, true, true, 0, 494000000, 5, "Local chain"]
            ]
            var bad = []
            for (var i = 0; i < cases.length; ++i) {
                var c = cases[i]
                var got = v.syncLabel(v.syncState(c[0], c[1], c[2], c[3], c[4], c[5]), c[4])
                if (got !== c[6]) bad.push(i + ": got '" + got + "', want '" + c[6] + "'")
            }
            var n = cases.length
            function want(name, got, expected) {
                ++n
                if (got !== expected) bad.push(name + ": got '" + got + "', want '" + expected + "'")
            }

            // status().privateSends -> the status row, and whether it warns.
            var modes = [
                ["on", "Over Tor, each to a few random peers", false],
                ["proxy", "Over Tor, through your proxy", false],
                ["off", "The ordinary way, from this computer's IP address", false],
                ["unavailable", "The ordinary way: Tor was unavailable when the node started", true],
                ["restart", "Not going out: restart the node", true],
                ["", "—", false]
            ]
            for (var m = 0; m < modes.length; ++m) {
                want("line " + modes[m][0], v.sendsLine(modes[m][0]), modes[m][1])
                want("warn " + modes[m][0], v.sendsWarn(modes[m][0]), modes[m][2])
            }
            want("restart message", v.sendsMessage("restart", "Tor's SOCKS port moved to 127.0.0.1:9251").indexOf("Tor's SOCKS port moved to 127.0.0.1:9251. "), 0)
            want("unavailable message", v.sendsMessage("unavailable", "tor_module is not loaded").indexOf("tor_module is not loaded. "), 0)
            want("unavailable title", v.sendsTitle("unavailable"), "Your transactions are not going over Tor")

            // The switch's note: network, proxy field, switch.
            want("note on", v.sendsNote("signet", "", true).indexOf("Send your transactions over Tor: each goes to a few random peers"), 0)
            want("note off", v.sendsNote("mainnet", "", false), "Off: your transactions go out the ordinary way, from this computer's IP address.")
            want("note regtest", v.sendsNote("regtest", "", true), "Regtest is a local chain with no onion peers: with this on, transactions do not go out.")
            want("note proxy", v.sendsNote("signet", "127.0.0.1:9050", false), "With a proxy the node always sends your transactions over Tor, through the proxy.")

            // Saved only to a module that knows the setting: an older one refuses unknown keys.
            want("save to an older module", JSON.stringify(v.withSends({ proxy: "" }, false, true)), '{"proxy":""}')
            want("save on", JSON.stringify(v.withSends({ proxy: "" }, true, true)), '{"proxy":"","privateSends":true}')
            want("save off", JSON.stringify(v.withSends({ proxy: "" }, true, false)), '{"proxy":"","privateSends":false}')

            // Without a module (as here) the view knows no privateSends: switch and row hidden.
            function find(item, name) {
                if (!item) return null
                if (item.objectName === name) return item
                var kids = item.children || []
                for (var k = 0; k < kids.length; ++k) { var f = find(kids[k], name); if (f) return f }
                return null
            }
            want("found the RPC switch", find(v, "exposeRpcSwitch") !== null, true)
            want("RPC switch row shown", find(v, "exposeRpcSwitch") !== null && find(v, "exposeRpcSwitch").parent.visible, true)
            var sw = find(v, "privateSendsSwitch")
            want("found the switch", sw !== null, true)
            want("switch hidden without the setting", sw !== null && sw.parent.visible, false)
            want("row hidden without the field", find(v, "privateSendsText") !== null && find(v, "privateSendsText").parent.visible, false)

            console.log(bad.length ? "STATES-FAIL " + bad.join("; ") : "STATES-OK " + n + " cases")
        }
    }
}
