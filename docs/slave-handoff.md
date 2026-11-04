# Slave 구현 인계 — Interface Rev.1

**Slave는 센서값을 저장하고, Master의 `01` 명령에 고정 9 Byte로 응답한다.**
먼저 센서 없이 아래 G1 고정 응답으로 보드 간 통신을 맞춘 뒤 센서를 연결한다.
이 문서는 [Interface Rev.1](interface.md)의 구현용 요약이며, 상세 경계 조건은 원문을 따른다.

## 1. 담당 범위와 배선

- **Slave 담당:** DHT11·초음파 센서 수집, 단위 변환·유효성·시간 관리, SPI 응답, Slave XDC·검증.
- **Master 담당:** SPI Clock·읽기 요청, 응답 검사, FND·UART·OLED 표시. OLED는 Master의 별도 I2C 장치다.
- 양쪽 Basys3의 **같은 JB 번호끼리** 연결한다. MOSI/MISO를 교차하지 않는다.

| 신호 | Master ↔ Slave | 양쪽 Package Pin | 방향 |
| --- | --- | --- | --- |
| CS_n | JB1 ↔ JB1 | A14 | Master → Slave |
| MOSI | JB2 ↔ JB2 | A16 | Master → Slave |
| MISO | JB3 ↔ JB3 | B15 | Slave → Master |
| SCLK | JB4 ↔ JB4 | B16 | Master → Slave |
| GND | JB5 ↔ JB5 | 전원 GND | 공통 기준 |

신호는 LVCMOS33, 각 보드는 별도 USB 전원을 사용한다. **보드 사이 JB6/12의 3.3V는 연결하지 않는다.**
Rev.1 배선 기준은 Slave CS_n에 외부 10kΩ Pull-up, Master MISO에 외부 10kΩ Pull-down이다.
양쪽 전원·FPGA 설정 완료 조건에서 시험한다. 센서 Pin·전압 보호 회로는 Slave 쪽에서 확정한다.

## 2. SPI 규칙

| 항목 | 합의값 |
| --- | --- |
| Mode / 순서 | Mode 0(CPOL=0, CPHA=0), Byte 안에서 MSB-first |
| Clock / 요청 주기 | SCLK 100kHz, High/Low nominal 5µs·최소 4.5µs, Master Poll 100ms |
| 송수신 Edge | 상승 Edge에서 수신, 하강 Edge 이후 다음 Bit 출력 |
| 전송 단위 | CS_n LOW 한 번에 **10 Byte·80 Clock**, Byte 사이 CS 해제·별도 Pause 없음 |
| CS 시간 | 첫 상승 전 Setup ≥5µs, 마지막 하강 후 Hold ≥5µs, 다음 요청 전 High gap ≥10µs |
| Data 시간 | 상승 Edge 기준 Setup/Hold 각각 ≥1µs. Slave MISO는 SCLK 하강 후 ≤1µs에 유효 |
| 선택 / 해제 | CS_n=1이면 MISO=High-Z. MISO 출력 Enable/Disable 응답 ≤1µs |
| Timeout | CS_n LOW가 2ms를 초과하면 Slave는 MISO=0으로 두고 CS_n HIGH를 기다림 |

Slave의 100MHz Clock에서 외부 CS_n/SCLK/MOSI의 비동기 입력을 처리해야 한다.
100MHz로 동기화·Edge 검출하는 구현을 권장하되 위 응답 시간을 만족해야 한다.
아래 전송 순서는 **외부 SPI Edge 기준**이며 실제 내부 처리는 동기화 지연을 고려한다.

## 3. 요청과 응답 — 전송 중에 응답한다

```text
Byte index  0   1   2     3       4       5      6      7       8       9
MOSI        01  00  00    00      00      00     00     00      00      00
MISO        00  A5  STATUS TEMP_H  TEMP_L  HUM_H  HUM_L  DIST_H  DIST_L  XOR
```

`01`은 READ_SENSORS다. 뒤의 MOSI 9 Byte는 Dummy이므로 무시한다.
명령을 받는 첫 8 Clock 동안 MISO는 0이다. **8번째 상승에서 명령 수신을 완료하고,
뒤따르는 하강에서 A5의 Bit7을 준비한다. Master는 9번째 상승에서 이 Bit를 읽는다.**
마지막 Bit는 80번째 상승에서 읽히고, 대응하는 하강까지 유지한다.

| 필드 | 형식·단위 | Valid일 때 허용 범위 |
| --- | --- | --- |
| TEMP | signed 16-bit Two's complement, 0.1°C | -200..600(-20.0..60.0°C) |
| HUM | unsigned 16-bit, 0.1%RH | 0..1000(0.0..100.0%) |
| DIST | unsigned 16-bit, cm | 2..400cm |
| STATUS | bit0=온도·습도 공통 Valid, bit1=거리 Valid, bit7:2=0 | 00=모두 무효, 01=온습도만, 02=거리만, 03=모두 유효 |
| XOR | `A5 ^ STATUS ^ TEMP_H ^ TEMP_L ^ HUM_H ^ HUM_L ^ DIST_H ^ DIST_L` | 첫 무시 Byte 00과 XOR 자신은 계산에서 제외 |

16-bit 값은 **상위 Byte 먼저** 보낸다. 예: 23.5°C→235→`00 EB`, -5.5°C→-55→`FF C9`.
센서 Driver 결과를 위 단위로 변환하고, 남는 소수는 0 방향으로 절삭한다.
센서가 미준비여도 응답해야 한다. **STATUS=00은 정상 통신이며 센서값만 무효다.**

## 4. 값 저장·오류·복구

- 센서는 SPI와 독립적으로 측정한다. 읽기 명령을 받은 뒤 측정 완료를 기다리거나 SCLK를 지연시키지 않는다.
- `01` 명령 확정 시 STATUS·온습도·거리를 한 번에 Snapshot으로 고정하고 XOR도 그 값으로 만든다. 전송 중 새 측정값을 섞지 않는다.
- 같은 내부 Clock에 측정 갱신과 Snapshot이 겹치면 **이전에 완료된 값**을 사용한다. 새 값은 다음 요청부터 반영한다.
- 측정 실패·범위 초과 시 해당 Valid를 지우고 마지막 수치는 보존한다. 새 측정 성공 전에는 Valid를 다시 켜지 않는다.
- 마지막 성공 저장부터 온습도 **3초 이상**, 거리 **250ms 이상**이면 해당 Valid=0이다. SPI 읽기로 시간을 초기화하지 않는다. 만료 경계의 Snapshot도 Invalid다.
- DHT11은 전원 인가 후 최소 2초, 매 통신 종료 후 최소 2초 대기한다. 거리 측정 시작 간격은 100ms를 제안한다.
- Reset 시 값·Valid=0. CS_n이 LOW이면 MISO=0으로 두고 HIGH를 본 뒤 새 명령을 받는다.
- CS_n 조기 상승 시 진행 상태를 폐기한다. 알 수 없는 명령·80 Clock 이후 추가 Clock에는 MISO=0이며 다음 CS_n HIGH까지 새 명령을 찾지 않는다.
- Timeout은 System Clock으로 세고 SCLK 정지·Byte 경계에서 다시 시작하지 않는다. 매 요청은 새 명령부터 시작한다.

## 5. 먼저 맞출 시험값

아래 MISO는 첫 무시 Byte를 포함한 **전체 10 Byte**다. 실제 센서 측정값이 아닌 시험 패턴이다.

| 시험 | MISO 전체 | Master 예상 |
| --- | --- | --- |
| G1: 첫 연결 | `00 A5 03 00 EB 02 58 01 23 35` | 23.5°C / 60.0% / 291cm, Link OK |
| G2: 음수 | `00 A5 03 FF C9 01 C4 00 7B 2E` | -5.5°C / 45.2% / 123cm, Link OK |
| G3: 미준비 | `00 A5 00 00 00 00 00 00 00 A5` | 센서 모두 `--`, Link OK |

진행 순서: **G1 반복 → G2·G3 → 전송 중 값 갱신 → 중단·Reset·Timeout 복구 → 실제 센서**.
G1에서 Master UART 예상은 `T=23.5C H=60.0% D=291cm L=OK O=OK`다(OLED 정상 연결 조건).
FND는 SW[1:0]의 00/11=온도, 01=습도, 10=거리로 확인한다.

팀원이 공유할 항목: **Slave 코드 Commit·Top 이름·XDC, 적용한 Bitstream, 위 시험 결과, 센서 Pin·전압 처리**.
Master는 구현·Simulation·Master+OLED 단독 실물 시험을 마쳤으며 **두 보드 실제 연동은 아직 미검증**이다.
공통 상세 시험은 [Interface Rev.1의 Golden Vector](interface.md#golden-test-vector)를 사용한다.
