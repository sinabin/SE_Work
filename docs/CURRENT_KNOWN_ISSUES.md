# Current Known Issues / Follow-up Items

## 모니터링

- Linux `monitor_dashboard.sh`의 운영 버전과 이 저장소 사본이 항상 동일하다고 가정하지 말 것.
- Windows `dailycheck.py`와 DB 프로세스 컬럼 연결 불일치가 과거 확인됨.
- Windows 디스크 자동 임계치 판정 개선 여지.
- ccnsearch는 일반 Linux와 수집 방식이 달라 별도 예외처리 유지 필요.

## NTP

- 과거 `NoSync` 서버가 존재했으며 서버별 데몬/설정 차이가 있음.
- chronyd와 ntpd 동시 enable 여부 확인 필요.
- 내부 NTP `192.168.2.240` 기준 사용 여부를 정기 확인.

## 보안/구성

- 과거 운영 코드에 평문 DB 비밀번호 및 SNMP Community가 포함되어 있었음.
- Vault password 파일, 임시 SQL 디렉터리 권한, CLI DB 비밀번호 노출 구조 등은 개선 후보지만 운영 영향 검토 후 변경.

## 버전

- CentOS 7, Ansible 2.9, Python 2.7 등 노후 구성 의존성이 존재하므로 단순 업그레이드 금지.
- Tomcat/Apache 버전은 취약점 검토 전 반드시 현재 버전을 재확인.
