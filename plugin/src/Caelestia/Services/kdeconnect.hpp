#pragma once

#include "kdeconnectdevice.hpp"

#include <qhash.h>
#include <qmap.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qqmllist.h>

class QDBusServiceWatcher;

namespace caelestia::services {

class KdeConnect : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(QQmlListProperty<caelestia::services::KdeConnectDevice> devices READ devices NOTIFY devicesChanged)

public:
    explicit KdeConnect(QObject* parent = nullptr);

    [[nodiscard]] bool available() const;
    [[nodiscard]] QQmlListProperty<KdeConnectDevice> devices();

    Q_INVOKABLE void refresh();

signals:
    void availableChanged();
    void devicesChanged();

private slots:
    void handleServiceRegistered();
    void handleServiceUnregistered();
    void handleDeviceAdded(const QString& id);
    void handleDeviceRemoved(const QString& id);
    void handleDeviceListChanged();

private:
    void connectDaemonSignals();
    void disconnectDaemonSignals();
    void setAvailable(bool available);
    void reconcileDevices(const QMap<QString, QString>& devices);
    void clearDevices();

    static qsizetype devicesCount(QQmlListProperty<KdeConnectDevice>* property);
    static KdeConnectDevice* deviceAt(QQmlListProperty<KdeConnectDevice>* property, qsizetype index);

    QDBusServiceWatcher* m_serviceWatcher;
    QList<KdeConnectDevice*> m_devices;
    bool m_available = false;
    quint64 m_refreshGeneration = 0;
};

} // namespace caelestia::services
