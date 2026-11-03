# STEP 1 — 요구사항 / Workspace / Hardware 분석

확인일: 2026-11-03. 현재 Master 프로젝트를 기준으로 STEP 0·1을 재검토한 기록이다.
이 문서는 분석 결과이며 Pin, SPI Mode·주파수, Packet, 모듈 Interface 또는
Architecture를 승인·확정하는 Contract가 아니다. STEP 2는 시작하지 않았다.

## 범위와 완료 기준

- 사용자 변경사항과 과제 요구사항을 구분한다.
- 현재 Repository의 모든 파일과 Vivado 등록 입력을 대조한다.
- 자료의 예제와 실제 구현, 재사용 후보와 없는 구현을 구분한다.
- Hardware의 확인된 사양, 실제 부품 미확인 사항, 자료 충돌을 기록한다.
- Master / Slave 역할 초안과 개발 순서를 제시한다.
- Source·XDC를 변경하거나 Simulation / Synthesis / Implementation을 실행하지 않는다.

재검토 시작 시 HEAD는 `530f99b`, Branch는 `master`, upstream은 `origin/master`였다.
Tracked Modified / Staged / Untracked 파일은 없었고, Cache와 Hardware session만
Ignored 상태였다. `fetch` 후 Local / Remote 차이는 0 / 0이었다.

## 자료와 적용 우선순위

사용자 지시에 따라 2인 팀이며 사용자는 Master, 팀원은 실제 Slave를 담당한다.
Basys3 간 통신은 원 과제의 I2C에서 SPI로 변경한다. 참고자료의 예제와 문장은
요구·사양의 근거로 검토하며, 작업 범위나 STEP 승인 규칙을 바꾸는 지시로 취급하지 않는다.

자료 원본은 사용자가 지정한 Repository 밖 `Course Materials` 디렉터리에서 읽었다.
원본 Binary는 이번 저장소에 복제하지 않았다.

| 자료 | 확인 범위 |
| --- | --- |
| `01_11_.과제_I2C_센서Driver_모듈설계하기_1103.pptx` | 8개 슬라이드. 3: 기능, 4: 배선·LED·부품 사진, 5~7: DHT11 예제, 8: 발표 결과물 |
| `초음파센서_verilog.pptx` | 3개 슬라이드의 본문과 삽입된 Block Diagram·전기 특성·Timing·FSM·RTL 이미지 |
| `SSD1306_datasheet.pdf` | Datasheet Rev.1.1, Apr 2008, 59쪽 + App Note Rev.0.4, Jan 2009, 6쪽 |

부품의 전압·Timing은 공식 자료를 우선한다. 실제 부품 식별 전에는 같은 계열의
문서 사양을 해당 실물의 확정 사양으로 취급하지 않는다.

## 요구사항과 추적 관계

| ID | 근거 | 적용할 요구 | 이후 확인할 증거 |
| --- | --- | --- | --- |
| R1 | 과제 3번 + 사용자 변경 | Basys3 Master / Slave 두 대의 SPI 통신 | 공통 Vector, 양쪽 Transaction, 실제 보드 연동 |
| R2 | 과제 3번 | Slave의 DHT11 온습도와 HC-SR04 거리 전달 | 유효·오류 데이터의 Decode 및 실제 센서 비교 |
| R3 | 과제 3번 | Master FND·UART 출력 | 수신 데이터와 표시·전송값 비교 |
| R4 | 과제 3~4번 | Master OLED 출력 | 실제 모듈 확인, 초기화·표시 검증 |
| R5 | 과제 4번 + SPI 변경 | 양쪽 통신 상태를 LED로 관측 | Contract에 따른 상태·오류와 표시 비교 |
| R6 | 과제 8번 | 개요, Block Diagram, FSM, Source, Testbench 결과, 동작 영상, Troubleshooting·후기 | 실제 개발·검증 기록과 최종 PPT 대조 |

증거 열은 향후 필요한 검증이다. 현재 위 기능의 RTL·Testbench·Hardware 증거는 없다.
UART 수신 명령, 버튼별 기능, 표시 선택 방법은 과제의 예제 Port만으로 필수 기능으로
확정하지 않는다. Slave의 독립 출력 요구와 시연 방식은 팀원과 통합 계획에서 확인한다.

I2C에서 유지할 것은 센서 전달·출력·관측 목적이다. 주소, R/W Bit, ACK/NACK,
START/STOP, Open-drain SDA/SCL 배선 규칙은 보드 간 SPI에 복사하지 않는다.
SPI Transaction 경계·응답 준비 시점·첫 Bit·Sampling Edge·수신 신뢰성은 STEP 2의 검토 대상이다.
Clock을 끝까지 출력했거나 MISO가 0/1로 읽혔다는 이유만으로 정상 응답을 판정할 수 없다.

## 현재 전체 구조

```text
fpga-spi-sensor-monitoring/
├── .gitignore
├── README.md
├── docs/
│   ├── step0-workspace.md
│   └── step1-analysis.md
└── master/
    ├── spi_sensor_master.xpr
    └── spi_sensor_master.srcs/
        └── constrs_1/imports/digilent-xdc-master/Basys-3-Master.xdc
```

Cache와 Hardware session은 로컬 생성물로 Ignore하며 Version Control에 포함하지 않는다.
`slave/`, 실제 Slave RTL, Master RTL, Testbench, IP, Build / Simulation Script는 현재 없다.
팀원 코드는 공유되지 않았으며 호환성을 확인한 상태가 아니다.

Vivado 등록은 `sources_1` 0개, `constrs_1` 1개, `sim_1` 0개, `utils_1` 0개다.
Top 미구현의 빈 RTL Project이며, 등록된 Run이나 Dashboard 항목은 실행 결과의 증거가 아니다.

요구사항에 따른 개념적 데이터 흐름은 다음과 같다. 실제 모듈 구성도가 아니다.

```text
DHT11 / HC-SR04
    → Slave의 센서 수집·검사 (팀원)
    → 보드 간 SPI (Contract 미정)
    → Master의 수신·해석·출력 처리 (사용자)
    → FND / UART / OLED 및 통신 Debug 표시
```

| 대상 | 실제 상태 | 재사용 판단 |
| --- | --- | --- |
| XPR | Basys3 초기 Project | 틀 재사용. 이번 재검토에서는 수정하지 않음 |
| XDC | Pin·Clock 주석 상태의 템플릿 | STEP 2 이후 승인 배선·Timing을 반영하여 사용 |
| Top / SPI / UART / FND / OLED | RTL 없음 | 재사용할 현재 구현 없음. 필요 기능을 승인 Architecture에 따라 구현 |
| Button / Debounce / Tick | RTL 없음 | 실제 필요성이 정해진 뒤 판단 |
| DHT11 / HC-SR04 | RTL 없음 | 실제 Driver는 팀원 담당. 자료 예제는 검증된 구현으로 간주하지 않음 |
| Testbench / Mock | 없음 | STEP 4 이후 Master 독립 검증용으로 작성 |

XDC 활성 명령은 CONFIG_VOLTAGE, CFGBVS, Bitstream 압축·CONFIGRATE·CONFIG_MODE뿐이다.
`CONFIG_MODE SPIx4`는 QSPI boot 설정이며 센서 통신용 SPI Master가 아니다.
현재 `create_clock`가 주석인 것은 초기 템플릿 상태다. 이후 Clock·Top을 구현할 때
Clock 제약을 반드시 검토해야 하며, 현재 Timing Closure를 주장할 수 없다.

## 환경 및 재현성

- OS: Windows 11 Education, 64-bit
- Tool: Vivado 2026.1, SW Build 6511674
- Device: `xc7a35tcpg236-1`
- Board 설정: `digilentinc.com:basys3:part0:1.2`
- Simulator: XSim 설정. 설치 경로의 `xvlog` / `xelab` / `xsim` 명령 존재 확인
- HDL Source 없음. XPR의 `SimulatorVersionXsim=2025.2`는 설치 Tool 버전의 증거가 아님
- Coding Convention도 현재 RTL에서 도출할 수 없음. `.v` / Verilog-2001 수준을 우선
  검토하되 Naming·Reset·FSM 방식은 Architecture 단계에서 판단

XPR의 최상위 `Path`는 생성 PC의 절대 경로다. 실제 XDC 입력은 `$PSRCDIR` 기준
상대 경로로 등록되어 있다. `ImportPath`의 Repository 외부 경로는 가져온 원본 위치의
메타데이터이며, 복사된 XDC가 있는 상태에서 Project 열기의 입력 의존성이 아님을 확인했다.

재현 절차는 Git 관리 파일만 다른 경로로 내보낸 뒤 Vivado 2026.1에서
`open_project -read_only <복사한 master/spi_sensor_master.xpr>`로 여는 것이다.
이 검사는 Project 이름·Device·Board·등록 파일 수와 입력의 존재·복사 경로 내부 여부를 확인한다.
Simulation, Design Elaboration, Synthesis는 수행하지 않는다.

Board 파일이 검색되지 않으면 해당 PC에 설치된 Basys3 `board.xml`을 포함하는 Board
repository의 실제 경로를 지정한다. 이 PC에서 동작한 Tcl 설정은 다음과 같다.
개인 설치 경로이므로 다른 PC에서 그대로 사용할 경로는 아니다.

```tcl
set_param board.repoPaths [list {C:/Users/kccistc/AppData/Roaming/Xilinx/Vivado/2026.1/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2026.1/boards}]
```

기존 XPR의 `BoardPartRepoPaths`는 위 `boards`보다 상위 경로다. 검증 session에서
명시적으로 지정하면 Board 미검색 Warning 없이 열린다. 전역 설정이나 XPR을 임의로
변경하지 않았다. Board 설정이 다른 PC에서도 자동 인식된다고 보장하지 않는다.

Cache·`.gen`·`.ip_user_files` 없이 열 수 있다. 생성 IP 경로가 없다는 안내와
`IPUserFilesDir` Warning이 발생하지만 현재 IP 입력은 없고 XDC 해석은 성공한다.
Warning을 숨기기 위한 빈 폴더나 불필요 파일은 Commit하지 않는다.

## Hardware와 자료 충돌

### Basys3

[공식 Reference Manual](https://digilent.com/reference/_media/reference/programmable-logic/basys-3/basys3_rm.pdf)의
§4 / §5 / §8 / §9를 기준으로 W5의 100MHz Clock, USB-UART Bridge,
Active-low FND 제어, 일반 Pmod의 3.3V 전원과 GND를 확인했다.
실제 보드 Revision은 미확인이고, 열람한 Manual은 Rev.C 기준이다.
두 보드의 100MHz Clock이 같은 주파수라는 사실은 동기 관계를 뜻하지 않는다.

[AMD DS181](https://docs.amd.com/v/u/en-US/ds181_Artix_7_Data_Sheet)의
Table 1 / 2 / 9에 따라 전원·I/O Standard·입력 허용 조건을 구분해야 한다.
5V 센서 출력의 FPGA 직접 연결을 승인한 상태가 아니다.
Pmod 신호선에는 Delay Matching이 보장되지 않으므로 최고 Clock 수치만으로
보드 간 SPI 주파수를 정하지 않는다. 배선과 Clock / Data 지연은 STEP 2에서 검토한다.

### DHT11

[Aosong 문서](https://www.aosong.com/uploadfiles/2025/03/20250305165717988.pdf)
(Dec 2022, Table 2, §5)는 3.3~5.5V 전원, 40-bit MSB-first 전송과 Checksum,
최소 2초의 초기화·재측정 간격을 제시한다. 단일 Data-line Protocol이며 I2C가 아니다.
Host는 Low 구동과 Line 해제를 구분해야 하고, Pull-up과 실물 Breakout 전원 경로를
확인해야 한다. FPGA 내부 `PULLUP` 설정만으로 모든 전기 조건이 해결되지는 않는다.
온습도 소수부·온도 부호를 설명하는 문서 Revision이 있으므로 실제 센서와 팀원 출력
표현을 보기 전에 unsigned 8-bit 정수로 Contract를 제한하지 않는다.

### HC-SR04

[HC-SR04 문서](https://cdn.sparkfun.com/datasheets/Sensors/Proximity/HCSR04.pdf)는
DC 5V, 최소 10µs Trigger, 60ms를 넘는 측정 간격을 제시한다.
Echo의 High 시간을 왕복 시간으로 해석하여 `거리 = 시간 × 음속 / 2`로 계산한다.
`시간(µs) / 58`은 문서가 제시한 cm 환산 근사다.

| 자료의 내용 | 판단과 영향 |
| --- | --- |
| 본문 `3.3~5V`, 삽입 표 `DC 5V` | 충돌. 실물 변형 확인 전 3.3V 동작을 보장할 수 없음 |
| 거리식 본문에 `/2` 누락 | 왕복 시간을 반영한 공식 자료와 대조 필요 |
| 표의 `40Hz`, Burst 설명 `40kHz` | 두 수치를 동일한 의미로 사용하지 않음. Burst는 40kHz, 측정 간격은 별도 검토 |
| RTL 이미지의 1MHz Tick, 약 10,000 Tick timeout | 약 10ms. 4m 왕복 약 23ms를 처리하기에 짧음 |
| `echo` 직접 참조 | 비동기 입력 처리 여부를 실제 Slave 구현에서 검토해야 함 |
| timeout 시 별도 Valid/Error 출력 없음 | 이전 값과 유효한 새 측정을 구분할 방법이 필요 |

1MHz Tick의 실제 생성 코드와 실행 근거는 제공되지 않았다. 따라서 위 시간 계산은
이미지의 Parameter가 의도대로 동작한다는 조건의 정적 분석이다. 실제 Slave를 수정하거나
대신 구현하지 않았다. Echo 출력 전압과 Level Conversion은 실물 기준 확인 필요다.

### SSD1306 / OLED

제공 PDF §8.1.3 / §8.1.4, Table 7-1 / 13-4는 IC의 3-wire·4-wire SPI 지원을 설명한다.
4-wire는 `SCLK/SDIN/D/C#/CS#`이고 일반 양방향 SPI의 `SCLK/MOSI/MISO/CS#`와
같은 신호 구성이 아니다. Serial mode는 Write-only이고 4-wire에서는 MSB부터
상승 Edge에서 수신한다. 3-wire는 D/C Bit를 포함한 9-bit 단위다.
이 사양을 보드 간 SPI의 Mode나 Packet으로 확정하지 않는다.

과제 4번 사진은 `GND/VCC/SCL/SDA`의 4핀 OLED다. 실물도 동일한 모듈인지,
SPI 선택 Pad나 필요한 제어 Pin이 노출되는지는 미확인이다. 보드 간 SPI 전환이
OLED Module의 Interface를 자동으로 바꾸지는 않는다. 실물이 I2C 전용이면 OLED I2C를
유지할지 SPI 지원 모듈을 사용할지 확인한 뒤 결정해야 한다.

PDF의 128×64는 IC GDDRAM 구조이며 실물 패널 해상도 확인을 대체하지 않는다.
Table 12-1의 IC VDD·Panel VCC와 Breakout VCC 입력 조건도 동일하지 않다.
별첨 App Note에는 Charge Pump와 초기화 예제가 있으므로 문서 본문의 Reserved Pin
설명만으로 실제 모듈 회로나 전원을 단정하지 않는다. 패널에 맞는 MUX·COM 설정,
Reset·Power-on·Command/Data·Glyph 표시는 OLED 설계 시 확인한다.

### Pin 예제 충돌

과제 4번의 보드 간 I2C SDA와 5번의 DHT11 예제는 모두 JA1을 사용한다.
같은 Slave 보드에 그대로 중복 배치할 수 없으므로 배선 예제는 독립 예제로 해석한다.
공식 XDC의 Pin 이름은 참고 근거이며 새 SPI Pin Mapping은 아직 없다.

## 역할 초안과 경계

| 영역 | Master (사용자) | Slave (팀원) |
| --- | --- | --- |
| 센서 | 수신된 온습도·거리 사용 | DHT11·HC-SR04 수집과 센서 오류 처리 |
| 통신 | SPI Transaction 시작·Clock·수신·Decode | 승인 Contract에 따른 응답 |
| 일관성 | 완성된 수신 결과를 출력에 전달 | 전송 중 센서 값이 섞이지 않도록 제공 |
| 출력 | FND·UART·OLED와 Master Debug | Slave Debug와 독립 확인 |
| 검증 | Behavioral Slave와 공통 Vector로 독립 검증 | 실제 Slave RTL과 공통 Vector 검증 |

Snapshot 시점, 폭·부호·단위·Byte Order, 유효·미준비·센서 오류, 반복·중단·Reset,
Slave 응답 준비 지연, CDC와 첫 Bit 조건은 STEP 2에서 검토한다. 이 목록은
별도 Flag·Header·CRC·FIFO 등을 모두 추가해야 한다는 요구가 아니다.

## 미확인 사항과 후속 영향

| 미확인 항목 | 필요한 근거 | 판단 시점 |
| --- | --- | --- |
| 실물 Basys3 Revision·센서·OLED 모델과 Pin | 실물 식별, 모듈 공식 사양·회로 | 배선 확정 전 |
| HC-SR04 전원·Echo 전압, DHT Pull-up·전원 연결 | 해당 모듈 사양·회로와 필요한 실측 | 실제 연결 전 |
| OLED 해상도·지원 Bus·전압·Reset 노출 | 실제 제품 사양·회로 | OLED 배선·Driver 설계 전 |
| 팀원 센서 출력 폭·부호·단위·Update·오류 표현 | 실제 코드 또는 양쪽 합의 | Data Contract 확정 전 |
| 팀원 SPI 수신 구조·응답 지연·Clock 관계 | 팀원과 공통 Contract 검토 | Timing Contract 확정 전 |
| 표시 선택·갱신, UART Baud·출력 형식 | 과제 의도와 사용 방식 | Architecture / 출력 설계 시 |

이 항목들은 분석에서 발견한 조건이며 검증 PASS가 아니다. 필요한 항목이 미확인인 동안
해당 배선이나 호환성을 확정하지 않는다. 현재 분석 전체를 중단할 이유는 아니다.

## 개발 순서

1. STEP 2: Physical Interface, SPI Timing, Data Contract, Golden Vector 설계와 승인 대기
2. STEP 3: 승인 Contract 기반 Master Architecture·책임·Handshake·Convention 설계와 승인 대기
3. STEP 4: 최소 SPI Master와 Behavioral Slave의 Self-checking 독립 검증
4. STEP 5: Sensor Transaction, Decode, 반복·중단·Reset·Recovery 검증
5. 이후: 팀원 준비 상태에 따라 고정 Vector 기반 초기 보드 연동을 우선 검토하고 다음 STEP으로 제안
6. Debug LED·UART·FND로 수신 경로 관측, 실물 확인 후 OLED 추가 및 통합
7. 통합·Hardware·Final Review 후 별도 승인으로 PPT 작성

각 STEP은 사용자 `다음 단계` 요청으로만 진행한다. Review나 수정 요청은 승인으로
간주하지 않는다. Synthesis / Implementation / Timing은 Top·XDC·통합 Milestone에서
실행 필요성을 판단한다. 모든 작은 변경마다 반복하지 않는다.

## STEP 0·1 재검토 결과

| 범주 | 결과 |
| --- | --- |
| 초기 Git Baseline / 사용자 파일 보존 | STEP 0 기록과 이력 대조. 승인된 초기 입력을 보존 |
| 파일 관리 / Ignore | 실제 생성물만 제외. XPR·XDC·문서 추적, 원본 자료 Binary 미복제 |
| 프로젝트 전체 구조 | 전체 파일과 XPR 등록 대조. 기능 RTL·TB·IP 없음 |
| 요구사항 / SPI 변경 / 역할 | R1~R6와 역할 초안으로 정리 |
| 자료 충돌 / Hardware / 재사용 | 근거와 적용 한계·후속 확인 항목으로 정리 |
| 재현성 | Git 파일만 다른 경로로 내보내 Project 열기·입력 경로 검증 |
| 설계 Baseline | 변경 없음. STEP 2의 결정 선행하지 않음 |
| Simulation / Synthesis / Hardware | 수행하지 않음. 기능 PASS 없음 |

재검토에서 실제 수행한 검사는 다음과 같다.

- Stage한 Git 입력만 임시 경로로 내보내 Vivado 2026.1 Project 열기: PASS, 종료 코드 0
- Project 이름·Device·Board·4개 FileSet의 입력 수·XDC의 임시 경로 내부 해석: PASS
- 원본 XPR·XDC의 검증 전후 SHA-256 일치: PASS
- Ignore 규칙: 생성물 경로 12개 제외, 입력·검증 근거 경로 7개 보존 확인
  (일부는 규칙 검사용 가상 경로이며 새 Source나 검증 파일을 생성한 것이 아님)
- Repository 내부 Markdown 링크·Anchor·줄 끝 공백 확인: PASS
- IPUserFilesDir Warning 1건: 위 환경 및 재현성 절의 내용대로 기록, IP 입력 없음

현재 단계에서 확인 가능한 분석·관리 항목은 충족한다. 실물·팀원 구현의 미확인 항목을
해결한 상태라는 뜻은 아니다. 최초 STEP 1의 대화 결과를 Repository에 보존하고,
STEP 0의 과거 기록과 현재 상태를 명확히 구분한 것이 이번 보완이다.
