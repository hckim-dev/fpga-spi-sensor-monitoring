QT += widgets serialport testlib
CONFIG += c++17 testcase console
CONFIG -= app_bundle
TARGET = test_monitor
TEMPLATE = app
INCLUDEPATH += ../src
SOURCES += test_monitor.cpp ../src/protocol.cpp ../src/trend_plot.cpp ../src/monitor_window.cpp
HEADERS += ../src/protocol.h ../src/trend_plot.h ../src/monitor_window.h
