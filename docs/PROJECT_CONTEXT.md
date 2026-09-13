# SE_업무 Project Context

- 기준일: 2026-09-12
- 목적: 다른 ChatGPT 계정 또는 Codex 로컬 프로젝트에서 업무 맥락을 이어가기 위한 컨텍스트 이관본
- 성격: 운영 지식/대화에서 누적된 컨텍스트 + 업로드된 스크립트/문서의 확인 내용

## 1. 운영 환경 개요

중앙 운영 호스트는 Xcat 서버이며 Linux 서버는 주로 SSH/pdsh, Windows 서버는 Ansible WinRM으로 점검한다.
전체 운영망은 폐쇄망 성격이 강해 외부 인터넷 의존 솔루션은 기본 선택지가 아니다.

주요 일일점검은 두 축이다.

```text
Linux 및 일부 장비
  → ccnuser
  → dailycheck
  → /home/ccnuser/sysmon/sbin/monitor_dashboard.sh

Windows 서버
  → root
  → win_dailycheck
  → Ansible WinRM 수집
  → Xcat MySQL 적재
  → Python 리포트 출력
```

## 2. Xcat / Linux 모니터링

현재 `monitor_dashboard.sh` 계열 로직은 다음 지표를 다룬다.

- CPU
- 메모리
- 디스크 80% 이상
- NFS
- NTP
- 서비스/프로세스
- 계정 만료
- 보안 이벤트
- Uptime
- 라이선스 만료

Linux 다수 호스트는 `pdsh -g all`을 통해 일괄 수집한다.
특수 Solaris 서버인 `ccnsearch`는 별도 수집 파일을 Xcat에서 읽는 로직이 존재한다.
Cisco 계열 일부 장비는 SNMP 조회 로직이 포함되어 있다.

## 3. Windows 모니터링

Windows 측은 Ansible 2.9.27 / Python 2.7 계열 운영 구조가 확인되어 있다.
`win_dailycheck`는 Windows 서버에 접속해 CPU, 메모리, Uptime, 디스크, 지정 프로세스를 수집한 뒤 `win_monitoring.win_server_status`에 이력을 INSERT하는 구조다.

현재 문서상 주의점:

- 후처리 `dailycheck.py`와 실제 DB 프로세스 컬럼 연결이 완전히 일치하지 않음
- `Process Status=N/A`가 실제 프로세스 점검 실패를 뜻하지 않을 수 있음
- `Service (Stopped)=All Running`은 실제 서비스 수집값과 직접 연결되지 않은 구현이 확인됨
- Windows 디스크 사용률은 문자열 수집 위주이며 명시적 임계치 판정이 부족함

세부사항은 `docs/XCAT_ANSIBLE_ARCHITECTURE.md` 참조.

## 4. NTP 운영 기준

내부 기준 NTP 서버는 `192.168.2.240`으로 운영 컨텍스트에 기록되어 있다.
목표는 `NoSync` 제거, 단일 NTP 데몬 사용, 부팅 시 자동시작이다.

자주 사용하는 확인 명령:

```bash
ntpq -p
ntpq -c rl
ntpstat
chronyc tracking
chronyc sources
```

서버별 과거 조치 사례에는 chronyd/ntpd 동시 enable 해소, 외부 NTP → 내부 NTP 전환, Solaris ntpdate 후 서비스 재가동 등이 포함된다.

## 5. Web/WAS/Tomcat

확인된 주요 Tomcat 계열:

- ccnwas1: admin/call/portal 8.5.86
- ccnwas2: portal 및 call 계열 8.5.86
- hyboost_visual: 9.0.85
- ccnmail: 7.0.103
- ccnbib01/02: 7.0.77
- ccnmessanger: 7.0.109
- dbsafer: 9.x 계열

ccnweb1/2의 Apache httpd는 과거 확인 기준 2.4.51로 기록되어 있다.
버전은 시간이 지나면 달라질 수 있으므로 취약점 분석 전 실제 서버에서 재확인한다.

## 6. 디스크/로그 관리

운영에서 자주 다루는 항목:

- `/DATA`, `/share`, `/sharebackup`, `/oracle`, `/arc`, `/media`, `/data` 등 주요 마운트
- 80% 이상 사용 디스크 경고
- WAS catalina 로그 대용량 정리
- 월별 로그 압축/보관
- Scouter DB 오래된 디렉터리 압축/삭제

`all_disk.sh`, `main_disk.sh`, `cleanup_logs.sh`, `cleanup_scouter.sh` 등 관련 스크립트를 참고한다.

## 7. 취약점 점검/조치 방식

업무는 Linux U-series, Windows W-series, Tomcat/Apache, Oracle, 계정/권한, NTP, 감사로그 등 다양한 취약점 조치를 포함한다.

원칙:

1. 실제 운영 영향 여부를 먼저 확인
2. 단순 취약 판정과 실제 악용 가능성/서비스 영향은 구분
3. 변경 가능한 항목과 운영상 예외 항목을 구분
4. 벤더 조치가 필요한 경우 업체별로 정리
5. 조치 후 재점검 명령까지 제시

## 8. 보고서/문서 선호

- A4 1장 또는 필요한 범위 내 간결한 보고서
- 좌우 여백 넓게
- 맑은 고딕 계열
- 공공기관 문서 느낌
- 불필요한 각주/페이지번호 없음
- 표 중심 요약 선호
- `ccndevdb`는 대외 보고에서 제외 요청이 있었던 이력 존재

## 9. 자주 쓰는 운영 명령 스타일

사용자는 길고 추상적인 설명보다 다음을 선호한다.

```text
1. 확인 명령
2. 결과 해석
3. 조치 명령
4. 조치 후 확인 명령
```

가능하면 한 줄 명령을 우선한다.

## 10. 향후 개선 방향

과거 논의된 방향:

- Xcat에서 직접 명령을 치지 않아도 되는 Spring Boot 웹 대시보드
- `dailycheck`, `win_dailycheck` 실행 버튼
- Linux/Windows/백업 결과를 하나의 화면에서 조회
- MySQL의 점검 이력을 이용한 일/월간 보고서 자동 생성
- 백업 로그 export 결과 파싱 후 HTML/Excel 일일점검표 생성

이 저장소는 향후 이 자동화 프로젝트의 기반 컨텍스트로도 사용할 수 있다.
