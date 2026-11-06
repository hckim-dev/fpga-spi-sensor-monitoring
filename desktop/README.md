# Sensor Desk

Master의 USB-UART를 읽기 전용으로 수신하는 Qt 모니터입니다.
온도·습도·거리, 센서별 추이, SPI·OLED 상태와 상태 기록을 표시하고 CSV로 저장합니다.

## 실행·빌드

확인 환경: Windows 11, Qt 6.11.1 Widgets·SerialPort·Test, MSYS2 UCRT64 GCC 16.1.0.
Qt Charts는 필요하지 않습니다. 기본 Kit 경로는 `C:\msys64\ucrt64\bin`이며 다른 위치는 `-QtBin`으로 지정합니다.

```powershell
./scripts/run_monitor.ps1
./scripts/run_monitor.ps1 -Port COM4
./scripts/run_monitor.ps1 -Demo
```

`desktop/start.cmd`로도 실행할 수 있습니다. Qt Creator에서는 `desktop/monitor.pro`를 열고 호환되는 Qt 6 MinGW Kit으로 빌드합니다.
`-Demo`는 생성 데이터 모드로 화면·CSV에 구분해서 표시하며 실제 센서 수신과 함께 사용하지 않습니다.

Master의 USB 포트를 선택해 **연결**합니다. 두 보드 연결 시 Slave 포트와 구분하고 다른 터미널은 같은 포트를 닫습니다.
케이블 재연결 후 **새로고침 → 포트 선택 → 연결**로 수동 접속합니다. COM 번호는 PC마다 달라집니다.

## 표시·저장 기준

- UART: 115200 baud, 8N1, Flow Control 없음. PC에서 보드로 명령을 보내지 않습니다.
- `T=23.5C H=60.0% D=291cm L=OK O=OK` + CRLF를 해석합니다. 부분 수신·여러 줄·Reset의 빈 줄을 처리합니다.
- 센서 Invalid, SPI 오류, OLED 오류, PC 수신 중단을 구분합니다. 정상 레코드가 1초 동안 없으면 현재 수치를 비웁니다.
- 센서별 1/5/15분 추이를 표시하며 오류·재연결 구간의 그래프는 이어 그리지 않습니다.
- 최근 18,000개 기록을 보관합니다. 10Hz 기준 약 30분이며 초과 시 오래된 기록부터 제외합니다.
- **CSV 저장 / Ctrl+S**는 누른 시점의 보관 기록을 저장합니다. 연결 해제 후에도 기록은 남고 앱 종료 시 사라집니다.

CSV 열은 `received_utc, source, temperature_c, humidity_pct, distance_cm, spi_link, oled, segment_start`입니다.
시각은 PC 수신 UTC, 무효 센서값은 빈 칸이며 `segment_start=1`은 연결·오류·수신 중단 뒤 새 구간을 뜻합니다.
파일 선택 중 계속 수신하더라도 저장 대상은 클릭 시점의 Snapshot입니다. QSaveFile로 파일을 교체합니다.

[모니터링 화면](../docs/assets/desktop/monitoring.png) · [CSV 예시](../docs/assets/desktop/csv_export.png) · [정상/오류 비교](../docs/assets/status/spi_error_comparison.png)

## 구조·검증

| 파일 | 역할 |
| --- | --- |
| `src/protocol.*` | 줄 경계 복원·길이/범위 검사·CSV 저장 |
| `src/monitor_window.*` | 비동기 SerialPort 수신·수신 중단 감지·기록·화면 |
| `src/trend_plot.*` | 센서별 시간축·자동 축·단절 구간 표시 |
| `tests/test_monitor.cpp` | Protocol·복구·CSV·화면 자동 시험 |

```powershell
./scripts/build_monitor.ps1 -Test
```

2026-11-06 재검토: 별도 폴더에서 앱·시험을 새로 빌드하고 QtTest 36건 PASS를 확인했습니다.
세 가지 창 크기와 100%·125%·150% 배율의 레이아웃, 긴 오류 안내·상태 화면도 확인했습니다.
다른 작업 폴더에서 CLI 미리보기·화면/JSON/CSV 저장, 잘못된 옵션과 없는 포트의 실패 종료를 확인했습니다.

2026-11-05 실물 기록: 개선 후 Master COM4 10초·100건 수신 및 형식 오류 0건.
실제 USB 분리·재연결 1회에서 기존 기록 보존·수동 접속·센서값 복구를 확인했습니다.
자동 재접속·반복 탈착 내구성·센서 정확도를 검증한 결과는 아닙니다. [전체 검증 범위](../docs/implementation.md#검증-결과)

빌드·시험 결과는 `desktop/build*/`에 생성됩니다. 현재 Kit에서는 Qt 헤더의 GCC `-Wsfinae-incomplete` 경고가 재현되며,
경고를 숨기거나 Qt 설치 파일을 수정하지 않았습니다. 다른 PC에 실행 파일만 배포하는 패키징은 포함하지 않습니다.
