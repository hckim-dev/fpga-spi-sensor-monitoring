QT += widgets serialport
CONFIG += c++17
TARGET = sensor_monitor
TEMPLATE = app
SOURCES += src/main.cpp src/protocol.cpp src/trend_plot.cpp src/monitor_window.cpp
HEADERS += src/protocol.h src/trend_plot.h src/monitor_window.h
RESOURCES += resources.qrc
win32:QMAKE_CXXFLAGS += -Wall -Wextra
