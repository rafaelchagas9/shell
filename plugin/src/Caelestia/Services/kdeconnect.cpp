#include "kdeconnect.hpp"

#include <QtDBus/qdbusconnection.h>
#include <QtDBus/qdbusconnectioninterface.h>
#include <QtDBus/qdbusmessage.h>
#include <QtDBus/qdbuspendingcall.h>
#include <QtDBus/qdbuspendingreply.h>
#include <QtDBus/qdbusreply.h>
#include <QtDBus/qdbusservicewatcher.h>
#include <utility>

namespace caelestia::services {

namespace {

constexpr auto KDE_CONNECT_SERVICE = "org.kde.kdeconnect";
constexpr auto DAEMON_PATH = "/modules/kdeconnect";
constexpr auto DAEMON_INTERFACE = "org.kde.kdeconnect.daemon";

} // namespace

KdeConnect::KdeConnect(QObject* parent)
    : QObject(parent)
    , m_serviceWatcher(new QDBusServiceWatcher(QString::fromLatin1(KDE_CONNECT_SERVICE), QDBusConnection::sessionBus(),
          QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration, this)) {
    connect(m_serviceWatcher, &QDBusServiceWatcher::serviceRegistered, this, &KdeConnect::handleServiceRegistered);
    connect(m_serviceWatcher, &QDBusServiceWatcher::serviceUnregistered, this, &KdeConnect::handleServiceUnregistered);

    auto* interface = QDBusConnection::sessionBus().interface();
    const QDBusReply<bool> registered = interface->isServiceRegistered(QString::fromLatin1(KDE_CONNECT_SERVICE));
    if (registered.isValid() && registered.value()) {
        handleServiceRegistered();
    } else {
        interface->startService(QString::fromLatin1(KDE_CONNECT_SERVICE));
    }
}

bool KdeConnect::available() const {
    return m_available;
}

QQmlListProperty<KdeConnectDevice> KdeConnect::devices() {
    return QQmlListProperty<KdeConnectDevice>(this, nullptr, &KdeConnect::devicesCount, &KdeConnect::deviceAt);
}

void KdeConnect::refresh() {
    if (!m_available) {
        return;
    }

    const quint64 generation = ++m_refreshGeneration;
    auto message = QDBusMessage::createMethodCall(QString::fromLatin1(KDE_CONNECT_SERVICE),
        QString::fromLatin1(DAEMON_PATH), QString::fromLatin1(DAEMON_INTERFACE), QStringLiteral("deviceNames"));
    message.setArguments({ false, true });

    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, generation] {
        const QDBusPendingReply<QMap<QString, QString>> reply = *watcher;
        watcher->deleteLater();
        if (reply.isValid() && m_available && generation == m_refreshGeneration) {
            reconcileDevices(reply.value());
        }
    });
}

void KdeConnect::handleServiceRegistered() {
    if (m_available) {
        return;
    }

    setAvailable(true);
    connectDaemonSignals();
    refresh();
}

void KdeConnect::handleServiceUnregistered() {
    if (!m_available) {
        return;
    }

    ++m_refreshGeneration;
    disconnectDaemonSignals();
    clearDevices();
    setAvailable(false);
}

void KdeConnect::handleDeviceAdded(const QString& id) {
    Q_UNUSED(id)
    refresh();
}

void KdeConnect::handleDeviceRemoved(const QString& id) {
    Q_UNUSED(id)
    refresh();
}

void KdeConnect::handleDeviceListChanged() {
    refresh();
}

void KdeConnect::connectDaemonSignals() {
    auto bus = QDBusConnection::sessionBus();
    bus.connect(QString::fromLatin1(KDE_CONNECT_SERVICE), QString::fromLatin1(DAEMON_PATH),
        QString::fromLatin1(DAEMON_INTERFACE), QStringLiteral("deviceAdded"), this, SLOT(handleDeviceAdded(QString)));
    bus.connect(QString::fromLatin1(KDE_CONNECT_SERVICE), QString::fromLatin1(DAEMON_PATH),
        QString::fromLatin1(DAEMON_INTERFACE), QStringLiteral("deviceRemoved"), this,
        SLOT(handleDeviceRemoved(QString)));
    bus.connect(QString::fromLatin1(KDE_CONNECT_SERVICE), QString::fromLatin1(DAEMON_PATH),
        QString::fromLatin1(DAEMON_INTERFACE), QStringLiteral("deviceListChanged"), this,
        SLOT(handleDeviceListChanged()));
}

void KdeConnect::disconnectDaemonSignals() {
    auto bus = QDBusConnection::sessionBus();
    bus.disconnect(QString::fromLatin1(KDE_CONNECT_SERVICE), QString::fromLatin1(DAEMON_PATH),
        QString::fromLatin1(DAEMON_INTERFACE), QStringLiteral("deviceAdded"), this, SLOT(handleDeviceAdded(QString)));
    bus.disconnect(QString::fromLatin1(KDE_CONNECT_SERVICE), QString::fromLatin1(DAEMON_PATH),
        QString::fromLatin1(DAEMON_INTERFACE), QStringLiteral("deviceRemoved"), this,
        SLOT(handleDeviceRemoved(QString)));
    bus.disconnect(QString::fromLatin1(KDE_CONNECT_SERVICE), QString::fromLatin1(DAEMON_PATH),
        QString::fromLatin1(DAEMON_INTERFACE), QStringLiteral("deviceListChanged"), this,
        SLOT(handleDeviceListChanged()));
}

void KdeConnect::setAvailable(bool available) {
    if (m_available == available) {
        return;
    }
    m_available = available;
    emit availableChanged();
}

void KdeConnect::reconcileDevices(const QMap<QString, QString>& namedDevices) {
    QHash<QString, KdeConnectDevice*> existing;
    existing.reserve(m_devices.size());
    for (KdeConnectDevice* device : std::as_const(m_devices)) {
        existing.insert(device->id(), device);
    }

    QList<KdeConnectDevice*> devices;
    devices.reserve(namedDevices.size());
    for (auto it = namedDevices.cbegin(); it != namedDevices.cend(); ++it) {
        const QString& id = it.key();
        if (KdeConnectDevice* device = existing.take(id)) {
            device->refresh();
            devices.append(device);
        } else {
            devices.append(new KdeConnectDevice(id, this));
        }
    }

    for (KdeConnectDevice* device : std::as_const(existing)) {
        device->deleteLater();
    }

    if (m_devices == devices) {
        return;
    }
    m_devices = std::move(devices);
    emit devicesChanged();
}

void KdeConnect::clearDevices() {
    if (m_devices.isEmpty()) {
        return;
    }
    for (KdeConnectDevice* device : std::as_const(m_devices)) {
        device->deleteLater();
    }
    m_devices.clear();
    emit devicesChanged();
}

qsizetype KdeConnect::devicesCount(QQmlListProperty<KdeConnectDevice>* property) {
    return static_cast<KdeConnect*>(property->object)->m_devices.size();
}

KdeConnectDevice* KdeConnect::deviceAt(QQmlListProperty<KdeConnectDevice>* property, qsizetype index) {
    return static_cast<KdeConnect*>(property->object)->m_devices.at(index);
}

} // namespace caelestia::services
