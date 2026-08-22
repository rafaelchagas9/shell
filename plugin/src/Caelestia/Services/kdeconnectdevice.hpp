#pragma once

#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qvariantmap.h>

namespace caelestia::services {

class KdeConnectDevice : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("KdeConnect devices are provided by the KdeConnect service")

    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString name READ name NOTIFY nameChanged)
    Q_PROPERTY(QString type READ type NOTIFY typeChanged)
    Q_PROPERTY(bool reachable READ reachable NOTIFY reachableChanged)
    Q_PROPERTY(bool paired READ paired NOTIFY pairedChanged)
    Q_PROPERTY(bool batteryAvailable READ batteryAvailable NOTIFY batteryChanged)
    Q_PROPERTY(int batteryPercentage READ batteryPercentage NOTIFY batteryChanged)
    Q_PROPERTY(bool charging READ charging NOTIFY batteryChanged)

public:
    explicit KdeConnectDevice(QString id, QObject* parent = nullptr);

    [[nodiscard]] QString id() const;
    [[nodiscard]] QString name() const;
    [[nodiscard]] QString type() const;
    [[nodiscard]] bool reachable() const;
    [[nodiscard]] bool paired() const;
    [[nodiscard]] bool batteryAvailable() const;
    [[nodiscard]] int batteryPercentage() const;
    [[nodiscard]] bool charging() const;

    void refresh();

signals:
    void nameChanged();
    void typeChanged();
    void reachableChanged();
    void pairedChanged();
    void batteryChanged();

private slots:
    void handleNameChanged(const QString& name);
    void handleTypeChanged(const QString& type);
    void handleReachableChanged(bool reachable);
    void handlePairStateChanged(int state);
    void handlePluginsChanged();
    void handleBatteryRefreshed(bool charging, int charge);

private:
    void connectSignals();
    void refreshDevice();
    void refreshBattery();
    void applyDeviceProperties(const QVariantMap& properties);
    void applyBatteryProperties(const QVariantMap& properties);
    void clearBattery();

    QString m_id;
    QString m_name;
    QString m_type;
    bool m_reachable = false;
    bool m_paired = false;
    bool m_batteryAvailable = false;
    int m_batteryPercentage = -1;
    bool m_charging = false;
    quint64 m_deviceRefreshGeneration = 0;
    quint64 m_batteryRefreshGeneration = 0;
};

} // namespace caelestia::services
