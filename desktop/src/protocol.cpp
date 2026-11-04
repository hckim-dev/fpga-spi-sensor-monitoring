#include "protocol.h"

#include <QRegularExpression>
#include <QSaveFile>
#include <QTextStream>

std::optional<SensorSample> parseRecord(const QByteArray &line) {
  static const QRegularExpression pattern(QStringLiteral(
      "\\AT=(--|-?[0-9]{1,2}\\.[0-9])C H=(--|[0-9]{1,3}\\.[0-9])% "
      "D=(--|[0-9]{1,3})cm L=(OK|ERR:(?:NONE|TIMEOUT|LENGTH|HEADER|XOR|RESERVED|RANGE|STALE)) O=(OK|ERR)\\z"));
  if (line.size() > 64) {
    return std::nullopt;
  }
  const auto match = pattern.match(QString::fromLatin1(line));
  if (!match.hasMatch()) {
    return std::nullopt;
  }
  SensorSample sample;
  const auto value = [&match](int group) -> std::optional<double> {
    return match.captured(group) == "--" ? std::nullopt
                                         : std::optional<double>(match.captured(group).toDouble());
  };
  sample.temperature = value(1);
  sample.humidity = value(2);
  sample.distance = value(3);
  sample.link = match.captured(4);
  sample.oledOk = match.captured(5) == "OK";
  sample.raw = line;
  if (sample.temperature.has_value() != sample.humidity.has_value()
      || (sample.temperature && (*sample.temperature < -20 || *sample.temperature > 60))
      || (sample.humidity && (*sample.humidity < 0 || *sample.humidity > 100))
      || (sample.distance && (*sample.distance < 2 || *sample.distance > 400))) {
    return std::nullopt;
  }
  return sample;
}

QVector<SensorSample> RecordDecoder::feed(const QByteArray &bytes) {
  QVector<SensorSample> samples;
  for (char byte : bytes) {
    if (byte == '\n') {
      if (!discarding_) {
        if (pending_.endsWith('\r')) {
          pending_.chop(1);
        }
        if (!pending_.isEmpty()) {
          auto sample = parseRecord(pending_);
          if (sample) {
            samples.push_back(*sample);
          } else {
            ++rejected_;
          }
        }
      }
      pending_.clear();
      discarding_ = false;
    } else if (!discarding_) {
      pending_.append(byte);
      // 긴 잡음은 다음 줄 경계까지 버려 메모리와 재동기화 범위를 제한한다.
      if (pending_.size() > 65) {
        pending_.clear();
        discarding_ = true;
        ++rejected_;
      }
    }
  }
  return samples;
}

void RecordDecoder::reset() {
  pending_.clear();
  discarding_ = false;
  rejected_ = 0;
}

bool exportCsv(const QString &path, const std::deque<SensorSample> &samples, QString *error) {
  QSaveFile file(path);
  if (!file.open(QIODevice::WriteOnly)) {
    *error = file.errorString();
    return false;
  }
  QTextStream out(&file);
  out << "received_utc,source,temperature_c,humidity_pct,distance_cm,spi_link,oled\n";
  const auto number = [](const std::optional<double> &value, int precision) {
    return value ? QString::number(*value, 'f', precision) : QString();
  };
  for (const auto &sample : samples) {
    QString source = sample.source;
    source.replace('"', "\"\"");
    out << sample.receivedAt.toUTC().toString(Qt::ISODateWithMs) << ",\"" << source << "\","
        << number(sample.temperature, 1) << ',' << number(sample.humidity, 1) << ','
        << number(sample.distance, 0) << ',' << sample.link << ','
        << (sample.oledOk ? "OK" : "ERR") << '\n';
  }
  out.flush();
  if (out.status() != QTextStream::Ok || !file.commit()) {
    *error = file.errorString().isEmpty() ? QStringLiteral("CSV 쓰기에 실패했습니다.") : file.errorString();
    return false;
  }
  return true;
}
