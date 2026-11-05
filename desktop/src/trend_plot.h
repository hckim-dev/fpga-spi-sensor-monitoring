#pragma once

#include "protocol.h"
#include <QWidget>
#include <QPainterPath>
#include <QPolygonF>
#include <utility>

class TrendPlot : public QWidget {
public:
  explicit TrendPlot(QWidget *parent = nullptr);
  void setSamples(const std::deque<SensorSample> *samples) { samples_ = samples; }
  void setChannel(int channel) {
    if (channel >= 0 && channel < 3) {
      channel_ = channel;
      update();
    }
  }
  void setWindow(int seconds) {
    if (seconds > 0) {
      seconds_ = seconds;
      update();
    }
  }
  void setNow(qint64 elapsedMs) { now_ = elapsedMs; update(); }

protected:
  void paintEvent(QPaintEvent *event) override;

private:
  friend class MonitorTest;
  std::pair<double, double> visibleRange() const;
  QPainterPath trace(const QRectF &plot, double low, double high, QPolygonF *segmentStarts = nullptr) const;
  const std::deque<SensorSample> *samples_ = nullptr;
  int channel_ = 0;
  int seconds_ = 60;
  qint64 now_ = 0;
};
