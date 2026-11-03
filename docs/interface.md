# Master / Slave Interface Contract — Rev.1

대상: Basys3 두 대, 사용자 Master / 팀원 Slave. 작성일: 2026-11-03.
Rev.1 승인 당시 양쪽 기능 RTL은 미구현 상태였고 OLED는 GND/VCC/SCL/SDA 4핀임을 사용자가 확인했다.
사용자 승인일: 2026-11-03. 양쪽 구현이 따라야 하는 Rev.1 Baseline이다.
사용자 승인은 실제 팀원 RTL·Hardware 호환성 검증이나 실물 전기 조건 확인을 의미하지 않는다.

## 설계 선택

- 보드 간 전용 4-signal SPI: CS_n / MOSI / MISO / SCLK와 GND. MOSI는 읽기 명령, MISO는 센서 응답에 사용.
- Mode 0, MSB-first, 100kHz. 100MHz System Clock 기준 Half-period 500 Cycle로 충분한 동기화 여유를 확보한다.
- 센서값은 16-bit 경계의 고정 단위로 정규화해 센서 Driver 내부 형식을 Wire Format에서 분리한다.
- 센서는 Slave가 독립 갱신하고 Master는 저장된 Snapshot을 읽는다. SPI 요청으로 센서 측정을 시작하지 않는다.
- OLED는 별도의 I2C로 연결한다. 4핀 모듈에 SPI를 강제하지 않는다.

## Physical Interface

양쪽 JB를 전용으로 사용한다. Signal은 같은 이름끼리 연결하며 MOSI와 MISO를 교차하지 않는다.
JB1~5는 Connector Pin 번호이고 A14 등은 FPGA Package Pin이다. 보드 실크·공식 도면으로 방향을 확인한다.

| Signal | Master | Slave | Package Pin (양쪽 동일) | Direction |
| --- | --- | --- | --- | --- |
| spi_cs_n | JB1 | JB1 | A14 | Master → Slave |
| spi_mosi | JB2 | JB2 | A16 | Master → Slave |
| spi_miso | JB3 | JB3 | B15 | Slave → Master |
| spi_sclk | JB4 | JB4 | B16 | Master → Slave |
| GND | JB5 | JB5 | FPGA Signal Pin 아님 | 공통 기준 |

- Signal IOSTANDARD: LVCMOS33. 양쪽 보드는 각각 USB로 전원 공급한다. JB6/12의 3.3V 전원은 보드 사이에 연결하지 않는다.
- Slave의 CS_n에 Slave 3.3V 기준 외부 10kΩ Pull-up을 둔다. Master 미설정 시 비선택 상태를 유지하기 위한 설계 선택이다.
- Master의 MISO에 외부 10kΩ Pull-down을 둔다. Slave 미연결·비선택 상태의 부동 입력을 줄이기 위한 선택이며 연결 검출을 보장하지 않는다.
- Slave는 CS_n=1이면 MISO를 High-Z로 해제한다. 선택·해제 후 출력 enable/disable 응답은 1µs 이내로 한다.
- 초기 검증은 짧은 점퍼선(목표 20cm 이내)으로 한다. 이 길이가 동작을 보증하는 Datasheet 사양은 아니다.
- JA/JC는 보드 간 링크에서 사용하지 않는다. Master OLED는 JA1(SCL)·JA2(SDA)·JA5(GND)·JA6(3.3V)를 사용한다. 센서 Pin은 Slave 담당 범위이며, 전체 JB는 다른 주변장치와 공유하지 않는다.
- 실물 보드 Revision, OLED 전원·Pull-up, DHT11 전원·Pull-up, HC-SR04 Echo 전압·변환 회로는 실제 연결 전 확인한다.
- 이 링크는 양쪽 보드가 정상 전원·설정 상태인 조건의 설계다. 한쪽이 꺼진 채 다른 쪽이 신호를 구동하는 조건의 I/O 보호·전원 순서는 별도 확인 대상이다.

Pin 근거: Digilent Basys3 Reference Manual §9 / Table 6 및 공식 Basys-3-Master.xdc.
Rev.1 승인 당시 해당 JB Pin은 주석 상태였다. 현재 Master Top의 Pin 반영·검증 상태는
[설계 및 검증](implementation.md#보드-top-검증-결과)에 정리한다. Wire Contract 변경은 없다.

## SPI Timing

아래 수치는 이번 시스템의 제안 조건이며 Basys3의 보장된 외부 SPI 성능 사양이 아니다.

| 항목 | 규칙 |
| --- | --- |
| Mode | CPOL=0, CPHA=0 |
| Idle | CS_n=1, SCLK=0, MOSI=0, Slave MISO=Z |
| Bit order | Byte 내부 MSB-first |
| Clock | 목표 100kHz, High/Low 각각 nominal 5µs, 최소 4.5µs |
| Sampling | 양쪽 수신자는 SCLK 상승 Edge의 Bit를 수신 |
| Change | 송신자는 SCLK 하강 Edge 이후 다음 Bit를 출력 |
| MOSI setup / hold | Slave SCLK 입력의 상승 Edge 기준 각각 최소 1µs |
| MISO setup / hold | Master SCLK 출력의 상승 Edge 기준 Master MISO 입력에서 각각 최소 1µs |
| MISO delay | Slave SCLK 입력의 하강 Edge부터 MISO 출력 유효까지 최대 1µs |
| CS setup | CS_n 하강부터 첫 SCLK 상승까지 최소 5µs |
| CS hold | 마지막 SCLK 하강부터 CS_n 상승까지 최소 5µs |
| CS High gap | SCLK=0으로 다음 Transaction 전 최소 10µs |
| Transaction | CS_n LOW 한 번에 10 Byte, 정확히 80 Clock, Byte 사이 별도 Pause 없음 |
| Duration | 선택 구간 nominal 약 0.8ms. CS_n LOW 최대 2ms 이내에 종료 |

첫 Command Bit는 CS setup 동안 준비한다. Command 구간의 MISO는 0이며 첫 응답 Byte는 Command 다음 Byte다.
Command의 8번째 상승 Edge에서 요청을 수신하고, 뒤따르는 하강 Edge에서 첫 응답 Bit를 준비한다.
첫 응답 Bit(A5의 Bit7=1)는 전체 9번째 상승 Edge에서 읽는다. 응답 중 매 Byte마다 CS_n을 올리지 않는다.
Data 변경·Setup/Hold 규칙은 정상 선택 구간에 적용한다. CS 전환에 따른 출력 Enable/High-Z,
Reset·Timeout에 의한 MISO=0 전환은 예외이며 새로운 정상 Data Bit로 해석하지 않는다.

CDC 구현은 아직 정하지 않았다. Slave의 독립 100MHz Clock으로 외부 SCLK·CS_n을 동기화해 Edge를 검출하고
안정된 MOSI 구간에서 읽는 방식이 우선 검토 대상이다. Master도 MISO의 비동기 경계를 처리해야 한다.
SCLK Detect→MISO 출력은 위 1µs 이내를 만족해야 한다. 별도 센서 Clock Domain의 Multi-bit 값을
각 Bit별 Synchronizer로 옮기는 것은 Snapshot 일관성을 보장하지 않으므로 Handshake 등 별도 검토가 필요하다.
배선 왕복 지연·Skew 예산은 합계 0.5µs 이하를 목표로 하고 Master 입력 동기화 지연은 0.1µs 이하를 검토한다.
최소 Half-period 4.5µs에서 Slave 1µs와 위 예산을 빼면 선행 안정 시간은 2.9µs다.
요구 Setup 1µs까지 제외한 잔여 예산은 1.9µs다. 동기화 지연을 보수적으로 비용에 포함한 정적 예산이다.
이는 실측이나 Timing Closure 결과가 아니며 구현 시 실제 경로·제약·파형으로 확인한다.

## Transaction과 Byte Format

Master TX는 `01 00 00 00 00 00 00 00 00 00`으로 고정한다.
`01`은 READ_SENSORS이며 이후 9개 Byte는 Clock 제공용 Dummy다. Slave는 응답 구간의 MOSI를 해석하지 않는다.
Command 구간의 MISO 1 Byte는 수신 데이터에서 제외한다.

| 전체 Byte index | MOSI | MISO |
| --- | --- | --- |
| 0 | 01 (READ_SENSORS) | 00 (무시) |
| 1 | 00 | A5 (고정 Header) |
| 2 | 00 | STATUS |
| 3 | 00 | TEMP_H |
| 4 | 00 | TEMP_L |
| 5 | 00 | HUM_H |
| 6 | 00 | HUM_L |
| 7 | 00 | DIST_H |
| 8 | 00 | DIST_L |
| 9 | 00 | XOR |

- TEMP: signed 16-bit Two's complement, 0.1°C 단위. 예: 235→23.5°C, -55→-5.5°C.
- HUM: unsigned 16-bit, 0.1%RH 단위. 예: 600→60.0%RH.
- DIST: unsigned 16-bit, 1cm 단위. 예: 291→291cm.
- Multi-byte는 High Byte 먼저. 센서 표현을 단위값으로 변환하는 책임은 Slave에 있다.
- 소수 정밀도가 더 높은 Driver는 0 방향으로 절삭해 Wire 단위로 변환한다. 음수 온도도 같은 규칙이다.
- DIST는 cm 변환 후 소수부를 버린다. 통신 표현의 분해능이며 센서 측정 정확도를 주장하는 수치가 아니다.
- XOR는 A5부터 DIST_L까지 8개 Byte의 Bitwise XOR다. 응답 9개 Byte 전체 XOR가 0이어야 한다.
- XOR는 단순 오염 검사용이다. 여러 Bit 오류·우연한 동일 Checksum·Replay를 모두 검출하지 못하며 물리 연결이나 최신 데이터의 증명이 아니다.

## STATUS, 센서 갱신과 Snapshot

STATUS bit0=DHT_VALID(온도·습도 공통), bit1=DIST_VALID. bit7:2는 항상 0.

- Reset 시 STATUS=0, 모든 저장값=0. 센서 초기화 중에도 읽기에 즉시 응답한다.
- 센서 수집 성공은 Driver의 통신·Checksum 등 해당 검사와 아래 정상 범위 검사를 통과한 경우다.
  범위 초과도 센서 실패로 처리한다. 성공 시 해당 값 전체와 Valid를 같은 Sensor Update 사건으로 반영한다.
- 수집 실패 시 해당 Valid=0, 마지막 성공값은 보존한다. 실패 후 새 성공 전에는 다시 Valid=1로 만들지 않는다.
- Age는 Slave가 성공값을 저장한 시점부터 센다. DHT는 3초 이상, 거리는 250ms 이상이면 Valid=0이다.
  단위 변환 완료 시점 기준이며 DHT11 내부의 실제 측정 시각을 뜻하지 않는다. 실패·SPI 읽기로 Age를 초기화하지 않는다.
  Age 만료 뒤 Counter Wrap으로 다시 Valid가 되는 동작은 허용하지 않는다.
- DHT는 전원 인가 후 최소 2초 대기하고, 매 통신 종료(성공·실패) 후 최소 2초 대기한 다음 재요청한다.
  따라서 시작 간격을 정확히 2초로 고정하지 않는다. 거리 수집의 시작 간격은 100ms를 제안한다.
  이 간격과 Age 만료값은 설계 정책이며 실제 센서 문서의 제한을 완화하지 않는다.
- Valid=1인 정상 값 범위: TEMP -200..600, HUM 0..1000, DIST 2..400. 센서가 지원하는 범위는 이보다 좁을 수 있다.
- Master는 Header / 길이 / Reserved Bit / XOR와, Valid=1인 필드의 범위를 확인한다. Valid=0인 필드는 수치 검사를 생략하고 정상 측정값으로 표시하지 않는다.
- 통신 형식 오류와 센서 Invalid는 구분한다. STATUS=0이라도 형식이 맞으면 유효한 '센서 미준비' 응답이다.

Snapshot은 Slave의 100MHz 저장 Domain에서 READ 명령이 확정되어 Snapshot을 취하는 사건이다.
외부 SCLK의 물리적 상승 시각과 CDC 처리가 끝난 내부 명령 확정 시각을 동일하게 가정하지 않는다.
Slave는 이 사건에서 STATUS와 6개 Data Byte를 한 번에 고정한다. 전송 중 센서값이나 Valid가 바뀌어도
해당 응답에는 반영하지 않는다. 같은 Slave Clock Edge에서 Sensor Update와 Snapshot이 겹치면 이전에 완료된 값을 사용하고
그 Update는 다음 Snapshot부터 반영한다. Age 검사도 그 Clock Edge 직전의 저장 상태에 적용하며
`응답 Valid = 저장 Valid && (저장 Age < 만료값)`으로 판정한다. 따라서 저장 Age가 정확히 경계값인
Snapshot은 Invalid다. 그 Edge에서 새 성공값이 저장되더라도 다음 Snapshot부터 Valid가 된다.
실패가 같은 Edge에 발생한 경우에도 이번 Snapshot은 이전에 완료된 결과이고 다음 것부터 Invalid다.
센서 성공·실패 이벤트는 같은 센서에 대해 동시에 발생하지 않게 정의해야 한다. 응답 동안 센서 측정 자체를 막을 필요는 없다.
온습도 한 쌍은 같은 DHT 측정 결과이고, 거리는 별도 최신 측정이다. 세 값의 실제 측정 시각이 같다는 의미는 아니다.
응답 Valid는 Snapshot 시점의 판단이다. 전송 중 만료되더라도 현재 응답은 바꾸지 않으며,
Master가 응답을 오래 보관해도 계속 유효하다는 뜻은 아니다. Master의 수신 정지·통신 오류 시 표시 무효화 정책은 Architecture에서 정한다.
Master는 정확한 길이의 응답 수신과 CS_n 해제를 완료하고 Frame 확인 뒤에만 결과를 반영한다.
센서별 Valid도 같은 결과와 함께 갱신한다. 형식 오류 시 새 수치로 덮어쓰지 않으며 이전 수치를 최신 정상값처럼 표시하지 않는다.
구체적인 오류 표시·유지·재시도 정책은 Architecture 단계에서 정한다.

## 중단 / Reset / Recovery

- Unknown Command: Command 다음 모든 MISO Bit는 0. 다음 CS_n High까지 다른 Command를 찾지 않는다.
- CS_n 조기 상승: Slave는 Byte·Bit 위치와 Snapshot 전송 상태를 폐기한다. Master는 미완성 Frame을 반영하지 않는다.
- 정상 Transaction은 80개의 완전한 SCLK 주기(상승 80회·하강 80회) 후 CS hold를 거쳐 끝난다.
  응답의 마지막 Bit는 80번째 상승 Edge에서 읽고 대응하는 하강 Edge까지 유지한다.
- 응답 완료 뒤 추가 Clock: Slave MISO는 0이고 새 Transaction을 시작하지 않는다. 81번째 상승 Edge 하나만 더 있어도
  규약 밖의 Transaction이다. Slave는 이미 보낸 Frame을 회수할 수 없다. Master는 CS 해제 후
  자신이 수행한 전송 완료 정보와 수신 길이가 정확히 80주기·10 Byte인지 확인한다.
  출력 전용 SCLK 선의 외부 Glitch까지 Master가 관측·검출한다고 보장하지 않는다.
- 다음 Transaction은 항상 CS_n High gap 후 Command부터 새로 시작한다. 이전 Byte나 Bit를 이어 쓰지 않는다.
- Master Reset: CS_n=1, SCLK=0, MOSI=0으로 돌아간다. 미완성 수신은 폐기하고 Reset 해제 후 High gap을 지킨다.
  Master Reset·Timeout의 강제 종료는 정상 CS hold나 SCLK=0에서의 CS 전환 규칙의 예외이며, 해당 Transaction은 반영하지 않는다.
- Slave Reset: 저장값·Valid·현재 전송 상태를 초기화한다. CS_n이 LOW이면 MISO=0으로 두고 CS_n High를 관측한 후에만 새 Command를 받는다.
- Slave Reset 도중의 응답은 정상 동작 대상으로 보장하지 않는다. Reset이 Frame 끝에서 일어나면 Master가 이미 받은 정상 Frame과 구분할 수 없을 수 있다.
- 센서 Update가 늦어도 SCLK를 늘이거나 멈추게 하지 않는다. 저장값과 STATUS로 응답한다.
- Sensor Invalid 또는 Frame 오류 후 재시도는 새 Transaction으로 한다. 반복 간격과 사용자 표시 정책은 Master Architecture에서 정한다.
- 100kHz의 정상 Transaction은 2ms 안에 완료한다. Master는 자기 요청이 2ms를 넘으면
  CS_n=1, SCLK=0, MOSI=0으로 강제 복귀하고 수신을 폐기한다. SCLK High에서의 Timeout도 같은 규칙이다.
  Slave도 CS_n LOW가 2ms를 초과하면 MISO=0으로 두고 High를 기다린다. 시간은 각 보드의 System Clock으로 세며
  SCLK 정지나 Byte 경계에서 Timer를 재시작하지 않는다. 비정상 중단 후에는 SCLK=0과 High gap을 회복한 뒤 재요청한다.
  두 Timeout은 독립 Clock 기준이므로 어느 쪽이 먼저 끝나는지는 보장하지 않는다.
  Slave는 자체 Timeout 전에 CS 해제를 관측하면 일반 중단으로 복구해도 된다. 정상 복구는 어느 경로에서도 동일하다.

## Golden Test Vector

정상 명령은 위 10 Byte MOSI를 공통 사용한다. 아래 MISO에는 Command 구간의 무시 Byte `00`도 포함한다.
수치는 Testbench에 주입하는 값이며 실물 측정 결과가 아니다. G8 이후 조건의 CS 전환도 SCLK=0에서 수행하고
정상 종료·중단 뒤에는 같은 CS hold / High gap 규칙을 적용한다. Master Reset·Timeout은 위 예외를 적용하되 복구 후 High gap은 지킨다.
Slave Testbench는 요청에 대한 응답·경계·Snapshot·복구를, Master Testbench는 수신·검사·결과 반영을 비교한다.
G9/G13/G15/G20은 Master 측 오류 주입 조건이며, 실제 Slave가 잘못된 Frame을 생성해야 한다는 뜻이 아니다.
별도 지정이 없으면 각 사례는 독립 초기 상태로 시작하고 센서 Age는 충분히 작게 둔다.
시험에 명시하지 않은 센서 갱신·실패·자동 측정 사건은 주입하지 않는다.

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

정적 검토에서는 G1~G7의 Byte 수·Two's complement·단위 변환·XOR, G9의 단일 Bit 오염,
G15/G20의 정상 XOR와 의미 오류, G21의 하한값 Encoding도 계산했다. Pin 일치·중복 및 Timing 예산도 정적으로 확인했다.
모든 Vector는 양쪽 Testbench의 Acceptance Criteria다. 현재 Master에서 실행한 항목과
실제 Slave 구현에 남은 검증은 [설계 및 검증](implementation.md)의 실행 결과에 구분한다.

## 근거와 승인 경계

- Board Pin / 전압: https://digilent.com/reference/_media/reference/programmable-logic/basys-3/basys3_rm.pdf
- 공식 XDC: https://raw.githubusercontent.com/Digilent/digilent-xdc/master/Basys-3-Master.xdc
- FPGA 전기 조건: https://docs.amd.com/v/u/en-US/ds181_Artix_7_Data_Sheet
- 센서 Timing / 범위: STEP 1에서 확인한 Aosong DHT11 문서 및 HC-SR04 문서. 위 Wire Format은 이번 설계 제안이다.

이 Contract는 사용자 승인 Baseline이며 실제 양쪽 코드·Hardware 호환성은 미검증이다.
팀원에게 같은 Revision과 Vector를 공유해 구현 기준을 맞춰야 한다. 변경이 필요하면 Master / Slave·배선·검증 영향을
검토하고 사용자 승인 후 Revision과 관련 Vector를 함께 갱신한다. 문서 보존 시점에는 RTL·XDC·Testbench를 구현하지 않았다.
