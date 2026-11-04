#include "monitor_window.h"
#include "trend_plot.h"

#include <QButtonGroup>
#include <QComboBox>
#include <QFileDialog>
#include <QFrame>
#include <QHeaderView>
#include <QHBoxLayout>
#include <QLabel>
#include <QJsonObject>
#include <QMessageBox>
#include <QPushButton>
#include <QSerialPortInfo>
#include <QTableWidget>
#include <QVBoxLayout>
#include <cmath>

namespace {
constexpr int HistoryLimit = 18000;
constexpr qint64 ReceptionTimeoutMs = 1000;

QLabel *label(const QString &text, const char *name, QWidget *parent = nullptr) {
  auto *widget = new QLabel(text, parent);
  widget->setObjectName(QString::fromLatin1(name));
  return widget;
}

void setTone(QLabel *widget, const QString &text, const QString &color) {
  widget->setText(text);
  widget->setStyleSheet(QString("color: %1;").arg(color));
}
}

MonitorWindow::MonitorWindow(bool demo, QWidget *parent) : QMainWindow(parent), demo_(demo) {
  clock_.start();
  buildUi();
  refreshPorts();
  serial_.setReadBufferSize(65536);
  QObject::connect(&serial_, &QSerialPort::readyRead, this, [this] {
    consume(serial_.readAll(), serial_.portName());
  });
  QObject::connect(&serial_, &QSerialPort::errorOccurred, this, [this](QSerialPort::SerialPortError error) {
    if (error == QSerialPort::NoError || opening_ || closing_) {
      return;
    }
    if (serial_.isOpen()) {
      disconnectPort(QStringLiteral("연결 오류 · ") + serial_.errorString());
    }
  });
  refreshTimer_.setInterval(250);
  QObject::connect(&refreshTimer_, &QTimer::timeout, this, &MonitorWindow::refreshStatus);
  refreshTimer_.start();
  if (demo_) {
    demoTimer_.setInterval(100);
    QObject::connect(&demoTimer_, &QTimer::timeout, this, &MonitorWindow::produceDemo);
    demoTimer_.start();
    addEvent(QStringLiteral("미리보기 시작 · 생성 데이터이며 실측값이 아닙니다"), true);
    produceDemo();
  } else {
    addEvent(QStringLiteral("Master USB 포트를 선택해 연결하세요"));
  }
  refreshStatus();
}

void MonitorWindow::buildUi() {
  setWindowTitle(QStringLiteral("Sensor Desk · FPGA Monitor"));
  resize(1220, 850);
  setMinimumSize(980, 760);
  setStyleSheet(QStringLiteral(R"(
    QMainWindow, QWidget#canvas { background: #f3f4ef; color: #253b32; }
    QWidget { font-family: 'Malgun Gothic'; font-size: 12px; color: #253b32; }
    QLabel#eyebrow { color: #718077; font-size: 11px; font-weight: 600; }
    QLabel#title { font-family: 'Segoe UI'; font-size: 32px; font-weight: 600; }
    QLabel#subtitle, QLabel#muted { color: #768079; }
    QLabel#section { font-size: 16px; font-weight: 600; }
    QLabel#metric { font-family: 'Segoe UI'; font-size: 44px; font-weight: 600; }
    QLabel#unit { color: #79847d; font-family: 'Segoe UI'; font-size: 16px; }
    QLabel#raw { color: #68776e; font-family: 'Consolas'; font-size: 11px; }
    QLabel#banner { background: #f6edd8; color: #816433; padding: 9px 14px; border-radius: 5px; }
    QFrame#panel { background: #ffffff; border: 1px solid #dfe5dd; border-radius: 8px; }
    QFrame#divider { background: #e5e9e2; border: none; }
    QPushButton { background: #fff; border: 1px solid #d7dfd6; border-radius: 5px; padding: 8px 15px; }
    QPushButton:hover { background: #e9eee7; border-color: #a3b4a4; }
    QPushButton:pressed { background: #dce6da; }
    QPushButton:disabled { color: #a8afa8; background: #f4f5f1; border-color: #e2e6df; }
    QPushButton#primary { color: #fff; background: #285e4c; border-color: #285e4c; font-weight: 600; }
    QPushButton#primary:hover { background: #214f40; }
    QPushButton#primary:disabled { background: #b1beb2; border-color: #b1beb2; }
    QPushButton#tab { border: none; color: #7c857e; padding: 7px 15px; background: transparent; }
    QPushButton#tab:checked { color: #285e4c; background: #e9f0e7; font-weight: 600; }
    QComboBox { border: 1px solid #d7dfd6; border-radius: 5px; background: #fff; padding: 8px 12px; }
    QComboBox::drop-down { border: none; width: 22px; }
    QComboBox QAbstractItemView { background: white; selection-background-color: #e1ece0; selection-color: #253b32; }
    QTableWidget { background: transparent; border: none; gridline-color: #edf0eb; selection-background-color: #edf2ea; selection-color: #253b32; }
    QHeaderView::section { background: #fff; color: #839087; border: none; border-bottom: 1px solid #e5e9e2; padding: 6px 0; font-size: 11px; }
    QScrollBar:vertical { background: #f4f5f1; width: 7px; }
    QScrollBar::handle:vertical { background: #c8d3c6; min-height: 24px; border-radius: 3px; }
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
  )"));
  auto *canvas = new QWidget(this);
  canvas->setObjectName("canvas");
  setCentralWidget(canvas);
  auto *root = new QVBoxLayout(canvas);
  root->setContentsMargins(26, 22, 26, 16);
  root->setSpacing(14);

  auto *header = new QHBoxLayout;
  auto *title = new QVBoxLayout;
  title->setSpacing(3);
  title->addWidget(label(QStringLiteral("FPGA / SENSOR MONITORING"), "eyebrow"));
  title->addWidget(label(QStringLiteral("Sensor Desk"), "title"));
  title->addWidget(label(QStringLiteral("온도, 습도, 거리의 변화를 한곳에서."), "subtitle"));
  header->addLayout(title);
  header->addStretch();
  auto *controls = new QVBoxLayout;
  auto *portRow = new QHBoxLayout;
  ports_ = new QComboBox;
  ports_->setObjectName("portSelector");
  ports_->setMinimumWidth(205);
  ports_->setToolTip(QStringLiteral("Master 보드의 USB-UART 포트 · 115200 / 8N1"));
  refresh_ = new QPushButton(QStringLiteral("새로고침"));
  connect_ = new QPushButton(QStringLiteral("연결"));
  connect_->setObjectName("primary");
  portRow->addWidget(ports_);
  portRow->addWidget(refresh_);
  portRow->addWidget(connect_);
  controls->addLayout(portRow);
  connection_ = label(QStringLiteral("●  연결 안 됨"), "connection");
  connection_->setAlignment(Qt::AlignRight);
  controls->addWidget(connection_);
  header->addLayout(controls);
  root->addLayout(header);

  banner_ = label(QStringLiteral("미리보기 모드 · 생성 데이터 / 실제 센서 측정값이 아닙니다"), "banner");
  banner_->setVisible(demo_);
  root->addWidget(banner_);

  auto *metrics = new QFrame;
  metrics->setObjectName("panel");
  auto *metricsRow = new QHBoxLayout(metrics);
  metricsRow->setContentsMargins(25, 19, 25, 19);
  metricsRow->setSpacing(25);
  const QString names[] = {QStringLiteral("온도"), QStringLiteral("습도"), QStringLiteral("거리")};
  const QString units[] = {QStringLiteral("°C"), QStringLiteral("% RH"), QStringLiteral("cm")};
  const QString ids[] = {"temperatureValue", "humidityValue", "distanceValue"};
  for (int i = 0; i < 3; ++i) {
    if (i) {
      auto *divider = new QFrame;
      divider->setObjectName("divider");
      divider->setFixedWidth(1);
      metricsRow->addWidget(divider);
    }
    auto *column = new QVBoxLayout;
    column->setSpacing(3);
    column->addWidget(label(QString("0%1  /  %2").arg(i + 1).arg(names[i]), "eyebrow"));
    auto *valueRow = new QHBoxLayout;
    values_[i] = label(QStringLiteral("—"), "metric");
    values_[i]->setProperty("testId", ids[i]);
    valueRow->addWidget(values_[i]);
    valueRow->addWidget(label(units[i], "unit"), 0, Qt::AlignBottom);
    valueRow->addStretch();
    column->addLayout(valueRow);
    notes_[i] = label(QStringLiteral("수신 대기"), "muted");
    column->addWidget(notes_[i]);
    metricsRow->addLayout(column, 1);
  }
  root->addWidget(metrics);

  auto *chartPanel = new QFrame;
  chartPanel->setObjectName("panel");
  auto *chartColumn = new QVBoxLayout(chartPanel);
  chartColumn->setContentsMargins(22, 18, 22, 9);
  auto *chartHeader = new QHBoxLayout;
  chartHeader->addWidget(label(QStringLiteral("실시간 추이"), "section"));
  chartHeader->addSpacing(22);
  auto *channels = new QButtonGroup(this);
  channels->setExclusive(true);
  for (int i = 0; i < 3; ++i) {
    auto *tab = new QPushButton(names[i]);
    tab->setObjectName("tab");
    tab->setCheckable(true);
    tab->setChecked(i == 0);
    channels->addButton(tab, i);
    chartHeader->addWidget(tab);
  }
  chartHeader->addStretch();
  auto *window = new QComboBox;
  window->setObjectName("timeWindow");
  window->addItem(QStringLiteral("최근 1분"), 60);
  window->addItem(QStringLiteral("최근 5분"), 300);
  window->addItem(QStringLiteral("최근 15분"), 900);
  chartHeader->addWidget(window);
  chartColumn->addLayout(chartHeader);
  plot_ = new TrendPlot;
  plot_->setSamples(&history_);
  chartColumn->addWidget(plot_, 1);
  root->addWidget(chartPanel, 1);
  QObject::connect(channels, &QButtonGroup::idClicked, plot_, &TrendPlot::setChannel);
  QObject::connect(window, &QComboBox::currentIndexChanged, this, [this, window] {
    plot_->setWindow(window->currentData().toInt());
  });

  auto *bottom = new QHBoxLayout;
  auto *statusPanel = new QFrame;
  statusPanel->setObjectName("panel");
  auto *status = new QVBoxLayout(statusPanel);
  status->setContentsMargins(22, 18, 22, 18);
  status->addWidget(label(QStringLiteral("장치 상태"), "section"));
  spiStatus_ = label(QStringLiteral("SPI   —"), "spiStatus");
  oledStatus_ = label(QStringLiteral("OLED   —"), "oledStatus");
  status->addWidget(spiStatus_);
  status->addWidget(oledStatus_);
  lastUpdate_ = label(QStringLiteral("마지막 수신  —"), "muted");
  status->addWidget(lastUpdate_);
  status->addStretch();
  bottom->addWidget(statusPanel, 1);
  auto *eventPanel = new QFrame;
  eventPanel->setObjectName("panel");
  auto *eventColumn = new QVBoxLayout(eventPanel);
  eventColumn->setContentsMargins(22, 18, 22, 12);
  auto *eventHeader = new QHBoxLayout;
  eventHeader->addWidget(label(QStringLiteral("상태 기록"), "section"));
  eventHeader->addStretch();
  export_ = new QPushButton(QStringLiteral("CSV 저장"));
  eventHeader->addWidget(export_);
  eventColumn->addLayout(eventHeader);
  events_ = new QTableWidget(0, 2);
  events_->setObjectName("eventLog");
  events_->setHorizontalHeaderLabels({QStringLiteral("시간"), QStringLiteral("내용")});
  events_->horizontalHeader()->setDefaultAlignment(Qt::AlignLeft | Qt::AlignVCenter);
  events_->horizontalHeader()->setSectionResizeMode(0, QHeaderView::Fixed);
  events_->horizontalHeader()->setSectionResizeMode(1, QHeaderView::Stretch);
  events_->setColumnWidth(0, 85);
  events_->verticalHeader()->hide();
  events_->setEditTriggers(QAbstractItemView::NoEditTriggers);
  events_->setSelectionBehavior(QAbstractItemView::SelectRows);
  events_->setFocusPolicy(Qt::NoFocus);
  events_->setShowGrid(false);
  events_->setFixedHeight(100);
  events_->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
  eventColumn->addWidget(events_);
  bottom->addWidget(eventPanel, 2);
  root->addLayout(bottom);

  auto *footer = new QHBoxLayout;
  counts_ = label(QString(), "muted");
  raw_ = label(QStringLiteral("115200 baud  /  8N1  /  USB-UART"), "raw");
  raw_->setTextInteractionFlags(Qt::TextSelectableByMouse);
  footer->addWidget(counts_);
  footer->addStretch();
  footer->addWidget(raw_);
  root->addLayout(footer);
  QObject::connect(refresh_, &QPushButton::clicked, this, &MonitorWindow::refreshPorts);
  QObject::connect(connect_, &QPushButton::clicked, this, [this] {
    if (serial_.isOpen()) {
      disconnectPort(QStringLiteral("사용자가 연결을 해제했습니다"));
    } else {
      connectPort(ports_->currentData().toString());
    }
  });
  QObject::connect(export_, &QPushButton::clicked, this, &MonitorWindow::saveCsv);
}

void MonitorWindow::refreshPorts() {
  const auto selected = ports_->currentData().toString();
  ports_->clear();
  for (const auto &port : QSerialPortInfo::availablePorts()) {
    const QString description = port.description().isEmpty() ? QStringLiteral("Serial port") : port.description();
    ports_->addItem(port.portName() + " · " + description, port.portName());
    ports_->setItemData(ports_->count() - 1, port.serialNumber(), Qt::ToolTipRole);
  }
  const int index = ports_->findData(selected);
  if (index >= 0) {
    ports_->setCurrentIndex(index);
  }
  if (ports_->count() == 0) {
    ports_->addItem(QStringLiteral("연결 가능한 포트 없음"), QString());
  }
  connect_->setEnabled(!demo_ && !ports_->currentData().toString().isEmpty());
}

bool MonitorWindow::connectPort(const QString &port) {
  if (demo_ || serial_.isOpen() || port.isEmpty()) {
    return false;
  }
  const int index = ports_->findData(port);
  if (index >= 0) {
    ports_->setCurrentIndex(index);
  }
  rejectedBeforeConnection_ += decoder_.rejected();
  decoder_.reset();
  nextBreak_ = true;
  lastRecordMs_ = -1;
  previousDeviceState_.clear();
  serial_.setPortName(port);
  serial_.setBaudRate(QSerialPort::Baud115200);
  serial_.setDataBits(QSerialPort::Data8);
  serial_.setParity(QSerialPort::NoParity);
  serial_.setStopBits(QSerialPort::OneStop);
  serial_.setFlowControl(QSerialPort::NoFlowControl);
  opening_ = true;
  const bool opened = serial_.open(QIODevice::ReadOnly);
  opening_ = false;
  if (!opened) {
    transportMessage_ = port + QStringLiteral(" 연결 실패 · ") + serial_.errorString();
    addEvent(transportMessage_, true);
    refreshStatus();
    return false;
  }
  transportMessage_.clear();
  addEvent(port + QStringLiteral(" 연결 · 115200 / 8N1"));
  refreshStatus();
  return true;
}

void MonitorWindow::disconnectPort(const QString &reason) {
  closing_ = true;
  serial_.close();
  closing_ = false;
  lastRecordMs_ = -1;
  // 빠르게 재연결해도 이전 구간과 그래프를 이어 그리지 않는다.
  nextBreak_ = true;
  transportMessage_ = reason;
  addEvent(reason, true);
  refreshStatus();
}

void MonitorWindow::consume(const QByteArray &bytes, const QString &source) {
  const quint64 before = decoder_.rejected();
  const auto samples = decoder_.feed(bytes);
  if (decoder_.rejected() != before) {
    addEvent(QStringLiteral("UART 형식 오류 · %1줄 제외").arg(decoder_.rejected() - before), true);
  }
  for (auto sample : samples) {
    sample.receivedAt = QDateTime::currentDateTimeUtc();
    sample.elapsedMs = clock_.elapsed();
    sample.source = source;
    acceptSample(sample);
  }
  refreshStatus();
}

void MonitorWindow::acceptSample(SensorSample sample) {
  sample.breakBefore = nextBreak_;
  nextBreak_ = false;
  lastRecordMs_ = sample.elapsedMs;
  ++received_;
  const QString deviceState = sample.link + (sample.oledOk ? "/OK" : "/ERR")
      + (sample.temperature ? "/DHT" : "/--") + (sample.distance ? "/DIST" : "/--");
  if (deviceState != previousDeviceState_) {
    addEvent(QString("SPI %1 · OLED %2 · 온습도 %3 · 거리 %4")
                 .arg(sample.link, sample.oledOk ? "OK" : "ERR",
                      sample.temperature ? QStringLiteral("수신") : QStringLiteral("미준비"),
                      sample.distance ? QStringLiteral("수신") : QStringLiteral("미준비")),
             sample.link != "OK" || !sample.oledOk);
    previousDeviceState_ = deviceState;
  }
  history_.push_back(std::move(sample));
  if (history_.size() > HistoryLimit) {
    history_.pop_front();
  }
}

QString MonitorWindow::receptionState() const {
  if (!demo_ && !serial_.isOpen()) {
    return QStringLiteral("연결 안 됨");
  }
  if (lastRecordMs_ < 0) {
    return QStringLiteral("수신 대기");
  }
  if (clock_.elapsed() - lastRecordMs_ >= ReceptionTimeoutMs) {
    return QStringLiteral("수신 중단");
  }
  return demo_ ? QStringLiteral("미리보기") : QStringLiteral("수신 중");
}

void MonitorWindow::refreshStatus() {
  const QString state = receptionState();
  const bool fresh = lastRecordMs_ >= 0 && clock_.elapsed() - lastRecordMs_ < ReceptionTimeoutMs
      && (demo_ || serial_.isOpen());
  if (state != previousState_) {
    if (state == QStringLiteral("수신 중단") || (state == QStringLiteral("수신 중") && previousState_ == QStringLiteral("수신 중단"))) {
      addEvent(state == QStringLiteral("수신 중단") ? QStringLiteral("PC 수신 중단 · 정상 형식의 줄이 1초 이상 도착하지 않음")
                                                  : QStringLiteral("PC 수신 복구"), !fresh);
    }
    previousState_ = state;
  }
  setTone(connection_, "●  " + state + ((!demo_ && serial_.isOpen()) ? " · " + serial_.portName() : ""),
          fresh && !demo_ ? "#28715b" : "#93713c");
  connection_->setToolTip(transportMessage_);
  ports_->setEnabled(!demo_ && !serial_.isOpen());
  refresh_->setEnabled(!demo_ && !serial_.isOpen());
  connect_->setText(serial_.isOpen() ? QStringLiteral("연결 해제") : QStringLiteral("연결"));
  connect_->setEnabled(!demo_ && (serial_.isOpen() || !ports_->currentData().toString().isEmpty()));
  export_->setEnabled(!history_.empty());
  const SensorSample *sample = fresh && !history_.empty() ? &history_.back() : nullptr;
  for (int i = 0; i < 3; ++i) {
    const auto value = sample && sample->link == "OK"
        ? (i == 0 ? sample->temperature : i == 1 ? sample->humidity : sample->distance)
        : std::optional<double>();
    values_[i]->setText(value ? QString::number(*value, 'f', i == 2 ? 0 : 1) : QStringLiteral("—"));
    notes_[i]->setText(!sample ? state : sample->link != "OK" ? QStringLiteral("SPI 오류로 무효")
                      : !value ? QStringLiteral("센서 미준비 / 유효하지 않음")
                      : demo_ ? QStringLiteral("생성 데이터") : QStringLiteral("정상 수신"));
  }
  setTone(spiStatus_, sample ? "SPI   " + sample->link : QStringLiteral("SPI   확인 대기"),
          sample && sample->link == "OK" ? "#28715b" : "#93713c");
  setTone(oledStatus_, sample ? (sample->oledOk ? "OLED   OK" : "OLED   ERR") : QStringLiteral("OLED   확인 대기"),
          sample && sample->oledOk ? "#28715b" : "#93713c");
  if (lastRecordMs_ >= 0) {
    lastUpdate_->setText(QStringLiteral("마지막 수신  %1초 전").arg((clock_.elapsed() - lastRecordMs_) / 1000.0, 0, 'f', 1));
  } else {
    lastUpdate_->setText(QStringLiteral("마지막 수신  —"));
  }
  counts_->setText(QStringLiteral("수신 %1  ·  형식 오류 %2  ·  보관 %3 / 18,000")
                       .arg(received_).arg(rejectedBeforeConnection_ + decoder_.rejected()).arg(history_.size()));
  if (sample) {
    raw_->setText(QString::fromLatin1(sample->raw));
  } else {
    raw_->setText(QStringLiteral("115200 baud  /  8N1  /  USB-UART"));
  }
  plot_->setNow(clock_.elapsed());
}

void MonitorWindow::addEvent(const QString &message, bool warning) {
  events_->insertRow(0);
  auto *time = new QTableWidgetItem(QDateTime::currentDateTime().toString("HH:mm:ss"));
  time->setForeground(QColor("#849087"));
  events_->setItem(0, 0, time);
  auto *text = new QTableWidgetItem(message);
  text->setToolTip(message);
  text->setForeground(QColor(warning ? "#94723c" : "#385344"));
  events_->setItem(0, 1, text);
  events_->setRowHeight(0, 27);
  if (events_->rowCount() > 200) {
    events_->removeRow(200);
  }
}

void MonitorWindow::saveCsv() {
  const auto path = QFileDialog::getSaveFileName(this, QStringLiteral("수신 기록 저장"),
      QString("sensor_%1%2.csv").arg(demo_ ? "DEMO_" : "").arg(QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss")),
      QStringLiteral("CSV (*.csv)"));
  if (path.isEmpty()) {
    return;
  }
  QString error;
  if (!writeCsv(path, &error)) {
    QMessageBox::warning(this, QStringLiteral("저장 실패"), error);
    addEvent(QStringLiteral("CSV 저장 실패 · ") + error, true);
    return;
  }
  addEvent(QStringLiteral("CSV 저장 · %1개 수신 기록").arg(history_.size()));
}

bool MonitorWindow::writeCsv(const QString &path, QString *error) const {
  if (history_.empty()) {
    *error = QStringLiteral("저장할 수신 기록이 없습니다.");
    return false;
  }
  return exportCsv(path, history_, error);
}

QJsonObject MonitorWindow::sessionReport() const {
  QJsonObject report{{"records", static_cast<qint64>(received_)},
                     {"rejected", static_cast<qint64>(rejectedBeforeConnection_ + decoder_.rejected())},
                     {"retained", static_cast<qint64>(history_.size())},
                     {"state", receptionState()}, {"demo", demo_}};
  if (!history_.empty()) {
    const auto &sample = history_.back();
    report.insert("last_raw", QString::fromLatin1(sample.raw));
    report.insert("last_source", sample.source);
    report.insert("last_received_utc", sample.receivedAt.toUTC().toString(Qt::ISODateWithMs));
  }
  return report;
}

void MonitorWindow::produceDemo() {
  const double seconds = clock_.elapsed() / 1000.0;
  const auto line = QString("T=%1C H=%2% D=%3cm L=OK O=OK\r\n")
      .arg(24.0 + 1.2 * std::sin(seconds / 8), 0, 'f', 1)
      .arg(53.0 + 3.0 * std::sin(seconds / 11), 0, 'f', 1)
      .arg(qRound(24 + 4 * std::sin(seconds / 5)));
  consume(line.toLatin1(), QStringLiteral("DEMO"));
}
