# fpga-spi-sensor-monitoring

Basys3 두 대를 SPI로 연결하는 센서 모니터링 수업 프로젝트입니다.
본인 담당은 `master/`의 Master 설계·구현·검증이며, `slave/`는 팀원이 담당합니다.
Master / Slave Interface Contract Rev.1과 Master Architecture Rev.1을 확정했습니다.
현재 SPI Master·센서 Frame 검사·데이터 저장·Stale 처리와 FND 표시를 구현·검증했습니다.
UART·OLED·보드 통합은 이후 구현 대상이며, Slave는 팀원 담당입니다.

## 담당 범위와 설계

- Slave의 온습도·거리를 SPI로 수신하고 FND·UART·OLED에 표시하는 Master 개발
- 보드 간 전용 SPI: Mode 0, 100kHz, 읽기 명령 1 Byte와 고정 응답 9 Byte
- 센서 유효 상태, Snapshot, Checksum, 중단·Reset·Timeout 복구를 공통 규칙으로 정의
- 4핀 OLED는 보드 간 SPI와 별도의 I2C 연결 대상으로 계획

배선·Timing·데이터 형식과 공통 검증 기준은 [Interface Contract Rev.1](docs/interface.md)에 정리했습니다.
80-bit 전송, CS Timing, Busy 요청 무시, Reset·Timeout 복구를 Self-checking Simulation으로 확인했습니다.
독립 Core 합성 결과는 LUT 213개·Register 288개·Latch 0개입니다.
Sensor Reader는 온습도·거리 Decode와 오류·500ms 수신 정지 처리를 담당하며,
독립 합성 결과는 LUT 123개·Register 198개·Latch 0개입니다.
FND는 온습도 소수·음수·거리·Invalid를 표시하며, Scan 동안 값을 고정합니다.
독립 합성 결과는 LUT 94개·Register 44개·Latch 0개입니다.
보드 간 연동과 구현 후 Timing·Hardware 동작은 아직 검증하지 않았습니다.

Master는 `spi_master`의 전송, `sensor_reader`의 Frame 검사·데이터 저장,
FND·UART·OLED의 출력을 분리합니다. 출력 중에도 센서 수신을 계속하고 출력 대기 데이터는
최신 상태 한 개만 보관합니다. 세부 기준과 검증 범위는 [설계 및 검증](docs/implementation.md)에 정리합니다.

## 프로젝트 열기

- Master 확인 Tool: Vivado 2026.1 (SW Build 6511674), Windows
- Project: `master/spi_sensor_master.xpr`
- Device 설정: `xc7a35tcpg236-1`
- Board 설정: `digilentinc.com:basys3:part0:1.2`

Vivado에서 `master/spi_sensor_master.xpr`를 엽니다. Board files가 검색되지 않으면
Basys3 board repository 설정을 확인해야 합니다. 프로젝트에 저장된 사용자별 경로는
다른 PC에서 유효하지 않을 수 있습니다. Basys3 `board.xml`을 포함한 실제 Board repository의
`boards` 경로를 해당 PC의 Vivado에 설정해야 합니다.

팀원 Slave 프로젝트는 `slave/spi_sensor_slave.xpr`이며 XPR 생성 버전 표기는 Vivado 2020.2입니다.
Slave 프로젝트의 Tool 호환성과 실행은 아직 검증하지 않았습니다.

현재 Project에는 `spi_master`·`sensor_reader`·`fnd_controller`, Simulation 전용 Testbench·응답 모델이 등록되어 있습니다.
Design Top은 독립 모듈 `fnd_controller`, Simulation Top은 세 모듈을 연결한 `tb_sensor_display`입니다.
보드용 통합 Top은 아직 구현하지 않았습니다.
등록된 XDC는 핀과 Clock 제약이 주석 처리된
Basys3 템플릿입니다. 승인된 SPI 배선·Timing은 아직 XDC에 반영하지 않았습니다.
XDC의 QSPI boot 설정은 보드 간 센서 통신의 SPI 설계를 의미하지 않습니다.

## 독립 검증 실행

Vivado 명령이 PATH에 설정된 환경에서 실행합니다.

```powershell
python scripts/verify_spi_master.py
python scripts/verify_spi_master.py --synth
python scripts/verify_spi_master.py --sensor
python scripts/verify_spi_master.py --sensor --synth
python scripts/verify_spi_master.py --fnd
python scripts/verify_spi_master.py --fnd --synth
```

기본 명령은 SPI, `--sensor`는 Reader 단위·SPI 연결, `--fnd`는 FND 단위·SPI부터 표시까지의 연결 검증입니다.
`--synth`는 해당 모듈의 독립 합성입니다.
센서 검증에서는 Poll·Stale 시간을 줄이고 SPI는 실제 100kHz 설정을 사용합니다.
로그·Report·Waveform은 Git에서 제외한 `master/spi_sensor_master.sim/step4/`, `step5/`, `step6/`에 생성합니다.

## 파일 관리

`master/spi_sensor_master.xpr`와 `master/spi_sensor_master.srcs/`는 프로젝트 입력으로 보존합니다.
Cache, 실행 결과, Hardware session, Vivado session log는 `.gitignore`로 제외하며,
Source나 검증 근거의 확장자 전체를 Ignore하지 않습니다.
