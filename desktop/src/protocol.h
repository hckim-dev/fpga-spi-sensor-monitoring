#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QString>
#include <QVector>
#include <deque>
#include <optional>

struct SensorSample {
  QDateTime receivedAt;
  qint64 elapsedMs = 0;
  QString source;
  bool breakBefore = false;
  std::optional<double> temperature;
  std::optional<double> humidity;
  std::optional<double> distance;
  QString link;
  bool oledOk = false;
  QByteArray raw;
};

std::optional<SensorSample> parseRecord(const QByteArray &line);
bool exportCsv(const QString &path, const std::deque<SensorSample> &samples, QString *error);

class RecordDecoder {
public:
  QVector<SensorSample> feed(const QByteArray &bytes);
  void reset();
  quint64 rejected() const { return rejected_; }

private:
  QByteArray pending_;
  bool discarding_ = false;
  bool breakBeforeNext_ = true;
  quint64 rejected_ = 0;
};
