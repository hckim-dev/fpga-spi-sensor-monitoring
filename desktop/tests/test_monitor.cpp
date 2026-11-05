#include "protocol.h"
#include "monitor_window.h"
#include "trend_plot.h"

#include <QComboBox>
#include <QFile>
#include <QFileDialog>
#include <QDir>
#include <QApplication>
#include <QLabel>
#include <QPushButton>
#include <QPixmap>
#include <QTemporaryDir>
#include <QTableWidget>
#include <QScrollArea>
#include <QScrollBar>
#include <QToolButton>
#include <QTest>

class MonitorTest : public QObject {
  Q_OBJECT

private slots:
  void initTestCase() {
    QApplication::setAttribute(Qt::AA_DontUseNativeDialogs);
    QVERIFY(!QPixmap(":/icons/chevron.xpm").isNull());
    QVERIFY(QDir().mkpath(QCoreApplication::applicationDirPath() + "/../screens"));
  }

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
    QTest::newRow("link-error-with-values") << QByteArray("T=20.0C H=50.0% D=20cm L=ERR:XOR O=OK") << false;
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
    QVERIFY(csv.contains("2026-11-05T01:02:03.456Z,\"COM4\",23.0,53.0,,OK,ERR,0\n"));
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
    window.refreshStatus();
    QCOMPARE(window.values_[0]->text(), QStringLiteral("23.0"));
    QVERIFY(window.values_[0]->accessibleName().contains(QStringLiteral("온도 23.0 °C")));
    QTest::qWait(1010);
    window.refreshStatus();
    QCOMPARE(window.receptionState(), QStringLiteral("수신 중단"));
    QCOMPARE(window.values_[0]->text(), QStringLiteral("—"));
    QVERIFY(!window.spiStatus_->text().contains("OK"));
    window.consume("noise\r\n", "TEST");
    QCOMPARE(window.receptionState(), QStringLiteral("수신 중단"));
    window.consume(line, "TEST");
    window.refreshStatus();
    QCOMPARE(window.receptionState(), QStringLiteral("미리보기"));
    QCOMPARE(window.values_[0]->text(), QStringLiteral("23.0"));
    QVERIFY(window.history_.back().breakBefore);
    window.consume("T=--C H=--% D=--cm L=ERR:HEADER O=ERR\r\n", "TEST");
    window.refreshStatus();
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
    for (const QSize size : {QSize(1220, 850), QSize(980, 760), QSize(940, 600)}) {
      window.resize(size);
      QTest::qWait(30);
      auto *scroll = window.findChild<QScrollArea *>("workspace");
      if (size.height() >= 760) {
        QCOMPARE(scroll->verticalScrollBar()->maximum(), 0);
      }
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
          const auto *text = qobject_cast<QLabel *>(widget);
          if (text && !text->wordWrap()) {
            QVERIFY2(text->fontMetrics().horizontalAdvance(text->text()) <= text->contentsRect().width(), qPrintable(detail));
          }
        }
      }
      const auto path = QCoreApplication::applicationDirPath() + QString("/../screens/layout_%1x%2_%3.png")
          .arg(size.width()).arg(size.height()).arg(window.devicePixelRatioF());
      QVERIFY(window.grab().save(path));
    }
  }

  void decoderPreservesGaps() {
    RecordDecoder decoder;
    const QByteArray line("T=23.0C H=53.0% D=20cm L=OK O=OK\r\n");
    const auto samples = decoder.feed(line + line + "bad\r\n" + line + line);
    QCOMPARE(samples.size(), 4);
    QVERIFY(samples[0].breakBefore);
    QVERIFY(!samples[1].breakBefore);
    QVERIFY(samples[2].breakBefore);
    QVERIFY(!samples[3].breakBefore);
    decoder.feed(QByteArray(100, 'x'));
    const auto recovered = decoder.feed("\n" + line);
    QVERIFY(recovered[0].breakBefore);
  }

  void firstRecordTimeout() {
    MonitorWindow window(true);
    window.demoTimer_.stop();
    window.history_.clear();
    window.lastRecordMs_ = -1;
    window.connectedAtMs_ = window.clock_.elapsed();
    QCOMPARE(window.receptionState(), QStringLiteral("수신 대기"));
    QTest::qWait(1010);
    QCOMPARE(window.receptionState(), QStringLiteral("수신 없음"));
    window.consume("garbage\n", "TEST");
    QCOMPARE(window.receptionState(), QStringLiteral("수신 없음"));
    window.consume("T=23.0C H=53.0% D=20cm L=OK O=OK\r\n", "TEST");
    QCOMPARE(window.receptionState(), QStringLiteral("미리보기"));
  }

  void csvSnapshotWhileReceiving() {
    QTemporaryDir dir;
    const auto path = dir.filePath("snapshot.csv");
    MonitorWindow window;
    window.consume("T=23.0C H=53.0% D=20cm L=OK O=OK\r\n", "TEST");
    QTimer driver;
    bool accepted = false;
    QObject::connect(&driver, &QTimer::timeout, &window, [&] {
      auto *dialog = qobject_cast<QFileDialog *>(QApplication::activeModalWidget());
      if (dialog && !accepted) {
        accepted = true;
        window.consume("T=30.0C H=60.0% D=30cm L=OK O=OK\r\n", "TEST");
        dialog->selectFile(path);
        QMetaObject::invokeMethod(dialog, "accept", Qt::QueuedConnection);
      }
    });
    driver.start(20);
    QTimer::singleShot(3000, &window, [&] {
      if (auto *dialog = qobject_cast<QFileDialog *>(QApplication::activeModalWidget())) {
        dialog->reject();
      }
    });
    window.saveCsv();
    QVERIFY(accepted);
    QCOMPARE(window.history_.size(), size_t(2));
    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly));
    const auto data = file.readAll();
    QCOMPARE(data.count('\n'), 2);
    QVERIFY(data.contains(",23.0,53.0,20,OK,OK,1\n"));
    QVERIFY(!data.contains(",30.0,"));
  }

  void graphRangeAndGaps() {
    std::deque<SensorSample> history;
    auto sample = *parseRecord("T=-5.5C H=53.0% D=20cm L=OK O=OK");
    for (int i = 0; i < 8; ++i) {
      sample.elapsedMs = i * 100;
      sample.breakBefore = i == 3;
      sample.temperature = i == 5 ? std::optional<double>() : std::optional<double>(-5.5 + i * 0.1);
      history.push_back(sample);
    }
    TrendPlot plot;
    plot.setSamples(&history);
    plot.setNow(800);
    const auto [low, high] = plot.visibleRange();
    QVERIFY(low <= -5.5 && high >= -4.8);
    QVERIFY(high - low >= 4 && high - low <= 10);
    const auto path = plot.trace(QRectF(0, 0, 600, 300), low, high);
    int segments = 0;
    for (int i = 0; i < path.elementCount(); ++i) {
      if (path.elementAt(i).isMoveTo()) { ++segments; }
    }
    QCOMPARE(segments, 3);
    QPolygonF starts;
    plot.trace(QRectF(0, 0, 600, 300), low, high, &starts);
    QCOMPARE(starts.size(), 3);
    plot.setChannel(1);
    const auto humidity = plot.visibleRange();
    QVERIFY(humidity.first <= 53 && humidity.second >= 53);
    plot.setChannel(2);
    const auto distance = plot.visibleRange();
    QVERIFY(distance.first <= 20 && distance.second >= 20);
    plot.setWindow(0);
    QCOMPARE(plot.seconds_, 60);
    plot.setChannel(-1);
    QCOMPARE(plot.channel_, 2);
    plot.setNow(70000);
    QCOMPARE(plot.trace(QRectF(0, 0, 600, 300), 0, 100).elementCount(), 0);
    history.clear();
    sample.temperature = 23.0;
    sample.breakBefore = false;
    for (int i = 0; i < 4; ++i) {
      sample.elapsedMs = i * 2000;
      history.push_back(sample);
    }
    plot.setNow(7000);
    starts.clear();
    plot.trace(QRectF(0, 0, 600, 300), 0, 100, &starts);
    QCOMPARE(starts.size(), 4);
  }

  void largeCountersAndLongError() {
    MonitorWindow window;
    window.received_ = 18446744073709551615ULL;
    window.transportMessage_ = QStringLiteral("연결 실패 · ") + QStringLiteral("장치를 사용할 수 없습니다. ").repeated(10);
    window.transportFault_ = true;
    window.refreshStatus();
    window.show();
    window.resize(940, 600);
    window.findChild<QToolButton *>()->click();
    QTest::qWait(40);
    auto *scroll = window.findChild<QScrollArea *>("workspace");
    QVERIFY(scroll->verticalScrollBar()->maximum() > 0);
    QVERIFY(window.banner_->height() >= window.banner_->heightForWidth(window.banner_->width()));
    QVERIFY(window.counts_->height() >= window.counts_->heightForWidth(window.counts_->width()));
    QVERIFY(window.raw_->isVisible());
    QVERIFY(window.banner_->isVisible());
    QVERIFY(window.grab().save(QCoreApplication::applicationDirPath() + "/../screens/long_error.png"));
    scroll->ensureWidgetVisible(window.raw_);
    QVERIFY(scroll->verticalScrollBar()->value() > 0);
  }

  void stateScreens() {
    MonitorWindow window(true);
    window.demoTimer_.stop();
    window.show();
    const QByteArray frames[] = {
      "T=-5.5C H=100.0% D=400cm L=OK O=OK\r\n",
      "T=--C H=--% D=--cm L=OK O=ERR\r\n",
      "T=--C H=--% D=--cm L=ERR:HEADER O=OK\r\n"
    };
    for (int i = 0; i < 3; ++i) {
      window.consume(frames[i], "TEST");
      window.refreshStatus();
      QTest::qWait(30);
      const auto path = QCoreApplication::applicationDirPath() + QString("/../screens/state_%1.png").arg(i);
      QVERIFY(window.grab().save(path));
    }
  }

  void plotRenderingBenchmark() {
    std::deque<SensorSample> history;
    auto sample = *parseRecord("T=23.0C H=53.0% D=20cm L=OK O=OK");
    for (int i = 0; i < 18000; ++i) {
      sample.elapsedMs = i * 100;
      history.push_back(sample);
    }
    TrendPlot plot;
    plot.resize(1100, 280);
    plot.setSamples(&history);
    plot.setNow(1800000);
    QPixmap pixmap(plot.size());
    QBENCHMARK {
      plot.render(&pixmap);
    }
  }

  void fullCsvExport() {
    QTemporaryDir dir;
    std::deque<SensorSample> history;
    auto sample = *parseRecord("T=23.0C H=53.0% D=20cm L=OK O=OK");
    sample.receivedAt = QDateTime::currentDateTimeUtc();
    sample.source = "COM4";
    for (int i = 0; i < 18000; ++i) {
      history.push_back(sample);
    }
    const QString path = dir.filePath("full.csv");
    QElapsedTimer timer;
    timer.start();
    QString error;
    QVERIFY(exportCsv(path, history, &error));
    qInfo("CSV_EXPORT_BENCH records=18000 elapsed_ms=%lld", static_cast<long long>(timer.elapsed()));
    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly));
    QCOMPARE(file.readAll().count('\n'), 18001);
  }
};

QTEST_MAIN(MonitorTest)
#include "test_monitor.moc"
