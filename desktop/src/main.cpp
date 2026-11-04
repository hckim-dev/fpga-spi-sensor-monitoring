#include "monitor_window.h"

#include <QApplication>
#include <QCommandLineParser>
#include <QSaveFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QSerialPortInfo>
#include <QTextStream>
#include <QTimer>

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);
  app.setApplicationName("Sensor Desk");
  app.setOrganizationName("FPGA Sensor Monitor");
  app.setStyle("Fusion");
  QCommandLineParser parser;
  parser.setApplicationDescription(QStringLiteral("FPGA 센서 모니터 · UART 읽기 전용"));
  parser.addHelpOption();
  parser.addOption({"demo", QStringLiteral("실측과 분리된 생성 데이터 미리보기")});
  parser.addOption({"list-ports", QStringLiteral("사용 가능한 포트를 JSON으로 출력하고 종료")});
  parser.addOption({"port", QStringLiteral("시작할 때 연결할 Master 포트"), "port"});
  parser.addOption({"capture", QStringLiteral("화면을 PNG로 저장하고 종료"), "png"});
  parser.addOption({"seconds", QStringLiteral("Capture 또는 Capture Report까지의 대기 시간"), "seconds", "3"});
  parser.addOption({"report", QStringLiteral("자동 실행 결과를 JSON으로 저장하고 종료"), "json"});
  parser.addOption({"csv", QStringLiteral("보관된 수신 기록을 CSV로 저장하고 종료"), "csv"});
  parser.process(app);
  if (parser.isSet("list-ports")) {
    QJsonArray ports;
    for (const auto &port : QSerialPortInfo::availablePorts()) {
      ports.append(QJsonObject{{"port", port.portName()}, {"description", port.description()},
                               {"serial", port.serialNumber()}, {"location", port.systemLocation()}});
    }
    QTextStream(stdout) << QJsonDocument(ports).toJson();
    return 0;
  }
  bool ok = false;
  const int seconds = parser.value("seconds").toInt(&ok);
  if (!ok || seconds < 1 || seconds > 120 || (parser.isSet("demo") && parser.isSet("port"))) {
    QTextStream(stderr) << "Invalid options: seconds=1..120; demo and port are exclusive.\n";
    return 2;
  }
  MonitorWindow window(parser.isSet("demo"));
  window.show();
  if (parser.isSet("port")) {
    window.connectPort(parser.value("port"));
  }
  if (parser.isSet("capture") || parser.isSet("report") || parser.isSet("csv")) {
    QTimer::singleShot(seconds * 1000, &window, [&] {
      bool success = true;
      if (parser.isSet("capture")) {
        success = window.grab().save(parser.value("capture"));
      }
      if (parser.isSet("report")) {
        QSaveFile file(parser.value("report"));
        const auto data = QJsonDocument(window.sessionReport()).toJson();
        success = file.open(QIODevice::WriteOnly)
            && file.write(data) == data.size() && file.commit() && success;
      }
      if (parser.isSet("csv")) {
        QString error;
        success = window.writeCsv(parser.value("csv"), &error) && success;
        if (!error.isEmpty()) {
          QTextStream(stderr) << error << '\n';
        }
      }
      app.exit(success ? 0 : 1);
    });
  }
  return app.exec();
}
