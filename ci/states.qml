import QtQuick

// Drives the view's pure sync functions through every state a live node will not hold on demand,
// and prints STATES-OK or the cases that disagree.
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
            console.log(bad.length ? "STATES-FAIL " + bad.join("; ") : "STATES-OK " + cases.length + " cases")
        }
    }
}
