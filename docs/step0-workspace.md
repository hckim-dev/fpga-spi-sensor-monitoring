# STEP 0 — Workspace 초기 정리

확인일: 2026-11-03. 기능 구현과 Interface 설계는 수행하지 않는다.

현재 경로 안내: STEP 1 분석 이후 사용자가 Master 프로젝트를 다시 생성했다.
현재 Project는 `master/spi_sensor_master.xpr`, Constraint는
`master/spi_sensor_master.srcs/constrs_1/imports/digilent-xdc-master/Basys-3-Master.xdc`다.
아래 기존 경로와 해시는 STEP 0 당시의 기록으로 유지한다.
Repository 이름과 Remote는 `fpga-spi-sensor-monitoring`을 유지한다.
재생성 후 Commit 대상 파일만 별도 임시 경로로 내보내 Vivado 2026.1에서 읽기 전용으로
열었다. Project 이름 `spi_sensor_master`, Device, Board, 저장소 내부 XDC 경로와
Design Source 0개 / Constraint 1개 / Simulation Source 0개를 확인했다(종료 코드 0).
Board repository는 검증 session에서 실제 설치 경로를 지정했다. IP 생성 디렉터리
누락 Warning은 있었으나 현재 IP 입력은 없다. XDC 내용은 기존 파일과 동일하다.

## 작업 시작 시 Git Baseline

- Branch: `master`, upstream: `origin/master`
- HEAD: `1c24ab299217e794d73e891cda868d6b2945d06f` (`first commit`)
- Remote: `https://github.com/hckim-dev/fpga-spi-sensor-monitoring.git`
- Remote 직접 조회 결과: `master`는 위 HEAD와 동일
- Tracked: `README.md` 하나, Modified 없음
- Staged: 없음
- Ignored: 없음 (`.gitignore` 없음)
- 기존 Untracked 파일:
  - `fpga-spi-sensor-monitoring.xpr`
  - `fpga-spi-sensor-monitoring.srcs/constrs_1/imports/digilent-xdc-master/Basys-3-Master.xdc`
  - `fpga-spi-sensor-monitoring.cache/wt/project.wpc`
  - `fpga-spi-sensor-monitoring.hw/fpga-spi-sensor-monitoring.lpr`
- `.ip_user_files/`와 `.sim/`은 파일 없는 디렉터리였다.

기존 파일은 내용 변경 없이 보존했다. 기존 Untracked 프로젝트 입력 두 파일은
사용자의 명시적인 승인에 따라 초기 Baseline의 Commit 대상으로 포함한다. Cache와 Hardware session은
자동 생성 상태 파일로 판단하여 Ignore하며 로컬에서 삭제하지 않는다.

## 프로젝트 구조와 관리 결정

- `.xpr`: Vivado Project 설정 입력으로 보존
- `.srcs/.../Basys-3-Master.xdc`: 등록된 유일한 Constraint 입력으로 보존
- Design Source / Simulation Source / IP 입력: 현재 없음
- `.cache`, `.hw`, `.ip_user_files`, `.sim`, `.runs`, `.gen`, `.Xil`:
  이 프로젝트의 자동 생성 경로로 Ignore
- Root의 `vivado*.log`, `vivado*.jou`, `vivado*.str`: session 생성물로 Ignore
- Source, Testbench, XDC, Script, 보고서, Waveform, Bitstream 확장자에 대한
  전역 Ignore는 추가하지 않음. 향후 증거 보존 필요성을 개별 판단
- 이미 Tracking 중인 생성 파일이 없어 Tracking 제외 작업은 없음
- Local 파일 삭제, stash, reset, restore, branch 변경 없음

## 재현성 확인

설치된 Vivado 2026.1 (SW Build 6511674)을 사용했다. 기존 Cache 없이 별도 임시
디렉터리에 `.xpr`와 상대 경로의 XDC만 복사하여 `open_project -read_only`로 열었다.

- Vivado batch 종료 코드: 0
- Project 열기 및 등록 파일 존재 확인: PASS
- Device: `xc7a35tcpg236-1`
- `sources_1`: 0개 / `constrs_1`: 1개 / `sim_1`: 0개
- 등록 XDC는 복사한 임시 디렉터리 안에서 해석됨
- 원본 `.xpr`와 XDC의 SHA-256은 검사 전후 동일

이 결과는 현재 빈 프로젝트와 Constraint 입력의 이동 가능성만 확인한다.
초기 Baseline에 두 입력 파일과 상대 경로 구조를 포함하여 이 열기 조건을 보존한다.

확인한 메시지:

- 임시 경로가 80자를 넘어 Windows path length 안내가 발생했다.
- 생략한 `.gen`과 `.ip_user_files` 경로에 대한 안내/Warning이 발생했다.
  현재 IP 입력은 없고 Project 열기 및 XDC 해석은 성공했다.
- `Project 1-5713`: Project를 여는 도중 Basys3 board part 미검색 Warning이 발생했다.
  열기 전 `get_board_parts` 결과는 0개였지만 연 뒤에는 동일 ID가 1개 검색되었다.
  로컬 Board Store에 해당 `board.xml`이 존재한다. 이후 실제 `boards` 디렉터리를
  `set_param board.repoPaths`로 지정한 임시 batch session에서는 열기 전부터 1개가
  검색되었고 해당 Warning 없이 Project를 열었다. 기존 XPR의 repository 경로는
  Board Store 상위 경로이며, 실제 `boards` 디렉터리의 명시가 이 환경에서 유효했다.
  원본 XPR과 전역 설정은 수정하지 않았다. 다른 PC에서는 해당 PC의 Board files
  설치 경로에 맞춰 설정해야 한다.

원본 SHA-256:

| 입력 | SHA-256 |
| --- | --- |
| `.xpr` | `728BF1F0BD3176B521AC6F08D8DE3F06082711EBDAB8DD04C0D8BEDE548DB0FA` |
| `Basys-3-Master.xdc` | `F6F289E967F1DAB96349A8C7AAEE9C7E9DB1C0A5346848635EC2F056B922D89C` |

## 범위와 미검증

RTL / XDC 수정, Testbench 작성, Simulation, Synthesis, Implementation, Bitstream
생성, Hardware 실행은 하지 않았다. 기능 또는 물리 동작의 PASS 근거는 없다.
새로운 설계 Baseline은 정하지 않았다.

첨부 디렉터리에는 작업 지시 텍스트만 존재한다. 별도의 과제 원본, 센서 자료,
SSD1306 Datasheet는 이번 STEP에서 확인하지 못했다. STEP 1에서 접근 가능한
자료를 확인하고 부족한 자료만 별도로 표시해야 한다.

다음 STEP의 목표는 요구사항 / Workspace / Hardware 분석이다.
사용자의 명시적인 `다음 단계` 요청 전에는 진행하지 않는다.

## STEP 0 완료 상태

초기 상태 기록, Ignore 규칙 확인, 입력 파일 보존 및 이동 후 열기 검증은 수행했다.
기존 Untracked `.xpr`와 XDC의 초기 Commit 포함은 사용자가 승인했다.
STEP 0의 Commit 대상은 `.gitignore`, `README.md`, 이 기록, 승인된 `.xpr`와 XDC다.
Commit / Push 결과와 최종 Local / Remote 일치 여부는 작업 종료 보고에서 확인한다.
STEP 1은 시작하지 않았다.
