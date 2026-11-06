# Master / Slave 인터페이스 — Rev.1

두 Basys3 사이의 전용 SPI 규약입니다. Master는 요청·검사·표시를, Slave는 센서 측정·단위 변환·Snapshot 응답을 담당합니다.
이 문서는 합의한 전송·전기 조건이며 모든 항목을 실물에서 검증했다는 의미는 아닙니다. [검증 범위](implementation.md#검증-결과)

## 배선

JB의 같은 번호·같은 신호끼리 연결합니다. MOSI와 MISO를 교차하지 않습니다.

| Signal | Master ↔ Slave | 양쪽 Package Pin | 방향 |
| --- | --- | --- | --- |
| CS_n | JB1 ↔ JB1 | A14 | Master → Slave |
| MOSI | JB2 ↔ JB2 | A16 | Master → Slave |
| MISO | JB3 ↔ JB3 | B15 | Slave → Master |
| SCLK | JB4 ↔ JB4 | B16 | Master → Slave |
| GND | JB5 ↔ JB5 | 전원 GND | 공통 기준 |

- 신호는 LVCMOS33이며 양쪽 보드는 각각 USB 전원을 사용합니다. 보드 사이 JB6/12의 3.3V는 연결하지 않습니다.
- 설계 기준은 Slave CS_n에 외부 10kΩ Pull-up, Master MISO에 외부 10kΩ Pull-down입니다. 연결 검출을 보장하지 않습니다.
- 비선택 시 Slave MISO는 High-Z이며 선택·해제 후 출력 Enable/Disable 응답은 1µs 이내입니다.
- 양쪽 보드의 전원·FPGA 설정이 완료된 조건을 대상으로 합니다. 전원을 끄고 배선을 변경합니다.
- Slave 센서 전압·Pull-up과 HC-SR04 Echo의 3.3V 레벨 변환을 확인해야 합니다.

Master OLED는 SSD1306 128×32, I2C 100kHz입니다. 7-bit 주소 `0x3C`부터 시도하고,
주소 확정 전 오류 시 `0x3D`와 번갈아 재시도합니다. 성공한 주소는 Reset 전까지 유지합니다.
SCL=JA1(J1), SDA=JA2(L2), GND=JA5, VCC=JA6(3.3V)를 사용합니다.
Master USB-UART TX는 A18, 115200/8N1입니다. Slave Reset은 SW15(R2), Active-high입니다.
Slave 센서의 현재 XDC는 DHT DATA=JA1(J1), Trig=JXADC1(L17), Echo=JXADC2(M19)입니다.

## SPI Timing

각 보드는 독립 100MHz Clock을 사용합니다. 아래 시간은 인터페이스 요구 조건이며 외부 I/O Timing Closure나 실측 보증값이 아닙니다.

| 항목 | 규칙 |
| --- | --- |
| Mode·순서 | Mode 0(CPOL=0, CPHA=0), Byte 안에서 MSB-first |
| Idle | CS_n=1, SCLK=0, MOSI=0, Slave MISO=Z |
| SCLK | 100kHz, High/Low nominal 5µs·최소 4.5µs |
| 데이터 Edge | 상승에서 수신, 하강 이후 다음 Bit 출력 |
| Data setup/hold | 수신 기준 상승 Edge에 대해 각각 최소 1µs |
| MISO delay | Slave SCLK 입력 하강부터 MISO 유효까지 최대 1µs |
| CS setup/hold | 첫 상승 전 최소 5µs / 마지막 하강 후 최소 5µs |
| CS High gap | SCLK=0으로 최소 10µs |
| 전송 | CS_n LOW 한 번에 10 Byte·80 Clock, Byte 사이 Pause 없음 |
| Timeout | 정상 선택 구간 약 0.8ms, 2ms 초과 시 중단 |

MISO setup/hold는 Master SCLK 출력의 상승 Edge 기준 Master MISO 입력에서 만족해야 합니다.
MOSI setup/hold는 Slave SCLK 입력의 상승 Edge 기준입니다. Reset·Timeout의 강제 종료는 정상 hold 규칙의 예외입니다.
현재 Slave는 CS_n/SCLK/MOSI를, Master는 MISO를 2단계 동기화합니다. 실제 경로·왕복 지연·Skew는 별도 확인 대상입니다.

## Transaction과 Byte Format

Master는 `01`(READ_SENSORS)과 Dummy 9 Byte를 보내는 동안 응답을 받습니다.
명령의 8번째 상승에서 수신을 완료하고 뒤따르는 하강에서 A5의 Bit7을 준비해, Master가 9번째 상승에서 읽습니다.
첫 Command Bit는 CS setup 중 준비하며 Command 구간의 MISO는 0입니다.

| 전체 Byte index | MOSI | MISO |
| --- | --- | --- |
| 0 | 01 | 00 (무시) |
| 1 | 00 | A5 |
| 2 | 00 | STATUS |
| 3 / 4 | 00 / 00 | TEMP_H / TEMP_L |
| 5 / 6 | 00 / 00 | HUM_H / HUM_L |
| 7 / 8 | 00 / 00 | DIST_H / DIST_L |
| 9 | 00 | XOR |

| 필드 | 형식·단위 | Valid일 때 허용 범위 |
| --- | --- | --- |
| TEMP | signed 16-bit Two's complement, 0.1°C | -200..600 (-20.0..60.0°C) |
| HUM | unsigned 16-bit, 0.1%RH | 0..1000 (0.0..100.0%) |
| DIST | unsigned 16-bit, cm | 2..400cm |
| STATUS | bit0=온습도 공통 Valid, bit1=거리 Valid, bit7:2=0 | 00=모두 무효, 01=온습도만, 02=거리만, 03=모두 유효 |
| XOR | A5부터 DIST_L까지 8개 Byte의 Bitwise XOR | 응답 9 Byte 전체 XOR=0 |

16-bit는 상위 Byte 먼저 전달합니다. 예: 23.5°C→235→`00 EB`, -5.5°C→-55→`FF C9`.
센서 Driver 결과의 Wire 단위 변환은 Slave 책임이며 초과 소수는 0 방향으로 절삭합니다.
단위는 통신 표현의 분해능이며 센서 정확도가 아닙니다. XOR는 모든 다중 Bit 오류·Replay를 검출하지 못합니다.

## 센서 Valid·Snapshot

- 센서 측정은 SPI와 독립적으로 진행합니다. 읽기 요청 뒤 측정 완료를 기다리거나 SCLK를 늘이지 않습니다.
- Reset 시 값·Valid=0입니다. 센서 초기화 중에도 `STATUS=00`으로 응답하며 이는 정상 통신입니다.
- 성공한 측정값과 Valid는 함께 저장합니다. 실패·범위 초과 시 해당 Valid만 지우고 마지막 성공 수치는 보존합니다.
- 마지막 성공값 저장 후 DHT는 3초 이상, 거리는 250ms 이상이면 해당 Valid=0입니다. 실패·SPI 읽기로 Age를 초기화하지 않습니다.
- DHT 요청은 전원 인가 후 최소 2초, 매 통신 종료 후 최소 2초 대기합니다. 거리 측정 시작 간격은 100ms입니다.
- READ 명령이 Slave Clock에서 확정되면 STATUS·온습도·거리를 한 번에 Snapshot으로 고정하고 XOR를 계산합니다.
- 같은 Clock에서 측정 갱신과 Snapshot이 겹치면 이전 완료값을 사용합니다. 새 값은 다음 Transaction부터 반영합니다.
- Snapshot 직전 `Age < 만료값`일 때만 Valid입니다. 경계값이면 Invalid이며 전송 중 만료·새 측정은 현재 응답을 바꾸지 않습니다.
- 온습도 한 쌍은 같은 DHT 결과지만 거리는 별도 최신 측정입니다. 세 값의 실제 측정 시각이 같다는 뜻은 아닙니다.
- Master는 정확한 수신 길이·형식과 Valid 필드의 범위를 검사하고, CS 해제·Frame 검사 후에만 값을 반영합니다.

## 중단·Reset·복구

- 알 수 없는 명령: 응답 구간 MISO=0, CS_n High까지 새 명령을 찾지 않습니다.
- CS_n 조기 상승: Slave 전송 상태를 폐기하고 Master도 미완성 수신을 반영하지 않습니다.
- 정상 전송은 상승·하강 각각 80회입니다. 마지막 Bit는 80번째 상승에서 읽고 대응 하강까지 유지합니다.
- 추가 Clock: Slave는 MISO=0으로 두고 다음 CS_n High를 기다립니다. Master가 외부 SCLK Glitch를 검출한다는 보장은 없습니다.
- Master Reset: CS_n=1, SCLK=0, MOSI=0. 미완성 전송을 취소하고 Gap 후 재요청합니다.
- Slave Reset: 값·Valid·전송 상태 초기화. CS_n LOW이면 MISO=0, High 관측 뒤 새 명령을 받습니다.
- Master·Slave는 각 System Clock으로 선택 Timeout을 셉니다. SCLK 정지·Byte 경계에서 다시 시작하지 않습니다.
- 2ms 초과 시 Master는 강제 CS 해제·수신 폐기, Slave는 MISO=0·CS High 대기로 복구합니다. 두 Timeout의 발생 순서는 보장하지 않습니다.
- Reset·오류 후 새 요청은 High gap을 거쳐 Command부터 시작합니다. Frame 끝의 Slave Reset은 이미 수신한 정상 응답과 구별하지 못할 수 있습니다.

## Golden Test Vector

<details>
<summary>공통 시험 조건과 G1~G21 펼쳐보기</summary>

MOSI는 `01 00 00 00 00 00 00 00 00 00`으로 공통입니다. MISO에는 첫 무시 Byte를 포함합니다.
아래 값은 Testbench 주입값이며 실물 측정값이 아닙니다. 각 사례는 독립 초기 상태·충분히 작은 센서 Age를 기준으로 합니다.
G9/G13/G15/G20은 Master 검사 경로의 오류 주입이며 실제 Slave가 오류 Frame을 생성해야 한다는 뜻은 아닙니다.
정상 종료·중단 후 CS hold/Gap을 지키고, Reset·Timeout은 앞 절의 강제 종료 예외를 따릅니다.

| ID | 초기 Sensor State | 예상 MISO 전체 | Master 예상 |
| --- | --- | --- | --- |
| G1 | 둘 다 Valid, 23.5°C / 60.0% / 291cm | 00 A5 03 00 EB 02 58 01 23 35 | 세 값 일치, Byte Order 확인 |
| G2 | 둘 다 Valid, -5.5°C / 45.2% / 123cm | 00 A5 03 FF C9 01 C4 00 7B 2E | 음수 부호·소수 및 세 값 일치 |
| G3 | Reset 직후, 모두 0·Invalid | 00 A5 00 00 00 00 00 00 00 A5 | Frame 정상, 센서 둘 다 미준비 |
| G4 | G1 저장값, DHT 실패 | 00 A5 02 00 EB 02 58 01 23 34 | 거리만 Valid, 이전 온습도를 정상 표시하지 않음 |
| G5 | G1 저장값, 거리 실패 | 00 A5 01 00 EB 02 58 01 23 37 | 온습도만 Valid |
| G6 | Valid, 0.0°C / 0.0% / 2cm | 00 A5 03 00 00 00 00 00 02 A4 | 0을 Invalid로 오인하지 않음 |
| G7 | Valid, 60.0°C / 100.0% / 400cm | 00 A5 03 02 58 03 E8 01 90 86 | 제안 범위 상한과 16-bit Decode 확인 |

추가 공통 조건:

| ID | 동작 / 주입 | PASS 조건 |
| --- | --- | --- |
| G8 | G1 Snapshot 뒤 센서값을 G2로 갱신 | 현재 Frame=G1, 다음 새 Transaction=G2. 같은 Clock Edge에 갱신되면 이전 값 사용 |
| G9 | G1의 TEMP_L만 EB→EA로 바꾸고 XOR는 35 유지 | Frame 검사 실패, 수신 결과 미반영 |
| G10 | 37 Clock 뒤 CS_n 상승, 이후 G1 정상 요청 | 중단 결과 미반영, 다음 요청은 G1로 정상 복구 |
| G11 | CS_n High gap=10µs로 G1 요청 두 번 | 매번 80 Clock, 두 응답 모두 G1, Bit 위치 누적 없음 |
| G12 | Command FF와 Dummy 9 Byte | MISO 10 Byte 모두 00, Master Header 검사 실패 |
| G13 | Slave 없음 / MISO를 0 또는 1에 고정 | Header 검사 실패. 이 조건의 오류 원인을 배선으로 단정하지 않음 |
| G14 | 요청 시작 후 첫 응답 Header 전에 Slave Reset | 미준비·오류 응답 처리, CS High 후 새 요청에서 G3로 복구 |
| G15 | G1의 HUM을 1001로 변경: MISO `00 A5 03 00 EB 03 E9 01 23 85` | Checksum이 맞아도 범위 오류로 거절 |
| G16 | 독립 시험 A: 거리 Age를 250ms 전후로 조절하고 DHT는 Fresh 유지. B: DHT Age를 3s 전후로 조절하고 거리는 Fresh 유지 | 대상 Age가 경계 직전이면 STATUS=03, 경계값이면 A=01 / B=02. 경계에서 취한 Snapshot 이후의 갱신은 현재 응답을 바꾸지 않음 |
| G17 | 독립 시험 A(Slave): 시험 Master가 CS LOW를 유지하고 SCLK를 멈춰 2ms 초과. B(Master): System Clock은 유지하고 SPI 진행을 정지시키는 오류 주입 | A: Slave MISO=0·High 대기. B: Master 수신 폐기·CS 해제. 둘 다 다음 G1 정상 복구. 동시 연동에서 Timeout 발생 순서는 검사하지 않음 |
| G18 | G1 전송 중 SCLK High에서 Master Reset 후 재요청 | 현재 결과 미반영, CS High·SCLK Low·High gap 복구 후 G1 정상 응답 |
| G19 | Slave 시험: G1 응답 뒤 CS 유지·81번째 완전한 Clock 추가. Master 시험: 자체 정상 전송 길이 관측, 검사 경로에 잘못된 완료 길이 주입 | Slave 추가 MISO=0·새 Command 미시작·다음 G1 복구. Master 정상 출력은 80주기이며 내부에서 보고된 잘못된 완료 길이는 거절. 외부 SCLK Glitch의 검출 시험은 아님 |
| G20 | G1 STATUS에 bit2 추가: MISO `00 A5 07 00 EB 02 58 01 23 31` | XOR가 맞아도 Reserved Bit 오류로 거절 |
| G21 | Valid, -20.0°C / 0.0% / 2cm: MISO `00 A5 03 FF 38 00 00 00 02 63` | TEMP=-200 하한값·부호 확장 확인. 실물 측정값이 아닌 주입값 |

G1~G7·G21의 길이·부호·단위·XOR와 G9/G15/G20의 오류 조건은 정적으로 확인했습니다.
위 Vector는 공통 수락 기준입니다. 실제 실행한 Master 항목과 Slave의 미검증 범위는 [설계·검증](implementation.md#검증-결과)을 참고합니다.

</details>

## 기준 자료

[Digilent Basys3 Reference Manual](https://digilent.com/reference/_media/reference/programmable-logic/basys-3/basys3_rm.pdf) ·
[공식 XDC](https://raw.githubusercontent.com/Digilent/digilent-xdc/master/Basys-3-Master.xdc) ·
[Artix-7 전기 사양](https://docs.amd.com/v/u/en-US/ds181_Artix_7_Data_Sheet)

Wire Format·Pin·Timing을 변경할 때는 Master·Slave·배선·시험 Vector를 함께 검토하고 Revision을 갱신합니다.
