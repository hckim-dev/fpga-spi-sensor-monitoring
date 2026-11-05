#include "trend_plot.h"

#include <QPainter>
#include <QPainterPath>
#include <algorithm>
#include <cmath>

namespace {
std::optional<double> sensorValue(const SensorSample &sample, int channel) {
  const auto value = channel == 0 ? sample.temperature : channel == 1 ? sample.humidity : sample.distance;
  return sample.link == "OK" && value && std::isfinite(*value) ? value : std::nullopt;
}

auto visibleBegin(const std::deque<SensorSample> &samples, qint64 start) {
  return std::lower_bound(samples.cbegin(), samples.cend(), start,
      [](const SensorSample &sample, qint64 time) { return sample.elapsedMs < time; });
}
}

TrendPlot::TrendPlot(QWidget *parent) : QWidget(parent) {
  setMinimumHeight(140);
  setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
}

std::pair<double, double> TrendPlot::visibleRange() const {
  double low = 0;
  double high = channel_ == 0 ? 40 : 100;
  bool hasPoint = false;
  if (samples_) {
    const auto first = visibleBegin(*samples_, now_ - seconds_ * 1000LL);
    for (auto it = first; it != samples_->cend() && it->elapsedMs <= now_; ++it) {
      const auto value = sensorValue(*it, channel_);
      if (value) {
        low = hasPoint ? std::min(low, *value) : *value;
        high = hasPoint ? std::max(high, *value) : *value;
        hasPoint = true;
      }
    }
  }
  if (!hasPoint) {
    return {low, high};
  }
  const double minimumSpan[] = {4, 10, 20};
  const double desiredStep = std::max((high - low) * 1.3, minimumSpan[channel_]) / 4;
  const double base = std::pow(10.0, std::floor(std::log10(desiredStep)));
  double step = base;
  for (double factor : {1.0, 2.0, 5.0, 10.0}) {
    if (base * factor >= desiredStep) {
      step = base * factor;
      break;
    }
  }
  double bottom = std::floor((low + high) / (2 * step)) * step - 2 * step;
  if (bottom > low) {
    bottom = std::floor(low / step) * step;
  }
  if (bottom + 4 * step < high) {
    bottom = std::ceil(high / step) * step - 4 * step;
  }
  return {bottom, bottom + 4 * step};
}

QPainterPath TrendPlot::trace(const QRectF &plot, double low, double high, QPolygonF *segmentStarts) const {
  QPainterPath path;
  if (!samples_ || high <= low) {
    return path;
  }
  const qint64 start = now_ - seconds_ * 1000LL;
  bool connected = false;
  qint64 previous = 0;
  for (auto it = visibleBegin(*samples_, start); it != samples_->cend() && it->elapsedMs <= now_; ++it) {
    const auto value = sensorValue(*it, channel_);
    if (!value) {
      connected = false;
      continue;
    }
    const QPointF point(plot.left() + (it->elapsedMs - start) * plot.width() / (seconds_ * 1000.0),
                        plot.bottom() - (*value - low) * plot.height() / (high - low));
    if (connected && !it->breakBefore && it->elapsedMs - previous < 1000) {
      path.lineTo(point);
    } else {
      path.moveTo(point);
      if (segmentStarts) {
        segmentStarts->append(point);
      }
    }
    connected = true;
    previous = it->elapsedMs;
  }
  return path;
}

void TrendPlot::paintEvent(QPaintEvent *) {
  QPainter painter(this);
  painter.setRenderHint(QPainter::Antialiasing);
  const QColor ink("#596b61");
  const QColor colors[] = {QColor("#257769"), QColor("#4d7592"), QColor("#986832")};
  const QRectF plot(50, 27, width() - 74, height() - 67);
  const auto [low, high] = visibleRange();
  QFont font = painter.font();
  font.setPixelSize(12);
  painter.setFont(font);
  const QString units[] = {QStringLiteral("°C"), QStringLiteral("% RH"), QStringLiteral("cm")};
  painter.setPen(ink);
  painter.drawText(QRectF(0, 0, 45, 18), Qt::AlignRight | Qt::AlignVCenter, units[channel_]);
  for (int row = 0; row <= 4; ++row) {
    const double y = plot.bottom() - row * plot.height() / 4;
    painter.setPen(QPen(QColor("#e5e9e5"), 1, Qt::DashLine));
    painter.drawLine(QPointF(plot.left(), y), QPointF(plot.right(), y));
    painter.setPen(ink);
    painter.drawText(QRectF(0, y - 9, 37, 18), Qt::AlignRight | Qt::AlignVCenter,
                     QString::number(low + row * (high - low) / 4, 'f', 0));
  }
  for (int col = 0; col <= 4; ++col) {
    const double x = plot.left() + col * plot.width() / 4;
    painter.setPen(ink);
    const int ago = seconds_ - col * seconds_ / 4;
    const QString elapsed = ago >= 60 && ago % 60 == 0 ? QString("−%1m").arg(ago / 60)
                                                     : QString("−%1s").arg(ago);
    painter.drawText(QRectF(x - 24, plot.bottom() + 12, 48, 18), Qt::AlignCenter,
                     ago == 0 ? QStringLiteral("지금") : elapsed);
  }
  QPolygonF segmentStarts;
  const auto path = trace(plot, low, high, &segmentStarts);
  if (path.elementCount() == 0) {
    painter.setPen(ink);
    painter.drawText(plot, Qt::AlignCenter, !samples_ || samples_->empty()
        ? QStringLiteral("수신한 데이터가 여기에 쌓입니다") : QStringLiteral("선택한 센서의 유효한 데이터가 없습니다"));
    return;
  }
  painter.save();
  painter.setClipRect(plot.adjusted(-2, -2, 2, 2));
  painter.setPen(QPen(colors[channel_], 2.2, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
  painter.drawPath(path);
  // 선을 이룰 만큼 연속 수신되지 않은 단일 관측도 점으로 남긴다.
  painter.setPen(QPen(colors[channel_], 3.4, Qt::SolidLine, Qt::RoundCap));
  painter.drawPoints(segmentStarts);
  if (samples_ && !samples_->empty() && now_ - samples_->back().elapsedMs < 1000
      && sensorValue(samples_->back(), channel_)) {
    painter.setBrush(colors[channel_]);
    painter.setPen(Qt::NoPen);
    painter.drawEllipse(path.currentPosition(), 3.5, 3.5);
  }
  painter.restore();
}
