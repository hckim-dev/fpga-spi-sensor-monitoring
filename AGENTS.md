# 프로젝트 작업 규칙

- `master/`는 사용자 담당, `slave/`는 팀원 담당이다. 실제 Slave RTL은 수정하지 않는다.
- Interface와 Architecture는 `docs/interface.md`, `docs/implementation.md`를 기준으로 한다.
- 사용자가 “다음 단계”라고 할 때 현재 STEP만 진행한다. 구현 STEP은 검증·Commit·Push 후 멈춘다.
- Commit 전과 Push 직전에 Remote를 확인한다. Remote가 앞섰거나 Diverged이면 보고하고 멈춘다.

## 코드 형식

- Verilog-2001, 명시적 `wire/reg`, 2칸 들여쓰기와 공백을 사용한다. Tab·줄 끝 공백은 쓰지 않는다.
- Module Port와 Parameter는 줄마다 하나씩, Instance Port는 한 단계 더 들여쓴다.
- 이름은 `lower_snake_case`, 상수는 `UPPER_SNAKE_CASE`, Instance는 `u_<module>`로 쓴다.
- RTL의 조건문은 `begin/end`로 구분하고, 역할이 다른 선언·제어 블록 사이에는 빈 줄을 둔다.
- 주석은 처음 보는 사람이 알아야 할 설계 의도·우선순위·예외에만 짧은 한글로 쓴다. Tool directive는 유지한다.
- 기존 코드를 정리할 때 동작 변경과 구분해 검토하고 관련 Simulation을 다시 실행한다.
