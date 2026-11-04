#include "protocol.h"
#include "monitor_window.h"
#include "trend_plot.h"

#include <QComboBox>
#include <QFile>
#include <QLabel>
#include <QPushButton>
#include <QTemporaryDir>
#include <QTableWidget>
#include <QTest>

class MonitorTest : public QObject {
  Q_OBJECT

private slots:
  void vectors_data() {
    QTest::addColumn<QByteArray>("line");
    QTest::addColumn<bool>("accepted");
    QTest::newRow("golden-positive") << QByteArray("T=23.5C H=60.0% D=291cm L=OK O=OK") << true;
    QTest::newRow("golden-negative") << QByteArray("T=-5.5C H=45.2% D=123cm L=OK O=OK") << true;
    QTest::newRow("invalid-sensors") << QByteArray("T=--C H=--% D=--cm L=OK O=ERR") << true;
    QTest::newRow("header-error") << QByteArray("T=--C H=--% D=--cm L=ERR:HEADER O=OK") << true;
    QTest::newRow("range-low") << QByteArray("T=-20.0C H=0.0% D=2cm L=OK O=OK") << true;
    QTest::newRow("range-high") << QByteArray("T=60.0C H=100.0% D=400cm L=OK O=OK") << true;
    QTest::newRow("integer-sensor") << QByteArray("T=23.0C H=53.0% D=20cm L=OK O=OK") << true;
    QTest::newRow("temperature-range") << QByteArray("T=60.1C H=50.0% D=20cm L=OK O=OK") << false;
    QTest::newRow("humidity-range") << QByteArray("T=20.0C H=100.1% D=20cm L=OK O=OK") << false;
    QTest::newRow("distance-range") << QByteArray("T=20.0C H=50.0% D=401cm L=OK O=OK") << false;
    QTest::newRow("distance-zero") << QByteArray("T=20.0C H=50.0% D=0cm L=OK O=OK") << false;
    QTest::newRow("dht-valid-pair") << QByteArray("T=--C H=50.0% D=20cm L=OK O=OK") << false;
    QTest::newRow("unknown-reason") << QByteArray("T=--C H=--% D=--cm L=ERR:OTHER O=OK") << false;
    QTest::newRow("tail-garbage") << QByteArray("T=20.0C H=50.0% D=20cm L=OK O=OK X") << false;
    QTest::newRow("bad-precision") << QByteArray("T=20.00C H=50.0% D=20cm L=OK O=OK") << false;
  }

  void vectors() {
    QFETCH(QByteArray, line);
    QFETCH(bool, accepted);
    QCOMPARE(parseRecord(line).has_value(), accepted);
  }

  void decodedValues() {
    const auto sample = parseRecord("T=-5.5C H=45.2% D=123cm L=OK O=ERR");
    QVERIFY(sample);
    QCOMPARE(*sample->temperature, -5.5);
    QCOMPARE(*sample->humidity, 45.2);
    QCOMPARE(*sample->distance, 123.0);
    QVERIFY(!sample->oledOk);
    const auto invalid = parseRecord("T=--C H=--% D=--cm L=ERR:STALE O=OK");
    QVERIFY(invalid);
    QVERIFY(!invalid->temperature && !invalid->humidity && !invalid->distance);
  }

  void errorReasons() {
    for (const auto &reason : {"NONE", "TIMEOUT", "LENGTH", "HEADER", "XOR", "RESERVED", "RANGE", "STALE"}) {
      QVERIFY(parseRecord(QByteArray("T=--C H=--% D=--cm L=ERR:") + reason + " O=OK"));
    }
  }

  void everySplit() {
    const QByteArray record("T=-5.5C H=45.2% D=123cm L=OK O=OK\r\n");
    for (qsizetype split = 0; split <= record.size(); ++split) {
      RecordDecoder decoder;
      const auto first = decoder.feed(record.left(split));
      const auto second = decoder.feed(record.mid(split));
      QCOMPARE(first.size() + second.size(), 1);
      QCOMPARE(decoder.rejected(), quint64(0));
    }
  }

  void noiseAndRecovery() {
    RecordDecoder decoder;
    const QByteArray record("T=23.0C H=53.0% D=20cm L=OK O=OK\r\n");
    QCOMPARE(decoder.feed("middle of record\r\n\r\n" + record + record).size(), 2);
    QCOMPARE(decoder.rejected(), quint64(1));
    QVERIFY(decoder.feed(QByteArray(1024 * 1024, 'x')).isEmpty());
    QCOMPARE(decoder.rejected(), quint64(2));
    QCOMPARE(decoder.feed("still noise\n" + record).size(), 1);
    decoder.feed(record.left(13));
    decoder.reset();
    QCOMPARE(decoder.feed(record).size(), 1);
    QCOMPARE(decoder.rejected(), quint64(0));
  }

  void csvExport() {
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    auto sample = *parseRecord("T=23.0C H=53.0% D=--cm L=OK O=ERR");
    sample.receivedAt = QDateTime::fromString("2026-11-05T01:02:03.456Z", Qt::ISODateWithMs);
    sample.source = "COM4";
    QString error;
    const QString path = dir.filePath("sample.csv");
    QVERIFY(exportCsv(path, {sample}, &error));
    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly));
    const auto csv = file.readAll();
    QVERIFY(csv.contains("2026-11-05T01:02:03.456Z,\"COM4\",23.0,53.0,,OK,ERR\n"));
    QVERIFY(!exportCsv(dir.filePath("missing/sample.csv"), {sample}, &error));
    QVERIFY(!error.isEmpty());
  }

  void demoWidgets() {
    MonitorWindow window(true);
    window.show();
    QTRY_VERIFY(window.receivedCount() >= 2);
    QCOMPARE(window.receptionState(), QStringLiteral("미리보기"));
    QVERIFY(!window.findChild<QComboBox *>("portSelector")->isEnabled());
    QVERIFY(!window.findChild<QPushButton *>("primary")->isEnabled());
    const auto labels = window.findChildren<QLabel *>("metric");
    QCOMPARE(labels.size(), 3);
    for (const auto *value : labels) {
      QVERIFY(value->text() != QStringLiteral("—"));
    }
    for (auto *button : window.findChildren<QPushButton *>("tab")) {
      button->click();
    }
    window.findChild<QComboBox *>("timeWindow")->setCurrentIndex(2);
    window.resize(980, 760);
    QVERIFY(!window.grab().isNull());
  }

  void unavailablePort() {
    MonitorWindow window;
    QVERIFY(!window.connectPort("NONEXISTENT_FPGA_PORT"));
    QCOMPARE(window.receptionState(), QStringLiteral("연결 안 됨"));
    QCOMPARE(window.receivedCount(), quint64(0));
  }

  void freshnessAndRecovery() {
    MonitorWindow window(true);
    window.demoTimer_.stop();
    const QByteArray line("T=23.0C H=53.0% D=20cm L=OK O=OK\r\n");
    window.consume(line, "TEST");
    QCOMPARE(window.values_[0]->text(), QStringLiteral("23.0"));
    QTest::qWait(1010);
    window.refreshStatus();
    QCOMPARE(window.receptionState(), QStringLiteral("수신 중단"));
    QCOMPARE(window.values_[0]->text(), QStringLiteral("—"));
    QVERIFY(!window.spiStatus_->text().contains("OK"));
    window.consume("noise\r\n", "TEST");
    QCOMPARE(window.receptionState(), QStringLiteral("수신 중단"));
    window.consume(line, "TEST");
    QCOMPARE(window.receptionState(), QStringLiteral("미리보기"));
    QCOMPARE(window.values_[0]->text(), QStringLiteral("23.0"));
    window.consume("T=--C H=--% D=--cm L=ERR:HEADER O=ERR\r\n", "TEST");
    QCOMPARE(window.values_[0]->text(), QStringLiteral("—"));
    QVERIFY(window.spiStatus_->text().contains("HEADER"));
    QVERIFY(window.oledStatus_->text().contains("ERR"));
    window.disconnectPort(QStringLiteral("시험 해제"));
    window.demo_ = false;
    window.refreshStatus();
    QCOMPARE(window.receptionState(), QStringLiteral("연결 안 됨"));
    QCOMPARE(window.values_[2]->text(), QStringLiteral("—"));
    window.demo_ = true;
    window.consume(line, "TEST");
    QVERIFY(window.history_.back().breakBefore);
  }

  void boundedHistory() {
    MonitorWindow window(true);
    window.demoTimer_.stop();
    auto sample = *parseRecord("T=23.0C H=53.0% D=20cm L=OK O=OK");
    for (int i = 0; i < 18010; ++i) {
      sample.elapsedMs = i;
      window.acceptSample(sample);
    }
    QCOMPARE(window.history_.size(), size_t(18000));
    QCOMPARE(window.history_.front().elapsedMs, qint64(10));
    QVERIFY(window.events_->rowCount() <= 200);
  }

  void layoutFits() {
    MonitorWindow window(true);
    window.show();
    for (const QSize size : {QSize(1220, 850), QSize(980, 760)}) {
      window.resize(size);
      QTest::qWait(30);
      const auto widgets = window.findChildren<QWidget *>();
      for (auto *widget : widgets) {
        if (widget->isVisible() && !widget->isWindow() && widget->parentWidget()
            && (qobject_cast<QLabel *>(widget) || widget == window.plot_)) {
          const auto *parent = widget->parentWidget();
          const QString detail = QString("%1 %2 rect=%3,%4,%5,%6 parent=%7x%8 window=%9x%10")
              .arg(widget->metaObject()->className(), widget->objectName())
              .arg(widget->x()).arg(widget->y()).arg(widget->width()).arg(widget->height())
              .arg(parent->width()).arg(parent->height()).arg(window.width()).arg(window.height());
          QVERIFY2(widget->geometry().bottom() < parent->height(), qPrintable(detail));
          QVERIFY2(widget->geometry().right() < parent->width(), qPrintable(detail));
        }
      }
    }
  }
};

QTEST_MAIN(MonitorTest)
#include "test_monitor.moc"
