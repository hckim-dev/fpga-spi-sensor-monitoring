#pragma once

#include "protocol.h"
#include <QWidget>

class TrendPlot : public QWidget {
public:
  explicit TrendPlot(QWidget *parent = nullptr);
  void setSamples(const std::deque<SensorSample> *samples) { samples_ = samples; }
  void setChannel(int channel) { channel_ = channel; update(); }
  void setWindow(int seconds) { seconds_ = seconds; update(); }
  void setNow(qint64 elapsedMs) { now_ = elapsedMs; update(); }

protected:
  void paintEvent(QPaintEvent *event) override;

private:
  const std::deque<SensorSample> *samples_ = nullptr;
  int channel_ = 0;
  int seconds_ = 60;
  qint64 now_ = 0;
};
