#pragma once

#include "protocol.h"
#include <QElapsedTimer>
#include <QMainWindow>
#include <QSerialPort>
#include <QTimer>

class QComboBox;
class QLabel;
class QPushButton;
class QTableWidget;
class TrendPlot;
class QJsonObject;

class MonitorWindow : public QMainWindow {
  Q_OBJECT

public:
  explicit MonitorWindow(bool demo = false, QWidget *parent = nullptr);
  bool connectPort(const QString &port);
  quint64 receivedCount() const { return received_; }
  QString receptionState() const;
  QJsonObject sessionReport() const;
  bool writeCsv(const QString &path, QString *error) const;

private:
  friend class MonitorTest;
  void buildUi();
  void refreshPorts();
  void disconnectPort(const QString &reason, bool failure = false);
  void consume(const QByteArray &bytes, const QString &source);
  void acceptSample(SensorSample sample);
  void refreshStatus();
  void addEvent(const QString &message, bool warning = false);
  void saveCsv();
  void produceDemo();

  QSerialPort serial_;
  RecordDecoder decoder_;
  QElapsedTimer clock_;
  QTimer refreshTimer_;
  QTimer demoTimer_;
  std::deque<SensorSample> history_;
  qint64 lastRecordMs_ = -1;
  qint64 connectedAtMs_ = -1;
  qint64 lastErrorEventMs_ = -1000;
  quint64 received_ = 0;
  quint64 announcedRejected_ = 0;
  bool demo_ = false;
  bool opening_ = false;
  bool closing_ = false;
  bool nextBreak_ = true;
  bool transportFault_ = false;
  quint64 rejectedBeforeConnection_ = 0;
  QString previousState_;
  QString previousDeviceState_;
  QString transportMessage_;
  QComboBox *ports_ = nullptr;
  QPushButton *refresh_ = nullptr;
  QPushButton *connect_ = nullptr;
  QPushButton *export_ = nullptr;
  QLabel *banner_ = nullptr;
  QLabel *connection_ = nullptr;
  QLabel *spiStatus_ = nullptr;
  QLabel *oledStatus_ = nullptr;
  QLabel *counts_ = nullptr;
  QLabel *lastUpdate_ = nullptr;
  QLabel *raw_ = nullptr;
  QLabel *values_[3] = {};
  QLabel *notes_[3] = {};
  QTableWidget *events_ = nullptr;
  TrendPlot *plot_ = nullptr;
};
