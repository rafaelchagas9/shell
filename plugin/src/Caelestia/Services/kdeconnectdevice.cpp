#include "kdeconnectdevice.hpp"

#include <QtDBus/qdbusconnection.h>
#include <QtDBus/qdbusmessage.h>
#include <QtDBus/qdbuspendingcall.h>
#include <QtDBus/qdbuspendingreply.h>
#include <algorithm>
#include <utility>

namespace caelestia::services {

namespace {

constexpr auto KDE_CONNECT_SERVICE = "org.kde.kdeconnect";
constexpr auto DEVICE_INTERFACE = "org.kde.kdeconnect.device";
constexpr auto BATTERY_INTERFACE = "org.kde.kdeconnect.device.battery";
constexpr auto PROPERTIES_INTERFACE = "org.freedesktop.DBus.Properties";

[[nodiscard]] QString devicePath(const QString& id) {
    return QStringLiteral("/modules/kdeconnect/devices/") + id;
}

[[nodiscard]] QString batteryPath(const QString& id) {
    return devicePath(id) + QStringLiteral("/battery");
}

template <typename Callback>
void fetchProperties(QObject* context, const QString& path, const QString& interface, Callback&& callback) {
    auto message = QDBusMessage::createMethodCall(QString::fromLatin1(KDE_CONNECT_SERVICE), path,
        QString::fromLatin1(PROPERTIES_INTERFACE), QStringLiteral("GetAll"));
    message.setArguments({ interface });

    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message), context);
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, context,
        [watcher, callback = std::forward<Callback>(callback)]() mutable {
            const QDBusPendingReply<QVariantMap> reply = *watcher;
            watcher->deleteLater();
            if (reply.isValid()) {
                callback(reply.value());
            }
        });
}

} // namespace

KdeConnectDevice::KdeConnectDevice(QString id, QObject* parent)
    : QObject(parent)
    , m_id(std::move(id)) {
    connectSignals();
    refresh();
}

QString KdeConnectDevice::id() const {
    return m_id;
}

QString KdeConnectDevice::name() const {
    return m_name;
}

QString KdeConnectDevice::type() const {
    return m_type;
}

bool KdeConnectDevice::reachable() const {
    return m_reachable;
}

bool KdeConnectDevice::paired() const {
    return m_paired;
}

bool KdeConnectDevice::batteryAvailable() const {
    return m_batteryAvailable;
}

int KdeConnectDevice::batteryPercentage() const {
    return m_batteryPercentage;
}

bool KdeConnectDevice::charging() const {
    return m_charging;
}

void KdeConnectDevice::refresh() {
    refreshDevice();
    refreshBattery();
}

void KdeConnectDevice::handleNameChanged(const QString& name) {
    if (m_name == name) {
        return;
    }
    m_name = name;
    emit nameChanged();
}

void KdeConnectDevice::handleTypeChanged(const QString& type) {
    if (m_type == type) {
        return;
    }
    m_type = type;
    emit typeChanged();
}

void KdeConnectDevice::handleReachableChanged(bool reachable) {
    if (m_reachable == reachable) {
        return;
    }
    m_reachable = reachable;
    emit reachableChanged();

    if (reachable) {
        refreshBattery();
    } else {
        clearBattery();
    }
}

void KdeConnectDevice::handlePairStateChanged(int state) {
    Q_UNUSED(state)
    refreshDevice();
}

void KdeConnectDevice::handlePluginsChanged() {
    refreshBattery();
}

void KdeConnectDevice::handleBatteryRefreshed(bool charging, int charge) {
    if (!m_reachable) {
        return;
    }

    const int percentage = std::clamp(charge, 0, 100);
    const bool available = charge >= 0;
    if (m_batteryAvailable == available && m_batteryPercentage == percentage && m_charging == charging) {
        return;
    }

    m_batteryAvailable = available;
    m_batteryPercentage = available ? percentage : -1;
    m_charging = available && charging;
    emit batteryChanged();
}

void KdeConnectDevice::connectSignals() {
    auto bus = QDBusConnection::sessionBus();
    const QString devPath = devicePath(m_id);
    bus.connect(QString::fromLatin1(KDE_CONNECT_SERVICE), devPath, QString::fromLatin1(DEVICE_INTERFACE),
        QStringLiteral("nameChanged"), this, SLOT(handleNameChanged(QString)));
    bus.connect(QString::fromLatin1(KDE_CONNECT_SERVICE), devPath, QString::fromLatin1(DEVICE_INTERFACE),
        QStringLiteral("typeChanged"), this, SLOT(handleTypeChanged(QString)));
    bus.connect(QString::fromLatin1(KDE_CONNECT_SERVICE), devPath, QString::fromLatin1(DEVICE_INTERFACE),
        QStringLiteral("reachableChanged"), this, SLOT(handleReachableChanged(bool)));
    bus.connect(QString::fromLatin1(KDE_CONNECT_SERVICE), devPath, QString::fromLatin1(DEVICE_INTERFACE),
        QStringLiteral("pairStateChanged"), this, SLOT(handlePairStateChanged(int)));
    bus.connect(QString::fromLatin1(KDE_CONNECT_SERVICE), devPath, QString::fromLatin1(DEVICE_INTERFACE),
        QStringLiteral("pluginsChanged"), this, SLOT(handlePluginsChanged()));
    bus.connect(QString::fromLatin1(KDE_CONNECT_SERVICE), batteryPath(m_id), QString::fromLatin1(BATTERY_INTERFACE),
        QStringLiteral("refreshed"), this, SLOT(handleBatteryRefreshed(bool, int)));
}

void KdeConnectDevice::refreshDevice() {
    const quint64 generation = ++m_deviceRefreshGeneration;
    fetchProperties(this, devicePath(m_id), QString::fromLatin1(DEVICE_INTERFACE),
        [this, generation](const QVariantMap& properties) {
            if (generation == m_deviceRefreshGeneration) {
                applyDeviceProperties(properties);
            }
        });
}

void KdeConnectDevice::refreshBattery() {
    const quint64 generation = ++m_batteryRefreshGeneration;
    fetchProperties(this, batteryPath(m_id), QString::fromLatin1(BATTERY_INTERFACE),
        [this, generation](const QVariantMap& properties) {
            if (generation == m_batteryRefreshGeneration && m_reachable) {
                applyBatteryProperties(properties);
            }
        });
}

void KdeConnectDevice::applyDeviceProperties(const QVariantMap& properties) {
    handleNameChanged(properties.value(QStringLiteral("name")).toString());
    handleTypeChanged(properties.value(QStringLiteral("type")).toString());

    const bool reachable = properties.value(QStringLiteral("isReachable")).toBool();
    handleReachableChanged(reachable);

    const bool paired = properties.value(QStringLiteral("isPaired")).toBool();
    if (m_paired != paired) {
        m_paired = paired;
        emit pairedChanged();
    }
}

void KdeConnectDevice::applyBatteryProperties(const QVariantMap& properties) {
    const int charge = properties.value(QStringLiteral("charge"), -1).toInt();
    const bool hasBattery = properties.value(QStringLiteral("hasBattery"), charge >= 0).toBool();
    if (!hasBattery || charge < 0) {
        clearBattery();
        return;
    }

    handleBatteryRefreshed(properties.value(QStringLiteral("isCharging")).toBool(), charge);
}

void KdeConnectDevice::clearBattery() {
    ++m_batteryRefreshGeneration;
    if (!m_batteryAvailable && m_batteryPercentage == -1 && !m_charging) {
        return;
    }

    m_batteryAvailable = false;
    m_batteryPercentage = -1;
    m_charging = false;
    emit batteryChanged();
}

} // namespace caelestia::services
