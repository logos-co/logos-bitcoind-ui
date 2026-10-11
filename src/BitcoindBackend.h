#pragma once

#include "logos_ui_plugin_context.h"
#include "rep_BitcoindBackend_source.h"

#include <QElapsedTimer>
#include <QTimer>
#include <QVariantMap>

// Every bitcoind_module call is made here; the QML renders. The event carries state changes
// at once; the poll carries blocks and peers, which move without one.
class BitcoindBackend : public BitcoindBackendSimpleSource, public LogosUiPluginContext {
    Q_OBJECT
public:
    explicit BitcoindBackend(QObject* parent = nullptr);

    void selectNetwork(QString network) override;
    void saveConfig(QString configJson) override;
    void start() override;
    void stop() override;
    void refresh() override;

protected:
    void onContextReady() override;

private:
    void poll();
    void loadConfig();
    void applyStatus(QVariantMap st);

    QTimer* m_poll = nullptr;
    QTimer* m_stopClock = nullptr;
    QElapsedTimer m_stopSince;
    bool m_stopping = false;
};
