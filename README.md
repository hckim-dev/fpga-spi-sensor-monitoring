# fpga-spi-sensor-monitoring

Basys3 두 대를 SPI로 연결하는 센서 모니터링 수업 프로젝트의 Master 저장소입니다.
실제 Slave 구현은 팀원 담당이며, 이 저장소의 `master/`에서 Master를 개발합니다.
현재는 요구사항 분석을 마쳤으며, Interface Contract 설계 전입니다.

## 프로젝트 열기

- 확인한 Tool: Vivado 2026.1 (SW Build 6511674), Windows
- Project: `master/spi_sensor_master.xpr`
- Device 설정: `xc7a35tcpg236-1`
- Board 설정: `digilentinc.com:basys3:part0:1.2`

Vivado에서 `master/spi_sensor_master.xpr`를 엽니다. Board files가 검색되지 않으면 Basys3 board repository
설정을 확인해야 합니다. 프로젝트에 저장된 사용자별 Board repository 경로는 다른 PC에서
유효하지 않을 수 있습니다.

현재 RTL과 Testbench는 없으며, 등록된 XDC는 핀과 Clock 제약이 주석 처리된
Basys3 템플릿입니다. SPI Pin Mapping이나 Timing Contract는 아직 확정하지 않았습니다.
XDC의 QSPI boot 설정은 보드 간 센서 통신의 SPI 설계를 의미하지 않습니다.

## 파일 관리

`master/spi_sensor_master.xpr`와 `master/spi_sensor_master.srcs/`는 프로젝트 입력으로 보존합니다.
Cache, 실행 결과, Hardware session, Vivado session log는 `.gitignore`로 제외하며,
생성물만을 위해 Source나 검증 근거의
확장자 전체를 Ignore하지 않습니다.

초기 Git 상태와 검증 범위는 [STEP 0 기록](docs/step0-workspace.md)을 참고하세요.
