# Master 설계 및 검증

기준: Interface Contract Rev.1 (`43f9968`), 2026-11-03.
STEP 2의 Wire Format·Pin·SPI Timing·센서 Valid / Age 규칙은 변경하지 않는다.
Architecture Rev.1 사용자 승인일: 2026-11-03. 아래 모듈 구성과 동작은 승인된 구현 기준이다.
이 설계 승인이 모든 모듈의 구현·Simulation·Hardware 검증 완료를 의미하지 않는다.

현재 구현: [spi_master.v](../master/spi_sensor_master.srcs/sources_1/new/spi_master.v),
[sensor_reader.v](../master/spi_sensor_master.srcs/sources_1/new/sensor_reader.v),
[fnd_controller.v](../master/spi_sensor_master.srcs/sources_1/new/fnd_controller.v),
[uart_reporter.v](../master/spi_sensor_master.srcs/sources_1/new/uart_reporter.v)와 내부 `uart_tx`, 독립 Testbench.
보드용 [Top](../master/spi_sensor_master.srcs/sources_1/new/spi_sensor_master_top.v)과
[Reset](../master/spi_sensor_master.srcs/sources_1/new/reset_sync.v)도 구현했다.
[oled_display.v](../master/spi_sensor_master.srcs/sources_1/new/oled_display.v)와 `oled_font`·`i2c_master`를 Top에 통합했다.
현재 전체 빌드와 실물 확인 범위는 아래 OLED 통합 검증에 정리한다.

## 목표와 완료 기준

- SPI 전송, 센서 Frame 해석, 출력의 책임과 상태 소유권이 분명하다.
- 모듈 Handshake·Clock·Reset·Timeout·Snapshot 경계가 서로 맞는다.
- 느린 출력이 SPI를 막지 않고, 잘못되거나 오래된 값을 정상 데이터로 표시하지 않는다.
- Rev.1의 Golden Vector를 Master 독립 검증에 연결할 수 있다.
- 실제 기능이 없는 상태와 설계 제안을 구분한다.

## 구조와 책임

```mermaid
flowchart LR
  SL[팀원 Slave] <-->|SPI Rev.1| SPI[spi_master]
  SPI <-->|고정 Frame / 완료| READER[sensor_reader]
  READER -->|최신 상태| FND[fnd_controller]
  READER -->|상태 갱신| UR[uart_reporter]
  UR --> UT[uart_tx]
  READER -->|상태 갱신| OD[oled_display]
  OD --> I2C[i2c_master]
  I2C <-->|별도 I2C| OLED[4핀 OLED]
```

`spi_sensor_master_top`은 연결, Reset 배포, 표시 선택 입력 동기화, LED 배치만 담당한다.
센서 수집 Driver나 실제 Slave SPI는 이쪽에서 구현하지 않는다. 공통 Tick·FIFO·Bus Arbiter·별도 Frame Decoder 모듈은 만들지 않는다.
기능별 책임이 분명한 단위만 분리하고, 단순 Counter와 검사식은 해당 모듈 내부에 둔다.

| 모듈 | 책임 / 보유 상태 |
| --- | --- |
| reset_sync | 외부 Active-high Reset의 비동기 Assert·동기 Release |
| spi_master | CS·SCLK·MOSI, MISO 동기화·Shift, Bit 수, Setup/Hold/Gap, 2ms 선택 Watchdog |
| sensor_reader | Poll 주기, 요청 Frame, 완료 Frame 검사, 최신 값·Valid·링크 상태·수신 정지 시간 |
| fnd_controller | 표시 선택·숫자 변환·자리 Scan, 한 Scan 동안의 표시 Snapshot |
| uart_reporter / uart_tx | 고정 최대 길이 ASCII 레코드 생성 / 8N1 Bit 전송 |
| oled_display / i2c_master | 초기화·Glyph·화면 갱신 / 주소·ACK·Byte·START/STOP·Bus Timeout |

설계 시작 시 Master에 재사용할 RTL은 없었다. XPR 틀과 XDC 템플릿만 재사용하고, 새 RTL은 아래 단위로 작성한다.
현재 `slave/`에는 팀원이 추가한 빈 `top`과 초기 XPR·XDC가 있다. XPR 생성 버전은 2020.2,
Master는 2026.1이며, Slave를 열어 변환하거나 수정하지 않았다. 실제 기능 호환성은 아직 미검증이다.

## Clock / Reset / 작성 규칙

- 내부 Logic은 Basys3의 100MHz `clk` 하나만 사용한다. SPI SCLK·UART baud·FND scan·I2C는 Counter / Enable로 제어하고 내부 Clock으로 쓰지 않는다.
- `reset_sync`는 2단계 Release 동기화를 사용하고, Power-on 초기화 상태를 Reset Assert로 지정한다. 나머지 Logic은 동기 Active-high `rst`를 공통 사용한다.
- System Clock이 동작하는 조건에서 외부 Reset Assert 후 다음 Clock에 내부 상태와 출력이 Reset된다. Release는 동기화 후 수행한다.
- Reset 출력: SPI CS_n=1/SCLK=0/MOSI=0, UART TX=1, FND 모든 자리·Segment OFF, I2C SDA/SCL 해제, Sensor/Link Valid=0.
- `spi_master`는 Reset 해제 뒤에도 10µs CS High gap을 먼저 보장한 다음 요청을 받는다. 외부 Reset을 Slave로 전달하지 않는다.
- MISO는 `spi_master` 내부 2-FF Synchronizer를 통과시킨 뒤 SCLK 상승 사건에서 수신한다. 동기화 지연을 포함해 Rev.1 Timing 예산을 만족하는지 검증한다.
- 표시 선택 입력은 Top에서 각 Bit를 2-FF 동기화한다. UI 선택용이며 원자적 Multi-bit Data 전달로 취급하지 않는다.
- HDL은 `.v`, Verilog-2001 수준으로 작성한다. 명시적 `wire/reg`, Sequential Non-blocking / Combinational Blocking, `lower_snake_case`, 상수 `UPPER_SNAKE_CASE`, Instance `u_<module>`를 사용한다.
- Tool Attribute가 필요한 Synchronizer는 `ASYNC_REG` 적용과 합성 후 인식을 확인한다. Latch·암묵적 폭 축소·불필요한 Clock Domain을 만들지 않는다.

## spi_master: Frame 단위 전송

Byte별 start/done 왕복으로 CS를 끊거나 Byte 사이 Pause를 만드는 구조를 피한다.
Frame 길이는 Rev.1의 10 Byte(80 Bit)로 고정한다. SPI core는 명령·센서 필드를 해석하지 않고 Raw Frame만 전송한다.
Clock과 Timing 상수는 검증 시 축소 가능한 Parameter로 두되 실제 보드 설정은 Rev.1 값을 사용한다. Runtime 가변 길이는 추가하지 않는다.

| 신호 | 의미 |
| --- | --- |
| start | `busy=0`에서 1 Clock만 발생시키는 요청 |
| tx_frame[79:0] | 수락 Edge에서 복사. 상위 Byte부터 전송 |
| busy | 수락 후 Setup / 전송 / Hold / Gap 동안 1. Reset 후 초기 Gap에도 1 |
| done | Gap까지 끝난 결과 알림, 1 Clock. 성공과 Timeout 모두 발생 |
| error | done과 함께 유효한 Timeout 결과. 다음 수락까지 보존 |
| rx_frame[79:0] | Command 구간의 무시 Byte를 포함한 수신 결과. 다음 수락까지 보존 |
| rx_bits[6:0] | 실제로 내부에서 수신 처리한 Bit 수. 정상 80, Timeout은 진행된 수 |

`start && !busy`에서만 요청을 수락한다. Busy 중 start는 수락하지 않고 큐에 넣지 않는다.
Done을 관측한 Cycle에는 결과가 안정되어 있고 Busy=0이다. 상위는 다음 Cycle 이후 새 요청을 발생시킨다.
수락한 요청 하나에 done은 한 번만 발생한다. Reset은 진행 중 요청을 취소하며, Reset과 초기 Gap 종료만으로 done을 발생시키지 않는다.
정상 전송 중 Timer와 MISO 동기화는 100MHz로 계속 동작하며 SCLK Enable에 묶지 않는다.

제어 상태는 IDLE → CS_SETUP → TRANSFER → CS_HOLD → CS_GAP → IDLE로 둔다.
Reset은 초기 CS_GAP으로 복귀한다. TRANSFER는 Byte가 아닌 80-bit Shift·Bit Counter로 진행한다.
500 System Clock마다 SCLK Half-period를 진행하고 첫 Bit를 첫 상승 전에 준비한다.
마지막 Bit를 수신한 뒤 마지막 하강·Hold·Gap까지 완료해야 정상 done을 낸다.
선택 Watchdog는 CS_n 하강부터 상승까지 세며 2ms 초과 시 즉시 CS_n=1/SCLK=0/MOSI=0,
미완성 결과를 error로 표시하고 Gap을 거쳐 done을 낸다. Watchdog는 SCLK 진행과 독립이다.

## sensor_reader: 요청·검사·데이터 저장

첫 요청은 Reset 후 SPI가 준비되면 시작한다. 이후 요청 시작 간격은 100ms를 목표로 한다.
하나의 sensor_reader만 SPI core를 소유한다. 다른 모듈은 start를 구동하지 않는다.
일반 Poll Timer는 수락한 요청 시작에서 다시 세며, 지연 때문에 밀린 요청을 쌓거나 몰아서 보내지 않는다.
만료 시 SPI가 Busy이면 Pending 요청 한 개만 유지하고 Idle에서 실행한 뒤 새 주기를 시작한다.
SPI 정상 전송은 약 0.8ms이므로 기본 주기에 비해 충분히 짧다. 이 계산은 성능 실측이 아니다.

Controller는 WAIT_POLL / WAIT_TRANSFER / CHECK_FRAME 세 단계로 분리한다.
WAIT_POLL에서 Poll이 Due이고 SPI가 Idle일 때만 요청을 1 Cycle 발생시키고 WAIT_TRANSFER로 이동한다.
TX Frame은 그 수락 Edge까지 유지한다. 초기 SPI Gap 동안에는 첫 요청을 보류한다. Done에서 결과를 복사하고,
CHECK_FRAME에서 검사·상태 반영을 수행한다. 한 번의 요청에 done을 한 번만 소비한다.

| 상위 Bit 구간 | 해석 |
| --- | --- |
| rx_frame[79:72] | 무시 Byte |
| [71:64] / [63:56] | Header A5 / STATUS |
| [55:40] | signed TEMP, 0.1°C |
| [39:24] | unsigned HUM, 0.1%RH |
| [23:8] / [7:0] | unsigned DIST(cm) / XOR |

TX는 `80'h01000000000000000000`. Frame 검사는 Transport error → 길이 80 → Header → XOR → Reserved Bit → Valid 필드 범위 순서로 한다.
범위는 Rev.1 그대로이며 signed TEMP 비교를 unsigned 비교로 바꾸지 않는다. 잘못된 Frame은 부분 반영하지 않는다.

- 정상 Frame: 온도·습도·거리·Sensor Valid를 같은 Clock에 반영하고 `link_valid=1`, `last_error=NONE`, 수신 Age=0.
- STATUS=0도 정상 Frame이다. 링크는 정상이고 센서는 미준비인 상태로 표시한다.
- Frame 오류·Timeout: 이전 숫자 Register는 보존하지만 Sensor Valid와 link_valid는 0. 잘못된 값으로 덮어쓰지 않는다.
- 마지막 정상 형식의 Frame 이후 500ms 이상 새 정상 Frame이 없으면 로컬 Stale로 처리하고 Valid를 지운다.
- 수신 Age는 CHECK_FRAME에서 성공을 반영한 Edge에 0이 되고, 이후 50,000,000번째 100MHz Clock Edge에서 500ms 경계에 도달한다.
  그 Edge에 성공 결과가 없으면 Stale로 반영한다. 성공 Frame만 Age를 초기화하며 Counter 만료 뒤 Wrap으로 다시 Fresh가 되는 것을 허용하지 않는다.
- 센서의 3s / 250ms Age는 Slave의 책임이고, Master의 500ms는 통신 결과의 갱신 여부를 보는 별도 정책이다.
- Reset 직후 숫자·Valid·link_valid는 0이고 오류 표시는 아직 NONE이다. 첫 성공 전에도 500ms 수신 정지 감시는 동작한다.
- 같은 Edge에 Frame 검사 완료와 Stale 판정이 겹치면 성공은 Age=0·link_stale=0으로 반영한다.
  오류이면 Age는 초기화하지 않고 계속 진행해 경계에서 link_stale=1이 되며, last_error에는 그 Frame 오류 이유를 남긴다.
  오류 처리 때문에 Age Counter가 멈추거나 Stale 경계가 계속 미뤄져서는 안 된다.

Data Record는 `temperature[15:0]`(signed), `humidity[15:0]`, `distance[15:0]`,
`sensor_valid[1:0]`, `link_valid`, `link_stale`, `last_error[2:0]`의 Register 묶음이다.
오류 이유는 NONE / TIMEOUT / LENGTH / HEADER / XOR / RESERVED / RANGE / STALE를 각각 0..7로 정의한다.
Raw Debug 전용 `debug_rx_byte[7:0]`는 rx_bits=80인 완료 결과에서만 rx_frame[15:8]로 갱신한다.
미완성 Timeout에서는 기존 Debug Byte를 유지한다. Sensor Record와 별개이며 Frame의 유효성을 보장하지 않는다.

`report_update`는 정상 Frame 수신(값이 같아도 포함), 실패 결과, 첫 Stale 전환에서 1 Cycle 발생한다.
Record와 Pulse는 함께 Register로 갱신되어 다음 수신 Clock Edge에서 소비 가능하고 다음 갱신까지 안정된다.
공통 100MHz Domain 안에서 전체 Record를 같은 Edge에 복사하므로 별도 Multi-bit CDC나 FIFO가 필요하지 않다.
`sample_toggle`은 정상 Frame마다 토글해 Debug에 사용한다.

## 출력과 Backpressure

출력 모듈이 Sensor Reader에 Ready를 돌려주거나 Poll을 멈추는 연결은 두지 않는다.
UART / OLED는 각자 현재 출력용 Snapshot과 Pending 최신 Record 한 개를 보유한다.
Busy 중 Update가 여러 번 오면 Pending을 최신 값으로 대체한다. 현재 메시지·화면에는 섞지 않는다.
Idle로 복귀하는 Edge에 Update가 함께 오면 새 Update를 이전 Pending보다 우선해 다음 출력을 시작한다.
Reset 시 현재 출력 동작과 Pending Valid·길이·위치를 취소한다. Reset 전 Record를 후속 레코드로 재전송하지 않는다.
Payload 배열 전체를 초기화하는 대신 유효 상태와 Index를 초기화해 미사용 내용이 출력되지 않게 한다.
중간 Update가 생략될 수 있는 상태 모니터이며 모든 Poll을 보존하는 Data Logger는 아니다.

### FND

`display_sel[1:0]`은 00=온도, 01=습도, 10=거리, 11=온도로 해석한다.
온습도는 소수 한 자리와 필요 시 Minus, 거리는 정수 cm를 표시한다. Invalid이면 `----`를 표시한다.
FND에는 단위를 넣지 않고 선택 상태와 UART / OLED로 구분한다.
전체 네 자리 Scan 시작에서 선택·값·Valid를 함께 복사해 한 Scan 중 숫자가 섞이지 않게 한다.
자리 갱신 간격 250µs, 전체 Refresh 1ms를 목표로 하며 Active-low an/seg를 사용한다.
자리 전환 시 자리 OFF·Segment 갱신·새 자리 ON 순서로 제어한다. 실제 Ghosting·밝기는 Hardware에서 확인한다.

### UART

TX-only, 115200 baud, 8N1을 사용한다. RX 명령·FIFO·PC 제어 Protocol은 추가하지 않는다.
`uart_reporter`는 최대 64 Byte의 한 줄을 생성하고 `uart_tx`의 `start/data[7:0]/busy/done`으로 한 문자씩 전달한다.
`uart_tx`는 Idle/Start/Data/Stop을 처리하고 Stop Bit가 끝난 후 done을 낸다. Busy 중 start는 수락하지 않는다.
start는 Busy=0에서 1 Cycle만 발생시키고 Data는 수락 Edge에 복사한다. Reporter는 done 이후 다음 Cycle부터 다음 문자를 요청한다.
예: `T=23.5C H=60.0% D=291cm L=OK O=OK` + CRLF. Invalid 센서는 `--`, 링크 오류는 `L=ERR:<reason>`, OLED 오류는 `O=ERR`로 표현한다.
UART Reporter는 Sensor Record 외에 oled_display의 동기 `oled_fault`를 읽기 전용 입력으로 받는다.
report_update 또는 oled_fault 변화 때 현재 Record와 OLED fault를 함께 Pending에 복사한다.
fault 변화 감지용 이전 상태도 Reset에서 지운다. 이 상태 경로는 sensor_reader나 SPI 제어로 되돌아가지 않는다.
Reset 후 첫 메시지 앞에 CRLF를 보내 중단된 이전 텍스트와 새 레코드를 분리한다.
64 Byte의 8N1 전송은 nominal 약 5.56ms로 100ms Poll 간격보다 짧다. 단위 변환은 정수 연산으로 한다.

### OLED / I2C

`oled_display`는 초기화, 숫자·문자 Glyph, 페이지별 Byte 생성을 담당하고 `i2c_master`는 Bus Timing과 ACK를 담당한다.
I2C는 우선 100kHz, Write-only 사용, SDA/SCL은 Low 구동 또는 해제로 제어하고 실제 Pin을 읽어 ACK·Bus 상태를 확인한다.
사용자가 SSD1306·128×64·GND/VCC/SCL/SDA 4핀을 확인했다. 모듈 주소·실제 Pull-up 전압과 Power-on Reset 동작은 미확인이다.
I2C는 Page별 Control+128 Byte, Payload 최대 129 Byte·Packet Watchdog 20ms로 정했다.
4핀에는 외부 Reset이 없으므로 OLED 화면 Controller에서 초기화·전원 조건을 따로 검증한다.
전체 Framebuffer 없이 현재 Record에서 Glyph / Page Byte를 순차 생성한다.
고정 Snapshot은 전송 생성 중 Data 일관성을 뜻한다. 페이지 쓰기 중에는 화면의 이전·새 영역이 함께 보일 수 있고,
4핀 모듈에는 FR 동기화 신호가 없으므로 화면 전체의 원자적 전환이나 Tearing 방지를 보장하지 않는다.

`i2c_master`의 Packet start/busy/done/error와 `tx_valid/tx_ready/tx_data[7:0]/tx_last`로 Byte를 공급한다.
Valid가 Ready로 수락될 때까지 Data/Last를 유지한다. SPI와 달리 I2C Byte 사이의 준비 대기는 SCL LOW 구간에서 처리한다.
주소+Write, 각 Byte ACK, 마지막 Byte 뒤 STOP을 처리한다. NACK / Bus Timeout이면 해당 갱신은 실패로 종료한다.
SCL LOW 대기·Bus Busy가 끝나지 않아도 내부 Watchdog는 System Clock으로 동작하며 실패 시 SDA/SCL 구동을 해제한다.
장애 상태에서 무조건 정상 STOP이 만들어졌다고 보고하지 않는다. 초기화·화면 갱신 중 어떤 Packet이라도 실패하면
현재 갱신을 중단하고 fault를 유지한다. 실패한 Byte부터 이어 쓰지 않고 500ms 대기 후 재초기화·전체 갱신을 재시도한다.
대기 중 Pending은 계속 최신 Record로 바뀌며, 재시도 때 최신 Snapshot을 사용한다. 재초기화와 전체 갱신이 모두 성공해야 fault를 지운다.
OLED 실패는 OLED fault로만 표시하고 Sensor Valid / SPI link 상태를 지우지 않는다. OLED 미연결이어도 나머지 기능은 진행한다.
I2C가 끊기면 기존 화면을 지우거나 고장 표시를 쓸 수 없을 수 있다. 이때 OLED 화면의 최신성을 보장하지 않고 LED·UART의 fault를 근거로 판단한다.

## Debug LED

| LED | 의미 |
| --- | --- |
| [7:0] | debug_rx_byte: 80 Bit가 수신된 최근 결과의 DIST_L 위치 Byte. 오류 Frame일 수도 있으며 미완성 Timeout에서는 유지 |
| [8] / [9] | DHT_VALID / DIST_VALID |
| [10] | 정상 Frame 수신 Toggle |
| [11] | OLED fault |
| [12] | SPI busy |
| [13] | last_error가 NONE이 아님: Frame 오류·Timeout·로컬 Stale 포함 |
| [14] | 정상 형식 Frame 수신 정지 500ms 이상 |
| [15] | link_valid: 최근 정상 형식 Frame, 로컬 Stale 아님 |

이 LED의 정상 의미는 운영 상태다. Golden Vector·Timing·Hardware 시험의 PASS를 대신하지 않는다.
표시 선택은 SW[1:0]이며 실제 Package Pin은 아래 Top 검증의 XDC에서 대조했다.

## 제약과 검증 단위

- XDC는 100MHz System Clock(10ns)과 승인 SPI Pin을 실제 Top Port에 반영했다. 외부 I/O 지연은 별도 검증 대상이다.
- SCLK는 내부 FF의 Clock으로 쓰지 않으므로 내부 SCLK Domain을 임의로 만들지 않는다. 외부 I/O 지연과 MISO Synchronizer는 구현 구조에 맞춰 제약·보고서를 검토한다.
- Synchronizer 첫 단계의 비동기 경로만 근거를 갖고 다룬다. 모든 SPI 경로를 통째로 False Path 처리해 Timing 검사를 숨기지 않는다.
- STEP 4: spi_master 독립 검증. 80 Bit·CS 경계·첫/마지막 Bit·MISO 지연·Reset·Timeout·Gap과 Busy 중 요청을 확인한다.
  요청당 done 한 번, Reset 취소 후 done 없음, 초기 Gap 종료의 가짜 done 없음을 포함한다.
- STEP 5: sensor_reader와 Behavioral Slave 검증. Rev.1 G1~G21 중 각 모듈이 책임지는 조건, 원자적 반영·오류·Stale·재요청을 확인한다.
- 이후: LED·UART·FND 독립 및 통합 → 팀원 준비 상태에 따라 고정 Vector 기반 보드 연동 → 실물 확인 후 OLED.
- 느린 UART/OLED, 연속 상태 갱신, 출력 장애 중에도 SPI가 계속 동작하는 것을 통합 검증한다.
  완료와 새 Update가 겹칠 때 최신 Record 우선, Reset 시 Pending 폐기, 오류 Frame과 500ms Age 경계의 동시 발생을 검사한다.
  OLED의 갱신 도중 실패·부분 화면 잔류·재초기화 후 전체 갱신 복구도 확인한다.
- Protocol 오류 Vector는 Master Mock이 주입한다. 팀원 Slave가 일부러 잘못된 응답을 만들도록 구현하지 않는다.
- Behavioral Slave는 Master의 `sim_1`에만 등록한다. Design Source나 실제 Slave 프로젝트의 대체물로 등록하지 않는다.

## 현재 경계와 승인

Wire Contract Rev.1 변경은 없다. OLED는 SSD1306 128×64·JA 연결로 구현했다. 실제 Pull-up 전압·센서 전압 보호·보드 Revision·팀원 구현 호환성은 별도 확인 대상이다.
Architecture 승인은 내부 폭·주기·Frame Mapping·모듈 책임의 정적 검토 결과다.
SPI 전송 Core·Sensor Reader·FND·UART를 아래 범위로 실행·검증했다. 전체 시스템의 실물 검증 완료를 뜻하지 않는다.
이후 기능은 각각 승인된 STEP에서 구현한다.

## SPI 전송 Core 검증 결과

확인일: 2026-11-03, Vivado / XSim 2026.1, `xc7a35tcpg236-1`.
실행: `python scripts/verify_spi_master.py`, 합성: 같은 명령에 `--synth` 추가.
실행 스크립트는 [verify_spi_master.py](../scripts/verify_spi_master.py)이며 Repository 밖 CWD에서도 경로를 해석한다.

| 확인 항목 | 실제 결과 |
| --- | --- |
| Self-checking Simulation | `SPI_MASTER_TEST_PASS cases=15 accepted=20 completed=15 cancelled=5` |
| 전송 | Mode 0·MSB-first·80회 상승/하강·Byte 간 Pause 없음·TX 수락 시 고정·첫/마지막 RX Bit |
| Timing | Half-period 5µs, CS setup/hold 5µs, High gap 최소 10µs, 정상 선택 구간 805µs |
| Handshake / Reset | Busy 중 요청 무시·미큐잉, 요청당 done 1회, 초기 Gap 가짜 done 없음, 5개 제어 구간 Reset 취소·재요청 |
| Timeout | SCLK High/Low 각각 진행 Counter를 정지시켜도 Watchdog가 2ms 초과에서 중단·Gap·error 완료·재요청 |
| MISO | 모델 출력 지연 0 / 1µs에서 Frame 수신 확인. Metastability의 물리 특성을 검증한 것은 아님 |
| Out-of-context Synthesis | Error 0·Critical Warning 0·합성 Warning 0, LUT 213·Register 288·Latch 0 |
| Synchronizer | 합성 후 ASYNC_REG 2개 유지 확인. Placement / MTBF 검증은 아님 |
| 합성 후 Timing Report | 10ns 내부 Clock 기준 추정 WNS 5.431ns. 배치·배선 전 결과 |
| 재현성 | 생성 파일 없는 별도 경로에서 외부 CWD로 Simulation 재통과. 현재 XPR 등록은 아래 Sensor Transaction 결과 참고 |

Timing Report 단계의 `Timing 38-242`는 상위 Clock Buffer가 없어 OOC Clock 지연·Skew를
추정할 수 없다는 Warning이다. 임의 Buffer 위치를 넣어 숨기지 않았다. 외부 입력 83개·출력 93개는
I/O Delay가 미지정 상태이며 상위 모듈 통합 전의 검사 범위다. 실제 I/O Timing과 Timing Closure는 미검증이다.
Waveform은 현재 실행 스크립트에서 `tb_spi_master.wdb`로 생성한다. Timing은 Testbench의 Edge 검사로 자동 확인했고 GUI 파형 검토를 수행한 것으로 기록하지 않는다.

Testbench의 Serial Peer는 비합성 Mock이다. 센서 수집이나 실제 Slave 프로젝트를 구현하지 않았으며,
이 SPI Core 시험은 센서 Decode·XOR·Valid·Age를 검사하지 않는다. 해당 Master 검증은 아래 Sensor Transaction 시험으로 구분한다.
이번 단계에서는 XDC·Slave 파일·상위 출력 기능을 수정하지 않았다. 전체 Implementation·Bitstream·Hardware 시험은 수행하지 않았다.

## Sensor Transaction 검증 결과

확인일: 2026-11-03, Vivado / XSim 2026.1. 실행은 `python scripts/verify_spi_master.py --sensor`,
Reader 독립 합성은 여기에 `--synth`를 추가한다. RTL·TB는 2칸 들여쓰기·명시적 Port·`u_<module>` Instance와
필요한 한글 주석을 사용한다. 기존 SPI 코드도 같은 기준으로 정리하고 회귀 시험을 수행했다.

| 시험 | 실행 범위와 결과 |
| --- | --- |
| [Reader 단위](../master/spi_sensor_master.srcs/sim_1/new/tb_sensor_reader.v) | 46건 PASS. Decode·오류 우선순위·Invalid 필드 범위 생략·숫자 보존·원자적 반영·Debug Byte·Toggle·Update Pulse |
| Poll / Age | 수락 기준 주기·Busy 중 단일 보류·지연 후 새 주기·Stale 직전/정확한 경계·포화·시작 시 무응답·반복 오류·경계 동시 성공/실패 |
| [SPI 연결](../master/spi_sensor_master.srcs/sim_1/new/tb_sensor_transaction.v) | 22건 PASS. 실제 spi_master와 비합성 직렬 모델, 100kHz·80 Clock·고정 TX·반복 요청·전송 중 응답 원본 변경 |
| 중단 / 복구 | 37 Clock 및 SCLK High Reset의 결과 폐기, 상대 Header 전 Reset, 실제 Core Watchdog 오류·재요청 |
| Reader 독립 합성 | Error 0·Critical Warning 0, LUT 123·Register 198·Latch 0·BRAM 0·DSP 0 |
| 합성 후 Timing | 10ns 내부 Clock 기준 추정 WNS 4.161ns. 배치·배선 및 상위 I/O Timing은 미검증 |
| 재현성 / XPR | 생성 파일 없는 별도 경로·외부 CWD에서 두 시험 재통과. XPR 읽기 전용 열기·Compile Order·RTL 2개·Simulation 전용 파일 4개 확인 |

단위 시험의 Poll/Stale은 40/200 Cycle, 연결 시험은 1ms/3ms로 줄였다.
RTL 기본값은 100MHz에서 100ms/500ms이며, 실제 시간 길이의 실물 동작을 측정한 결과가 아니다.
Stale Update는 SPI 전송 중에도 발생할 수 있으며 완료 Frame의 반영과 구분한다.

Golden Vector 중 G1~G7·G21의 Decode, G9·G12/G13 응답의 Header 거절·G15·G20의 오류 검사는 Master에서 실행했다.
G8은 모델이 고정한 현재 응답과 다음 응답의 일관성, G10/G18은 부분 전송·Reset 취소,
G11은 반복 전송의 Clock 수·High gap, G14는 상대 Reset 응답의 오류·복구,
G17은 Master Watchdog, G19는 잘못된 완료 길이 거절을 검사했다.
G8/G16의 실제 Slave Snapshot 우선순위·센서 Age 경계, G12의 실제 Unknown Command 처리,
G17/G19의 Slave Timeout·추가 Clock 처리는 팀원 RTL 검증 대상이다. 이 응답 모델로 실제 Slave의 정확성을 증명하지 않는다.

합성의 `Synth 8-3917`은 고정 명령 `spi_tx_frame` 80 Bit의 상수 출력 보고다(합성 요약 Warning 160건).
명령이 상수인 승인 설계와 일치하며 메시지를 숨기지 않았다. `Timing 38-242`와 I/O Delay 미지정
입력 83개·출력 66개는 독립 모듈 검사 범위다. 보드용 Top·제약·배치배선·실제 센서/출력 연동은 미검증이다.

## FND 표시 검증 결과

확인일: 2026-11-03, Vivado / XSim 2026.1. `python scripts/verify_spi_master.py --fnd`로
단위·연결 시험을, `--fnd --synth`로 FND 독립 합성을 실행한다.
`display_sel`은 공통 Clock에 동기화된 입력을 전제로 하며, 실제 Switch 동기화는 보드 Top에서 구현한다.

| 시험 | 실제 결과 |
| --- | --- |
| [FND 단위](../master/spi_sensor_master.srcs/sim_1/new/tb_fnd_controller.v) | 1,032건 PASS. 절댓값 0~1000 전 범위, 음수·부호 위치·소수점·선행 공백·선택 11→온도·센서별 Invalid |
| Scan / Reset | 네 자리 Snapshot 유지, 다음 Scan의 변경 반영, 한 자리만 Enable, OFF→Segment 설정→ON, Reset 시 전부 OFF |
| [SPI→Reader→FND](../master/spi_sensor_master.srcs/sim_1/new/tb_sensor_display.v) | 7건 PASS·SPI 15회 요청. 온습도·거리 선택, 음수, XOR 오류→Invalid, Stale·정상 복구 |
| 기본 주기 | 연결 시험에서 100MHz·SPI 100kHz·자리 250µs·전체 Scan 1ms. Poll/Stale만 1ms/3ms로 축소 |
| 독립 합성 | Error 0·Critical Warning 0, LUT 94·Register 44·Latch 0·BRAM 0·DSP 0 |
| 합성 후 Timing | 10ns 내부 Clock 추정 WNS 5.622ns. I/O 입력 36개·출력 12개 Delay 미지정, 상위 연결 경로·배치배선 Timing 미검증 |
| 재현성 / 회귀 | 생성 파일 없는 별도 경로·외부 CWD에서 재통과. XPR RTL 3개·Simulation 전용 파일 6개·Compile Order 확인. 기존 SPI 15건·Reader 46건·Transaction 22건 PASS |

FND는 Reader가 검사한 Valid와 범위(TEMP -200..600, HUM 0..1000, DIST 2..400)를 사용한다.
변환은 10-bit 절댓값의 Shift/Add-3 BCD이며 소수점은 별도 출력이다. Invalid는 다음 Scan부터 `----`로 반영한다.
`Synth 8-3936`/`8-7129`의 25건은 이 변환에 필요하지 않은 상위 Bit 최적화·입력 부하 없음 보고이며,
`Timing 38-242`는 OOC Clock 위치 미지정 Warning이다. 해당 메시지를 숨기지 않았다.

극성·Segment 순서는 [Basys3 공식 Reference Manual §8.1](https://digilent.com/reference/_media/reference/programmable-logic/basys-3/basys3_rm.pdf)과
등록 XDC 템플릿을 대조했다. Scan 제어는 Simulation으로 확인했으며 실제 밝기·Ghosting을 측정하지 않았다.
Slave는 빈 Top 상태라 조기 보드 연동을 진행하지 않았다. XDC·실제 Slave·보드 Top은 이번 변경에 포함하지 않는다.

## UART 출력 검증 결과

확인일: 2026-11-03, Vivado / XSim 2026.1. 실행은 `python scripts/verify_spi_master.py --uart`,
Reporter와 내부 TX의 독립 합성은 여기에 `--synth`를 추가한다.
100MHz / 868 Cycle의 Bit 시간은 8.68µs(계산상 약 115207.37 baud, 115200 대비 +0.0064%)다.

| 시험 | 실제 결과 |
| --- | --- |
| [Byte TX](../master/spi_sensor_master.srcs/sim_1/new/tb_uart_tx.v) | 259건 PASS. 256개 Byte의 직렬 복호화·868 Cycle/Bit·LSB-first·Stop 완료·Busy 요청 무시·Start/Data/Stop Reset |
| [Reporter](../master/spi_sensor_master.srcs/sim_1/new/tb_uart_reporter.v) | 21건 PASS. Snapshot·최신 Pending 대체·동시 갱신 우선·부호/소수·범위 경계·센서별 Invalid·오류 0~7·OLED fault 변화·64 Byte 이내 길이 |
| Reset 복구 | 현재/대기 메시지 취소. Reset 해제 뒤 한 문자(86.8µs) Idle 유지 후 첫 메시지 앞 CRLF. 수신 모델을 Reset하지 않은 조건도 확인 |
| [SPI→Reader→UART](../master/spi_sensor_master.srcs/sim_1/new/tb_sensor_uart.v) | 4건 PASS·SPI 23회·UART 7줄. 음수·XOR 오류·Stale·정상 복구 중에도 1ms Poll 유지·메시지 내 값 혼합 없음 |
| 합성 / Timing | LUT 1,551·Register 726·Latch 0·BRAM 0·DSP 0, 10ns 내부 Clock 추정 WNS 4.039ns |
| 재현성 / 회귀 | 생성 파일 없는 별도 경로·외부 CWD에서 UART 3개 시험 재통과. XPR RTL 5개·Simulation 전용 파일 10개·Compile Order 확인. 기존 SPI·Reader·FND 시험 모두 PASS |

단위 Reporter만 Bit 시간을 8 Cycle로 줄였고, TX 단위·연결 시험은 기본 868 Cycle을 사용했다.
연결 시험의 SPI는 100kHz이며 Poll/Stale만 1ms/3ms다. 실제 보드·PC 수신 시험은 수행하지 않았다.
Reporter는 수치 변환·필드 생성·메시지 조립을 Register로 나누고, 현재 문자열과 대기 Record 한 개를 소유한다.
초기 CRLF를 포함해 최대 64 Byte이며 Invalid 필드도 단위를 유지한다(예: `T=--C H=--% D=--cm`).
링크 오류는 `L=ERR:<reason>`, OLED 상태는 `O=OK/ERR`로 표시한다. 이 UART 단위 검증에서는 OLED fault를 시험에서 주입했다.

합성은 Error 0·Critical Warning 0이며, `Synth 8-3936` 1건은 10-bit 절댓값 변환에서 상위 Bit가 제거된 결과다.
`Netlist 29-101`은 평탄화된 Reporter의 Primitive 수에 따른 Floorplanning 안내,
`Timing 38-242`는 OOC Clock 위치 미지정 경고다. 모두 숨기지 않았다.
I/O 입력 40개·출력 2개의 Delay는 미지정이며, 배치배선·상위 모듈 연결 Timing Closure는 미검증이다.
실행 스크립트는 합성 후 내부 Setup Slack이 음수이면 실패 처리한다. 이 검사가 외부 I/O Timing 검증을 대신하지 않는다.

## 보드 Top 검증 결과

확인일: 2026-11-03. `python scripts/verify_spi_master.py --top`으로 Reset·전체 Top을 검사하고,
`--top --synth`로 실제 XDC를 읽어 일반 Top 합성(독립 모듈 OOC 아님)을 수행한다.
초기 Top 검증은 OLED 통합 전 `oled_fault=1` 조건이었다. 아래 합성·Pin 결과는 OLED 통합 후 현재 Top으로 갱신했다.

| 항목 | 실제 결과 |
| --- | --- |
| [Reset 단위](../master/spi_sensor_master.srcs/sim_1/new/tb_reset_sync.v) | 6건 PASS. 버튼 없이 Power-on Assert, 비동기 Assert, 두 Clock Release, Clock 정지 중 Assert·Release 보류 |
| [전체 Top](../master/spi_sensor_master.srcs/sim_1/new/tb_spi_sensor_master_top.v) | 10건 PASS·SPI 41회·UART 11줄. FND 선택·2-FF 선택 지연·LED 상태/Toggle·오류/Stale·SCLK High 버튼 Reset·복구 |
| 합성 | Error 0·Critical Warning 0, LUT 2,715·Register 1,649·Latch 0·BRAM 0·DSP 0 |
| 제약 / DRC | 39개 Port 모두 LVCMOS33·Package Pin 지정·중복 없음, 합성 DRC 위반 0 |
| Reset / 동기화 | Power-on Reset FF INIT=1 두 개·ASYNC_REG 12개 유지. MISO 첫/둘째 FF 사이 10ns Setup 경로가 예외로 제거되지 않음 |
| 합성 후 Timing | 내부 WNS 1.822ns·WHS 0.045ns, Unconstrained internal endpoint 0. 배치배선 결과 아님 |
| 재현성 / 회귀 | 생성 파일 없는 별도 경로·외부 CWD에서 재통과. 초기 Top 기준 XPR RTL 7개·Simulation 전용 파일 12개·Top/Compile Order 확인(현재 등록은 아래 참조). 기존 SPI·Reader·FND·UART 시험 모두 PASS |

기본 주기는 SPI 100kHz·UART 868 Cycle/Bit·FND 1ms이며, 통합 시험의 Poll/Stale만 1ms/3ms로 줄였다.
외부 Reset은 동기화 블록에서 비동기 Assert되고, 주변 모듈은 System Clock의 다음 Edge에서 동기 Reset된다.
표시 Switch 두 Bit는 UI 선택용이며 동시에 움직인 Bit의 원자적 전달을 보장하지 않는다. Button Debounce는 추가하지 않았다.

활성 Pin은 [등록 XDC](../master/spi_sensor_master.srcs/constrs_1/imports/digilent-xdc-master/Basys-3-Master.xdc)의 다음 항목이다. Vector Pin 목록은 Bit 0부터 순서다.

| Top Port | 연결 / Package Pin |
| --- | --- |
| clk / btn_c | 100MHz W5 / BTNC U18 |
| display_sel[0] / [1] | SW0 V17 / SW1 V16 |
| spi_cs_n / spi_mosi / spi_miso / spi_sclk | JB1 A14 / JB2 A16 / JB3 B15 / JB4 B16 |
| uart_tx | USB-UART 방향 TX, A18 |
| oled_scl / oled_sda | JA1 J1 / JA2 L2, GND=JA5·3.3V=JA6 |
| seg[6:0] / dp | W7 W6 U8 V8 U5 V5 U7 / V7 |
| an[3:0] | U2 U4 V4 W4 |
| led[15:0] | U16 E19 U19 V19 W18 U15 U14 V14 V13 V3 W3 U3 P3 N3 P1 L1 |

Pin 근거는 [공식 XDC](https://raw.githubusercontent.com/Digilent/digilent-xdc/master/Basys-3-Master.xdc)와
[Basys3 Reference Manual](https://digilent.com/reference/_media/reference/programmable-logic/basys-3/basys3_rm.pdf)이며, 실물 Board Revision은 미확인이다.
False Path는 MISO·Switch·SCL/SDA의 첫 수신 FF와 버튼의 비동기 Reset PRE에 한정한다. 동기화 단계 사이와 나머지 내부 Logic은 검사한다.
입력 Clock/Delay가 없는 경로는 CDC Report에서 생략될 수 있어 Report만으로 전체 CDC 검증이나 MTBF 근거로 쓰지 않는다.

합성 Warning 27건은 FND 미사용 상위 입력과 FND/UART/OLED 숫자 변환 상위 Bit 최적화다. 숨기거나 Severity를 낮추지 않았다.
입력 6개·출력 34개는 외부 Delay 미지정이다. 외부 SPI Setup/Hold·보드 배선·출력 I/O Timing은 아직 검증하지 않았으며,
현재 Pin/Clock 제약과 합성 결과만으로 Timing Closure를 선언하지 않는다. 배치배선 후 결과는 아래에 구분한다.

## 배치배선 및 Bitstream

확인일: 2026-11-03, Vivado 2026.1 Build 6511674, `xc7a35tcpg236-1`.
`python scripts/verify_spi_master.py --top --impl`은 RTL 기본 Parameter와 실제 XDC로
합성 → opt → place → phys_opt → route → 검사 → Bitstream 생성을 실행한다. OLED를 포함한 현재 Top과 JA Pin 제약을 사용했다.

| 항목 | 실제 결과 |
| --- | --- |
| 배선 | 배선 대상 Net 3,569개 모두 연결, Routing Error 0 |
| 내부 Timing | 100MHz 기준 WNS 2.152ns·TNS 0·WHS 0.065ns·THS 0, Unconstrained internal endpoint 0 |
| 배치배선 Resource | LUT 2,690·Register 1,652·Latch 0·BRAM 0·DSP 0 |
| DRC / 동기화 | Routed DRC 위반 0·ASYNC_REG 12개·Reset FF 두 개의 INIT=1 유지. MISO 동기화 단계 사이 Setup 경로 유지 |
| 산출물 | `spi_sensor_master.bit` 657,338 Byte, `spi_sensor_master_routed.dcp`, Timing·DRC·I/O·CDC·배선·예외 Report |
| 재현 / 회귀 | Commit 대상 별도 경로·기본 Parameter로 Implementation·Bitstream 재통과. Simulation 재현은 아래 OLED 검증에 구분 |

산출물은 Git에서 제외한 `master/spi_sensor_master.sim/step9/`에 보관한다.
`build_manifest.json`은 Tool·Part·명령·입력 파일과 `.bit`/`.dcp`의 SHA-256을 기록한다.
빌드 도중 입력이 바뀌면 실패 처리하며, 별도 경로의 입력·산출물 해시와 Commit 대상 Source(줄바꿈 정규화)를 Programming 전에 다시 대조했다.
생성 시각·경로를 포함하는 Binary의 빌드 간 동일 SHA-256을 재현 기준으로 삼지는 않는다.

Setup/Hold 실패, 불완전 배선, DRC 위반, 동기화 Attribute·Reset 초기값 손실은 실행 스크립트에서 실패 처리한다.
합성 Warning 27건의 원인을 확인했고 Critical Warning은 없다. 메시지 Severity나 Timing 목표를 낮추지 않았다.
입력 6개·출력 34개의 외부 Delay가 미지정이다. 내부 Timing 통과를 외부 SPI Timing Closure로 확대하지 않는다.
이 명령은 Bitstream 생성까지만 수행한다. 별도로 SRAM Programming과 Master+OLED·PC 수신을 시험했으며, 실제 Slave·센서 연동은 미검증이다.

## OLED I2C 전송 Core

확인일: 2026-11-03. 첨부 SSD1306 Datasheet §8.1.5의 주소·Control/Data Byte·Byte별 ACK·START/STOP과
Charge Pump Application Note를 검토했다. 설계 전원은 3.3V, 신호는 Open-drain이며 패널 구동용 IC VCC와 모듈 전원 핀을 구분한다.
배치는 SCL=JA1(J1), SDA=JA2(L2), GND=JA5, VCC=JA6(3.3V)로 정했으며, 현재 Top/XDC에 활성화했다.

| 항목 | 구현 / 검증 범위 |
| --- | --- |
| Interface | `start/address[6:0]`, `busy/done/error`, `tx_valid/tx_ready/tx_data[7:0]/tx_last`, 양방향 SCL/SDA |
| Write | 7-bit 주소+W=0, MSB-first, 주소·각 Payload ACK, 마지막 ACK 뒤 STOP·Bus-free. 주소 구간에는 Payload를 수락하지 않음 |
| Timing | 100MHz·Half-period 500 Cycle, High/Low 최소 5µs. SCL 동기화 대기로 주파수는 약 100kHz 이하 |
| 대기 / 한도 | SCL 실제 High 확인 후 High 시간 계수, Byte 공급은 SCL Low에서 대기. Payload 최대 129 Byte |
| 복구 | NACK·한도 초과는 STOP 시도 후 실패 완료. Bus·Clock Stretch·공급 대기는 독립 20ms Watchdog로 종료·양 Pin 해제. 강제 종료 시 물리 STOP을 보장하지 않음 |
| Reset | Pin 해제·상태 초기화·진행 중 요청 취소, 가짜 done 없음. Busy 중 start는 큐에 넣지 않음 |

시험은 [tb_i2c_master.v](../master/spi_sensor_master.srcs/sim_1/new/tb_i2c_master.v)와
`python scripts/verify_spi_master.py --i2c`로 실행한다. 실제 기본 Timing·20ms Timeout을 사용하며 Pull-up·ACK·Clock Stretch는 비합성 모델이다.
16건 PASS. 주소 0x3C/0x3D, Control 0x00/0x40, 129 Byte 정상/한도, 주소·중간·마지막 NACK,
Stretch·공급 대기, Timeout·Reset·재요청을 검사했다. 생성 파일 없는 별도 경로·외부 CWD에서도 재통과했다.
I2C 단독 검증 당시 XPR RTL 8개·Simulation 전용 파일 13개·Compile Order를 확인했고, 기존 Reset 6건·Master Top 10건도 회귀 PASS다.

`--i2c --synth`는 IOBUF 삽입을 포함한 일반 단독 합성이다. Open-drain을 내부 논리로 바꾸는 OOC 방식은 사용하지 않는다.
합성은 Error/Warning/Critical Warning 0, LUT 107·Register 64·Latch 0·IOBUF 2개·ASYNC_REG 4개, 내부 추정 WNS 4.872ns였다.
SCL/SDA의 I/O Buffer와 입력 동기화 Attribute를 검사했으며, 배치배선·실제 OLED의 ACK/화면/전압을 검증한 것은 아니다.
위 단독 Core 결과와 별도로, 현재 Top의 OLED·실물 검증은 아래와 같다.

## OLED 통합 검증

확인일: 2026-11-03. SSD1306 128×64, 5×7 Glyph·8개 Page를 사용한다.
Reset 후 100ms 대기하고 Page addressing·Charge Pump·128×64 설정으로 초기화한다.
VCOMH는 Datasheet 정의값 `DB 20`, Scrolling은 `2E`로 정지한다.
초기 주소 0x3C가 실패하면 500ms 후 0x3D를 시도하며 초기화 성공 주소를 유지한다.
전체 8개 Page를 기록한 다음 `AF`로 Display ON하고 fault를 해제한다.
숫자 변환·문자 선택·Pixel 생성을 Register 단계로 나눠 내부 10ns 목표를 만족한다.

| 검증 | 실제 결과 |
| --- | --- |
| OLED 단위 | 6건 PASS·완료 화면 6회. 초기화·Glyph·나머지 열 지우기·고정 Snapshot·최신 Pending·부분 Page NACK 후 전체 복구·Reset·주소 전환·미연결/복구 |
| Master 통합 | 3건 PASS·SPI 16회·OLED 화면 4회·UART 5줄. SPI 값의 OLED 반영, OLED 오류 중 SPI 지속·UART fault 표시, 재연결 복구 |
| 실제 빌드 | 위 전체 Top 합성·배치배선 결과. 양방향 IOBUF 2개·동기화 FF 12개, Latch/BRAM/DSP 0 |
| 재현 / 회귀 | Commit 대상만 별도 경로로 추출해 OLED 6건·통합 3건·Reset 6건·Top 10건·I2C 16건 재통과 |
| 프로젝트 | Vivado 읽기 전용 열기·Compile Order 확인. RTL 10개·Simulation 전용 16개. Design Top=`spi_sensor_master_top`, Simulation Top=`tb_master_oled` |
| Master+OLED 실물 | `xc7a35t_0` SRAM Programming 성공. 사용자 육안으로 정상 글자와 BTNC Reset 후 재표시 확인 |
| PC 관측 | COM4·115200 8N1. 최초 8초 80줄·Reset 후 5초 50줄·최종 Bitstream 적용 후 3초 30줄, 형식 오류 0. 모두 `T=--C H=--% D=--cm L=ERR:HEADER O=OK` |

`python scripts/verify_spi_master.py --oled`는 비합성 SSD1306 모델의 실제 SCL/SDA와 화면 RAM을 검사한다.
OLED 시험의 Power-up·Retry·I2C 시간을 줄였고, 통합 SPI는 실제 100kHz·UART는 868 Cycle/Bit다.
OLED 미연결·재연결 오류 복구는 Simulation에서만 검증했다.
실물 시험은 준비되지 않은 Slave의 SPI 케이블을 분리한 조건이므로 `HEADER`와 `--`가 정상 기대값이다.
`O=OK`는 모든 OLED Packet의 ACK와 전체 갱신 완료 상태이며, 화면 가독성은 별도 사용자 확인이다.
실제 OLED 주소·Pull-up 전압·상승 시간은 측정하지 않았다. 실제 Slave·센서값·외부 I/O Timing은 미검증이다.
Flash에는 쓰지 않았으며, USB 전원을 다시 넣으면 SRAM Bitstream을 다시 적용해야 한다.
UART 기록 도구는 [capture_uart.ps1](../scripts/capture_uart.ps1), 생성 Capture·Programming Log는 `step11/`에 두고 Git에서 제외한다.
