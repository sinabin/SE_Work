# SE_업무 Codex 프로젝트 지침

## 1. 프로젝트 목적

이 저장소는 1372 소비자상담센터 계열의 서버/인프라 운영 업무를 Codex에서 일관되게 지원하기 위한 로컬 프로젝트다.
핵심 범위는 Linux/Windows 서버 운영, Xcat 기반 중앙 운영, pdsh, Ansible/WinRM, 일일점검, NTP, 디스크/로그 관리, 취약점 조치, Tomcat/Apache, Oracle/MySQL, 백업 점검, 운영 보고서 작성이다.

## 2. 작업 전 반드시 확인할 문서

질문 또는 수정 대상에 맞추어 다음 문서를 먼저 읽는다.

1. `docs/PROJECT_CONTEXT.md` — 프로젝트 전체 맥락과 운영 원칙
2. `docs/XCAT_ANSIBLE_ARCHITECTURE.md` — Xcat/Ansible/일일점검 상세 구조
3. `docs/SERVER_INVENTORY.md` — 확인된 서버/역할/특이사항
4. `docs/REPORT_STYLE_GUIDE.md` — 보고서 작성 스타일
5. 관련 `runbooks/*.md` — 반복 운영 절차
6. 관련 `scripts/*.sh` 및 `config/*.txt` — 실제 코드/설정

## 3. 답변 원칙

- 기본 언어는 한국어.
- 운영자가 바로 복사해 쓸 수 있는 명령을 우선 제시한다.
- 조회 명령과 변경 명령을 명확히 구분한다.
- 한 줄 명령으로 충분하면 장황한 스크립트보다 한 줄 명령을 우선한다.
- CentOS 6/7, Solaris, Windows Server 2008 R2/2012 R2/2016/2019 차이를 고려한다.
- 폐쇄망 환경을 기본 전제로 한다. 외부 인터넷 사용을 전제로 한 해결책은 별도 표시한다.
- 서비스 재시작, 계정 변경, 방화벽 변경, 패키지 설치/업그레이드, DB DDL 등 운영 영향 가능 작업은 영향과 롤백 포인트를 함께 설명한다.
- 사용자가 명시적으로 변경을 요청하지 않은 경우 운영 설정을 임의 변경하지 않는다.
- 기존 운영 구조와 호환되는 최소 변경을 우선한다.

## 4. 코드 수정 원칙

- 먼저 기존 스크립트의 데이터 흐름, 호출 관계, cron 의존성, 파일 경로를 분석한다.
- 사용 중인 절대 경로를 이유 없이 변경하지 않는다.
- Bash 수정 시 현재 운영 CentOS 7의 Bash 호환성을 우선한다. 필요하면 CentOS 6 호환성도 확인한다.
- Solaris 대상은 GNU 전용 옵션을 그대로 사용하지 않는다.
- 현재 운영 스크립트의 출력 포맷을 변경할 경우 DB 파서, 대시보드, cron 후속 작업 영향까지 확인한다.
- 민감정보를 코드에 새로 하드코딩하지 않는다.
- 기존 평문 자격증명은 이 프로젝트에서 환경변수/별도 비밀파일 방식으로 치환되어 있다.
- `.env`, Vault password, SSH private key, DB 비밀번호, SNMP Community 등은 Git에 커밋하지 않는다.

## 5. 변경 전 확인할 주요 의존성

### Linux 일일점검

`ccnuser`의 `dailycheck`는 `/home/ccnuser/sysmon/sbin/monitor_dashboard.sh` 기반이다.
현재 프로젝트의 `scripts/monitor_dashboard.sh`는 운영 코드 참고본이며 비밀값이 제거된 사본이다.

### Windows 일일점검

`root`의 `win_dailycheck`는 Ansible 플레이북 실행 후 Python 리포트를 출력하는 구조다.
상세 내용은 `docs/XCAT_ANSIBLE_ARCHITECTURE.md`를 따른다.

### 특수 서버 ccnsearch

Solaris이며 일반 Linux 서버와 수집 방식이 다르다. Xcat이 직접 SSH 수집하는 Linux 서버와 달리 ccnsearch 쪽에서 생성된 수집 파일을 Xcat이 참조하는 구조가 존재한다.

## 6. 보고서 규칙

A4 보고서를 요청받으면 기본적으로 다음 스타일을 사용한다.

- 공공기관 실무 문서 느낌
- 좌우 여백 넓게
- 맑은 고딕 계열
- 불필요한 각주 없음
- 페이지 번호 불필요
- 핵심 결론과 조치 내역 중심
- `ccndevdb`는 사용자가 명시적으로 포함하라고 하지 않는 한 대외 보고에서 제외하는 선호가 있음

## 7. 보안 규칙

다음 값은 답변, 문서, 커밋에 실제 값으로 노출하지 않는다.

- DB 비밀번호
- Ansible Vault 비밀번호
- Windows 계정 비밀번호
- SSH private key
- SNMP Community
- API key/token

필요 시 `<REDACTED>`, `${DB_PASS}`, `${SNMP_COMMUNITY}` 같은 자리표시자를 사용한다.

## 8. Git 사용 권장 방식

- 변경 전 `git status`, `git diff` 확인
- 한 작업 단위로 작은 커밋 유지
- 운영 반영 전 반드시 diff 검토
- `secrets/`와 `.env*`의 실제 비밀 파일은 커밋 금지

## 9. 불확실한 정보 처리

문서/스크립트에서 확인되지 않은 사실을 확정적으로 말하지 않는다.
운영 컨텍스트와 코드가 충돌하면 실제 현재 코드/실행 결과를 우선하고, 문서는 업데이트 대상으로 표시한다.
