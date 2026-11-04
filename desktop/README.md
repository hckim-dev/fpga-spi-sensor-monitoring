# Sensor Desk

Master의 USB-UART 출력을 표시하는 Qt 데스크톱 모니터다. FPGA의 RTL·배선·통신 형식 변경 없이 사용한다.

```text
Slave 센서 → SPI → Master → USB-UART → Sensor Desk
```

온도·습도·거리, 센서별 추이(1/5/15분), SPI·OLED 상태, 상태 변화 기록과 CSV 저장을 제공한다.
연한 회색 배경과 절제된 색상으로 수치·추이·상태를 구분했다.

## 실행

이 PC에서는 `desktop/start.cmd`를 실행하거나 저장소에서 다음 명령을 사용한다.

```powershell
./scripts/run_monitor.ps1
./scripts/run_monitor.ps1 -Port COM4
./scripts/run_monitor.ps1 -Demo
```

Master의 USB 포트를 선택해 **연결**한다. 두 보드가 연결돼 있다면 Slave의 포트와 구분한다.
포트 목록의 항목에 마우스를 올리면 장치 Serial Number를 확인할 수 있다.
COM 번호는 PC마다 달라질 수 있다. 다른 터미널·수신 도구가 같은 포트를 사용 중이면 먼저 닫는다.
케이블 분리 후에는 **새로고침 → 포트 선택 → 연결**로 재연결한다.

Qt Creator에서는 `monitor.pro`를 열고 Qt 6 MinGW Kit을 선택한다. UI를 별도로 작성할 필요는 없다.
확인 환경은 Windows 11, Qt 6.11.1 Widgets·SerialPort·Test, MSYS2 UCRT64 GCC 16.1.0이다.
스크립트의 기본 Kit 경로는 `C:\msys64\ucrt64\bin`이며, 다른 설치 위치는 `-QtBin`으로 지정한다.
그래프는 QPainter로 그리므로 Qt Charts 설치가 필요 없다. 다른 PC에 실행 파일만 배포하는 작업은 별도 범위다.

## 데이터와 표시 기준

- 115200 baud, 8N1, Flow Control 없음, 읽기 전용. PC에서 보드에 명령을 보내지 않는다.
- `T=23.0C H=53.0% D=20cm L=OK O=OK` + CRLF를 해석한다. 부분 수신·여러 줄·Reset의 빈 줄을 처리한다.
- 잘못된 형식·범위는 제외하고 오류 수를 센다. 줄 중간에 연결하면 최초 조각도 형식 오류로 집계될 수 있다.
- `--` 센서와 `L=ERR:<reason>`를 구분한다. 정상 형식의 줄이 1초 이상 없으면 **PC 수신 중단**으로 표시하고 현재 수치를 비운다.
- PC 수신 중단과 FPGA의 `ERR:STALE`는 별개다. SPI 오류·센서 Invalid·재연결·1초 이상 간격은 그래프를 이어 그리지 않는다.
- 최근 18,000개 수신 기록을 메모리에 보관한다(10Hz 기준 약 30분). 초과 시 오래된 기록부터 제외한다.
- CSV는 저장 버튼을 누른 시점의 보관 기록이다. 연속 파일 기록은 아니다. 연결을 해제해도 기록은 남고 앱을 종료하면 사라진다.
- CSV 시각은 **PC 수신 UTC**이며 센서 측정 시각이 아니다. Invalid는 빈 칸, 상태는 별도 열이다. 재연결한 포트는 `source` 열로 구분한다.
- `-Demo`는 별도 실행 모드이며 생성 데이터임을 화면·CSV source(`DEMO`)·파일명에 표시한다. 실측과 혼합하지 않는다.
- DHT11의 `.0` 표시는 공통 출력 형식이다. 현재 센서의 소수 측정 능력을 의미하지 않는다.

## 구조와 검증

| 파일 | 역할 |
| --- | --- |
| `src/protocol.*` | 줄 경계 복원·유한 버퍼·값/상태 검사·CSV 저장 |
| `src/monitor_window.*` | 비동기 SerialPort 수신·수신 중단 감지·기록·화면 |
| `src/trend_plot.*` | 시간축·센서 선택·단절을 반영한 그래프 |
| `tests/test_monitor.cpp` | Protocol·복구·CSV·화면 회귀 |

```powershell
./scripts/build_monitor.ps1 -Test
```

2026-11-05: QtTest 27건 PASS: 경계값·음수·Invalid·오류 코드, 모든 Byte 분할 위치, 복수 줄·긴 잡음 후 복구,
CSV 성공/실패, 수신 중단·정상 복구·연결 해제, 기록 상한, 1220×850·980×760 화면 배치.
시험의 수신 중단·연결 해제는 앱 내부 상태를 사용하는 자동 시험이며 물리 USB 분리 시험과 구분한다.

Windows 창에서 실제 Master COM4·10초 수신 100건, 형식 오류 0건, 전 건 `L=OK O=OK`를 확인했다.
동일한 100건의 CSV와 실제 표시 Capture도 확인했다. 온도 24.1~24.9°C·습도 20.0%·거리 28cm는 UART 관측값이다.
전달받은 DHT11 소수 바이트 0 조건과 온도 출력의 차이는 원시 센서 Frame·적용 Slave Bitstream 확인이 필요하다.
Qt는 수신값을 반올림해 정수로 만들거나 보정하지 않는다. 센서 정확도·원시 형식 검증을 의미하지 않는다.

빌드 시 Qt 헤더의 `QChar`에서 GCC 16의 `-Wsfinae-incomplete` 경고가 발생한다.
`#include <QDateTime>`만 있는 최소 파일에서도 재현되며, 경고를 끄거나 설치된 Qt 파일을 수정하지 않았다.
자동 시험 로그·화면 Capture·실물 수신 결과는 Git에서 제외한 `desktop/build*/`에 둔다.

SerialPort는 GUI Event Loop의 `readyRead`로 읽는다. 동기 대기를 사용하지 않으며, 줄은 최대 64 Byte로 검사한다.
긴 줄은 LF까지 폐기해 재동기화하고, SerialPort 버퍼 64KiB·수신 기록 18,000개·상태 기록 200행으로 메모리를 제한한다.
CSV는 보관된 기록의 제한된 Snapshot을 QSaveFile로 저장한다.
API 기준: [QSerialPort](https://doc.qt.io/qt-6/qserialport.html), [QSaveFile](https://doc.qt.io/qt-6/qsavefile.html).
