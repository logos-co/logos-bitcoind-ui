#include "BitcoindBackend.h"

#include "logos_sdk.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStringList>

#include <cmath>

namespace {
constexpr int kPollMs = 2000;
constexpr int kStartTimeoutMs = 30000;
// stop() writes the cache first: seconds at the tip, longer mid-sync with a large cache.
constexpr int kStopTimeoutMs = 180000;
constexpr int kLogLines = 80;

QString toJson(const QVariantMap& m) {
    return QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(m)).toJson(QJsonDocument::Compact));
}
QString describe(const QString& e) { return e.isEmpty() ? QStringLiteral("unknown error") : e; }
QString describe(const logos::CallError& e) { return describe(QString::fromStdString(e.message)); }

// The module refuses a setting of the wrong type, and a JSON number arrives here as a double.
QVariantMap integral(QVariantMap m) {
    for (auto it = m.begin(); it != m.end(); ++it) {
        const double d = it->toDouble();
        if (it->typeId() == QMetaType::Double && std::floor(d) == d) *it = QVariant::fromValue<qint64>(qint64(d));
    }
    return m;
}

// Core's lines are "2026-10-10T23:47:30Z message" (or with microseconds); keep the time of day.
QString compactLog(const QString& raw) {
    static const QRegularExpression line(QStringLiteral(
        "^\\d{4}-\\d\\d-\\d\\dT(\\d\\d:\\d\\d:\\d\\d)(?:\\.\\d+)?Z\\s+(.*)$"));
    QStringList out;
    for (const QString& l : raw.trimmed().split(u'\n')) {
        const auto m = line.match(l);
        out << (m.hasMatch() ? m.captured(1) + QStringLiteral("  ") + m.captured(2) : l);
    }
    return out.join(u'\n');
}
}

BitcoindBackend::BitcoindBackend(QObject* parent) : BitcoindBackendSimpleSource(parent) {
    setNetwork(QStringLiteral("signet"));
    setNetworksJson(QStringLiteral("[\"mainnet\",\"testnet4\",\"signet\",\"regtest\"]"));
}

void BitcoindBackend::onContextReady() {
    // The callback runs on the IPC read stack, so it only queues.
    modules().bitcoind_module.onBitcoindStateChanged([this](QString payload) {
        QTimer::singleShot(0, this, [this, payload] {
            applyStatus(QJsonDocument::fromJson(payload.toUtf8()).object().toVariantMap());
        });
    });
    m_poll = new QTimer(this);
    m_poll->setInterval(kPollMs);
    connect(m_poll, &QTimer::timeout, this, [this] { poll(); });
    m_poll->start();
    m_stopClock = new QTimer(this);
    m_stopClock->setInterval(1000);
    connect(m_stopClock, &QTimer::timeout, this, [this] { setStopSecs(int(m_stopSince.elapsed() / 1000)); });
    loadConfig();
    poll();
}

void BitcoindBackend::applyStatus(QVariantMap st) {
    QString state = st.value("state").toString();
    if (state.isEmpty()) return;
    // Until the module starts writing the cache, a stop in flight still reads "running".
    if (m_stopping && state == QLatin1String("running")) state = QStringLiteral("flushing");
    st.insert("state", state);
    setState(state);
    setStatusJson(toJson(st));
    const QString running = st.value("network").toString().toLower();
    if (!running.isEmpty() && state != QLatin1String("stopped") && state != QLatin1String("failed")
        && running != network()) {
        setNetwork(running);  // show the node that is actually running
        setConfigJson({});
        loadConfig();
    }
}

void BitcoindBackend::poll() {
    if (!isContextReady()) return;
    modules().bitcoind_module.statusAsyncResult([this](logos::AsyncResult<QVariantMap> r) {
        if (!r.ok()) { setState(QStringLiteral("unavailable")); return; }
        applyStatus(r.value);
    });
    modules().bitcoind_module.logTailAsyncResult(kLogLines, [this](logos::AsyncResult<QString> r) {
        if (r.ok()) setLogText(compactLog(r.value));
    });
}

void BitcoindBackend::loadConfig() {
    if (!isContextReady()) return;
    const QString n = network();
    modules().bitcoind_module.getConfigAsyncResult(n, [this, n](logos::AsyncResult<QVariantMap> r) {
        if (r.ok() && n == network()) setConfigJson(toJson(r.value));
    });
}

void BitcoindBackend::selectNetwork(QString n) {
    if (n == network()) return;
    setNetwork(n);
    setConfigJson({});  // the form waits for this network's settings rather than show the last one's
    setLastError({});
    loadConfig();
}

void BitcoindBackend::saveConfig(QString configJson) {
    if (!isContextReady()) return;
    const QString n = network();
    const QVariantMap cfg = integral(QJsonDocument::fromJson(configJson.toUtf8()).object().toVariantMap());
    modules().bitcoind_module.configureAsyncResult(n, cfg, [this, n](logos::AsyncResult<LogosResult> r) {
        if (!r.ok()) { setLastError(describe(r.error)); return; }
        if (!r.value.success) { setLastError(describe(r.value.error.toString())); return; }
        setLastError({});
        if (n == network()) setConfigJson(toJson(r.value.value.toMap()));
    });
}

void BitcoindBackend::start() {
    if (!isContextReady() || busy()) return;
    setBusy(true);
    setLastError({});
    modules().bitcoind_module.startAsyncResult(network(), [this](logos::AsyncResult<LogosResult> r) {
        setBusy(false);
        if (!r.ok()) setLastError(describe(r.error));
        else if (!r.value.success) setLastError(describe(r.value.error.toString()));
        poll();
    }, Timeout(kStartTimeoutMs));
}

void BitcoindBackend::stop() {
    if (!isContextReady() || busy()) return;
    setBusy(true);
    m_stopping = true;
    m_stopSince.start();
    setStopSecs(0);
    m_stopClock->start();
    modules().bitcoind_module.stopAsyncResult([this](logos::AsyncResult<LogosResult> r) {
        setBusy(false);
        m_stopping = false;
        m_stopClock->stop();
        setStopSecs(0);
        if (!r.ok()) setLastError(describe(r.error));
        poll();
    }, Timeout(kStopTimeoutMs));
}

void BitcoindBackend::refresh() {
    loadConfig();
    poll();
}
