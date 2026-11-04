#include "trend_plot.h"

#include <QPainter>
#include <QPainterPath>
#include <algorithm>
#include <cmath>

TrendPlot::TrendPlot(QWidget *parent) : QWidget(parent) {
  setMinimumHeight(140);
  setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
}

void TrendPlot::paintEvent(QPaintEvent *) {
  QPainter painter(this);
  painter.setRenderHint(QPainter::Antialiasing);
  const QColor ink("#66736e");
  const QColor colors[] = {QColor("#257769"), QColor("#4d7592"), QColor("#aa7741")};
  const QRectF plot(48, 18, width() - 72, height() - 58);
  const auto valueFor = [this](const SensorSample &sample) {
    if (sample.link != "OK") {
      return std::optional<double>();
    }
    return channel_ == 0 ? sample.temperature : channel_ == 1 ? sample.humidity : sample.distance;
  };
  double low = 0;
  double high = channel_ == 0 ? 40 : channel_ == 1 ? 100 : 100;
  bool hasPoint = false;
  const qint64 start = now_ - seconds_ * 1000LL;
  if (samples_) {
    for (auto it = samples_->rbegin(); it != samples_->rend() && it->elapsedMs >= start; ++it) {
      const auto value = valueFor(*it);
      if (value) {
        low = std::min(low, std::floor(*value / 10.0) * 10.0);
        high = std::max(high, std::ceil((*value + 1) / 10.0) * 10.0);
        hasPoint = true;
      }
    }
  }
  QFont font = painter.font();
  font.setPixelSize(11);
  painter.setFont(font);
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
    painter.drawText(QRectF(x - 24, plot.bottom() + 12, 48, 18), Qt::AlignCenter,
                     ago == 0 ? QStringLiteral("지금") : QString("−%1s").arg(ago));
  }
  if (!hasPoint) {
    painter.setPen(ink);
    painter.drawText(plot, Qt::AlignCenter, QStringLiteral("수신한 데이터가 여기에 쌓입니다"));
    return;
  }
  QPainterPath path;
  bool connected = false;
  qint64 previous = 0;
  QPointF last;
  painter.save();
  painter.setClipRect(plot.adjusted(-2, -2, 2, 2));
  for (const auto &sample : *samples_) {
    if (sample.elapsedMs < start) {
      continue;
    }
    const auto value = valueFor(sample);
    if (!value) {
      connected = false;
      continue;
    }
    const QPointF point(plot.left() + (sample.elapsedMs - start) * plot.width() / (seconds_ * 1000.0),
                        plot.bottom() - (*value - low) * plot.height() / (high - low));
    if (connected && !sample.breakBefore && sample.elapsedMs - previous < 1000) {
      path.lineTo(point);
    } else {
      path.moveTo(point);
    }
    connected = true;
    previous = sample.elapsedMs;
    last = point;
  }
  painter.setPen(QPen(colors[channel_], 2.2, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
  painter.drawPath(path);
  if (connected) {
    painter.setBrush(colors[channel_]);
    painter.setPen(Qt::NoPen);
    painter.drawEllipse(last, 3.5, 3.5);
  }
  painter.restore();
}
