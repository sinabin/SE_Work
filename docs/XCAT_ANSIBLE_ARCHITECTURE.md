# Xcat 서버 Ansible 및 일일점검 운영 구조 상세 파악 보고서

- 문서 버전: v2.0
- 작성일: 2026-08-06
- 대상 서버: Xcat 서버
- 대상 업무: Ansible 및 연관 일일점검 체계
- 작성 목적: 이틀간의 짧은 인수인계 이후, 실제 명령·설정·플레이북·DB 데이터를 역추적하여 운영 구조와 일상 점검 절차를 파악
- 분석 원칙: 운영 설정을 변경하지 않고 조회 결과를 기준으로 정리
- 이번 문서 범위: **Ansible 및 Ansible과 연결된 일일점검 업무를 우선 분석**
- 이번 문서 제외 범위: Prometheus와 Grafana의 상세 구성은 후속 분석으로 보류

---

## 1. 핵심 결론

현재 Xcat 서버에서 이전 담당자가 안내한 일일 점검은 다음 두 작업으로 나뉜다.

```text
1. ccnuser 계정
   └─ dailycheck
      └─ Linux 및 일부 장비의 모니터링 대시보드 조회

2. root 계정
   └─ win_dailycheck
      ├─ Ansible로 Windows 서버 16대에 접속
      ├─ CPU·메모리·가동시간·디스크·지정 프로세스 수집
      ├─ Xcat 서버의 MySQL DB에 결과 적재
      └─ Python 프로그램으로 최신 결과 표 출력
```

두 명령은 이름이 비슷하지만 동작 방식이 다르다.

| 구분 | `ccnuser dailycheck` | `root win_dailycheck` |
|---|---|---|
| 구현 방식 | sysmon 쉘 스크립트 | Ansible 플레이북 + Python |
| 실행 파일 | `monitor_dashboard.sh` | `win_dailycheck.yml` + `dailycheck.py` |
| 주요 대상 | Linux 서버 및 일부 장비 | Windows 서버 16대 |
| 실행 시 직접 수집 | 추가 확인 필요. 현재는 대시보드 조회 성격으로 판단 | 실행 시 Windows 서버에 직접 접속하여 수집 |
| DB 적재 | sysmon 수집 구조 추가 분석 필요 | `win_monitoring.win_server_status`에 직접 INSERT |
| Vault 사용 | 없음 | 있음 |
| 실행 계정 | `ccnuser` | `root` |

따라서 **Linux 일일점검과 Windows 일일점검을 동일한 Ansible 작업으로 이해하면 안 된다.**

`win_dailycheck`는 명확한 Ansible 작업이다.

반면 `ccnuser`의 `dailycheck`는 현재까지 확인한 범위에서는 `/home/ccnuser/sysmon` 기반의 별도 자체 모니터링 체계다.

---

## 2. 서버 및 Ansible 기본 환경

### 2.1 시스템 정보

| 항목 | 확인 결과 |
|---|---|
| 호스트명 | `xcat` |
| 운영체제 | CentOS Linux 7 (Core) |
| 시간대 | KST |
| 주요 운영 계정 | `root`, `ccnuser` |
| Ansible 실행파일 | `/usr/bin/ansible` |
| ansible-playbook | `/usr/bin/ansible-playbook` |
| ansible-inventory | `/usr/bin/ansible-inventory` |

### 2.2 Ansible 버전

```text
ansible 2.9.27
config file = /etc/ansible/ansible.cfg
ansible python module location = /usr/lib/python2.7/site-packages/ansible
executable location = /usr/bin/ansible
python version = 2.7.5
```

설치 패키지:

```text
ansible-2.9.27-1.el7.noarch
```

설치 방식은 `pip3`가 아니라 CentOS RPM 패키지다.

### 2.3 Python 환경

| 구분 | 버전 |
|---|---|
| Ansible 실행 Python | Python 2.7.5 |
| 별도 Python 3 | Python 3.8.12 |

현재 Ansible 및 후처리 Python 코드가 Python 2.7 문법에 의존하므로 구조 파악 전에 임의 업그레이드를 진행하면 안 된다.

`dailycheck.py`에도 다음과 같은 Python 2 전용 코드가 존재한다.

```python
reload(sys)
sys.setdefaultencoding('utf-8')
```

---

## 3. Ansible 디렉터리 구조

기본 경로:

```text
/etc/ansible/
```

확인된 구조:

```text
/etc/ansible/
├── ansible/
├── ansible.cfg
├── ansible.cfg.rpmnew
├── hosts
├── hosts.rpmnew
├── playbooks/
├── result/
├── roles/
└── yumdir/
```

실제 운영 플레이북의 중심 경로:

```text
/etc/ansible/playbooks
```

`/etc/ansible/ansible` 아래에는 `.git`, `.github`, `lib`, `bin`, `test` 등이 존재하므로 실제 운영 프로젝트라기보다 Ansible 소스 트리로 판단된다.

---

## 4. Ansible 설정

실제 적용 설정 파일:

```text
/etc/ansible/ansible.cfg
```

주요 설정:

```ini
[defaults]
inventory = /etc/ansible/hosts
transport = smart
ansible_python_interpreter = /usr/bin/python
private_key_file = /home/ccnuser/.ssh/id_rsa
```

### 4.1 설정 의미

| 설정 | 의미 |
|---|---|
| `inventory=/etc/ansible/hosts` | 기본 관리 대상 서버 인벤토리 |
| `transport=smart` | 환경에 맞는 SSH 전송 방식 선택 |
| `private_key_file=/home/ccnuser/.ssh/id_rsa` | Linux 계열 대상 접속에 사용하는 기본 개인키 |
| `ansible_python_interpreter=/usr/bin/python` | 대상 서버의 Python 경로로 사용하려는 설정 |

`ansible_python_interpreter`는 `ansible-config dump --only-changed`에 표시되지 않아 실제 전역 적용 여부는 추가 확인이 필요하다.

---

## 5. 인벤토리와 Ansible Vault

기본 인벤토리:

```text
/etc/ansible/hosts
```

첫 줄:

```text
$ANSIBLE_VAULT;1.1;AES256
```

따라서 인벤토리 전체가 Ansible Vault로 암호화되어 있다.

Vault 비밀번호를 제공하지 않고 실행하면 다음 오류가 발생한다.

```text
Attempting to decrypt but no vault secrets found
Unable to parse /etc/ansible/hosts as an inventory source
No inventory was parsed, only implicit localhost is available
```

이는 인벤토리 손상이 아니라 복호화 비밀번호가 제공되지 않은 결과다.

### 5.1 조회와 편집

조회:

```bash
ansible-vault view /etc/ansible/hosts
```

편집:

```bash
ansible-vault edit /etc/ansible/hosts
```

`edit`는 임시 복호화 후 편집하고 저장할 때 다시 암호화한다.

운영 중 다음 명령으로 평문 상태를 유지하지 않는 것이 좋다.

```bash
ansible-vault decrypt /etc/ansible/hosts
```

### 5.2 Vault 비밀번호 파일

확인된 파일:

```text
/etc/ansible/playbooks/vault_password.txt
/etc/ansible/playbooks/txt/vault.txt
```

현재 활성 Cron은 다음 파일을 사용한다.

```text
/etc/ansible/playbooks/txt/vault.txt
```

권한:

```text
-rw-r--r-- root root
```

다른 일반 사용자가 읽을 수 있을 가능성이 있으므로 보안상 개선 대상이지만, 자동 실행 영향도를 확인하기 전에 임의 변경하면 안 된다.

---

## 6. 계정별 운영 역할

### 6.1 root 계정

주요 역할:

```text
Ansible 인벤토리 및 플레이북 운영
Windows 일일점검
Linux 비밀번호 변경
Ansible Cron 실행
Ansible 결과 후처리
```

`/etc/ansible`의 파일과 디렉터리는 대부분 `root:root` 소유다.

### 6.2 ccnuser 계정

주요 역할:

```text
sysmon 대시보드 조회
Linux/장비 점검 결과 확인
sysmon 로그 조회
라이선스 목록 관리
pdsh 사용
SSH 키 보유
```

주요 경로:

```text
/home/ccnuser/.ssh
/home/ccnuser/sysmon/sbin
/home/ccnuser/log/xcat
```

---

## 7. 운영 alias

### 7.1 root 계정 alias

정의 위치:

```text
/root/.bashrc
```

#### win_dailycheck

```bash
alias win_dailycheck='ansible-playbook --ask-vault-pass /etc/ansible/playbooks/win_dailycheck.yml && python /etc/ansible/playbooks/pythonscript/dailycheck.py'
```

#### web_dailycheck

```bash
alias web_dailycheck='ansible-playbook --ask-vault-pass /etc/ansible/playbooks/web_dailycheck.yml'
```

#### windows_dailycheck

```bash
alias windows_dailycheck='ansible-playbook --ask-vault-pass /etc/ansible/playbooks/win_monitoring.yml'
```

#### root의 dailycheck

```bash
alias dailycheck='python /etc/ansible/playbooks/pythonscript/dailycheck.py'
```

#### redhat_password

```bash
alias redhat_password='ansible-playbook -i /etc/ansible/hosts --limit redhat /etc/ansible/playbooks/linux_change_password.yml --ask-vault'
```

#### centos_password

```bash
alias centos_password='ansible-playbook -i /etc/ansible/hosts --limit centos /etc/ansible/playbooks/linux_change_password.yml --ask-vault'
```

### 7.2 ccnuser 계정 alias

정의 위치:

```text
/home/ccnuser/.bashrc
```

#### ccnuser의 dailycheck

```bash
alias dailycheck='/home/ccnuser/sysmon/sbin/monitor_dashboard.sh'
```

#### xcatlogs

```bash
alias xcatlogs='cd /home/ccnuser/log/xcat/'
```

#### viewlog

```bash
alias viewlog='tail -n 500 $(ls -1t /home/ccnuser/log/xcat/sys_logs/syslog_*.log | head -n 1)'
```

#### syslog

```bash
alias syslog='grep -i --color=auto "warning" $(ls -1t /home/ccnuser/log/xcat/sys_logs/syslog_*.log | head -n 1)'
```

#### license

```bash
alias license='vi /home/ccnuser/sysmon/sbin/txt_file/license_list.txt'
```

### 7.3 주의사항

동일한 `dailycheck` 명령이라도 계정에 따라 완전히 다른 프로그램이 실행된다.

```text
root의 dailycheck
→ Windows DB 결과 출력용 Python

ccnuser의 dailycheck
→ Linux/sysmon 모니터링 대시보드
```

명령 실행 전 반드시 다음 명령으로 계정을 확인해야 한다.

```bash
whoami
```

---

## 8. 이전 담당자가 안내한 일일 점검 절차

### 8.1 Linux 계열 일일점검

```text
1. ccnuser 계정 로그인
2. dailycheck 실행
3. 대시보드에서 이상 항목 확인
```

명령:

```bash
dailycheck
```

실제 실행 대상:

```text
/home/ccnuser/sysmon/sbin/monitor_dashboard.sh
```

### 8.2 Windows 일일점검

```text
1. root 계정 로그인
2. win_dailycheck 실행
3. Vault 비밀번호 입력
4. Ansible PLAY RECAP 확인
5. 최종 Windows 리포트 확인
```

명령:

```bash
win_dailycheck
```

실제 실행 순서:

```text
ansible-playbook --ask-vault-pass win_dailycheck.yml
&&
python dailycheck.py
```

`&&`가 있으므로 플레이북이 정상 종료되어야 Python 리포트가 실행된다.

---

# 9. ccnuser dailycheck 상세 분석

## 9.1 명령 성격

`ccnuser`의 `dailycheck`는 Ansible 플레이북이 아니다.

실제 명령:

```text
/home/ccnuser/sysmon/sbin/monitor_dashboard.sh
```

출력 제목:

```text
SERVER MONITORING DASHBOARD
```

현재 출력만으로 확인되는 역할은 수집 결과를 한 화면에 종합 표시하는 대시보드다.

실제 데이터가 어느 DB 또는 로그에서 조회되는지는 `monitor_dashboard.sh` 소스 분석이 필요하다.

## 9.2 출력 항목

| 항목 | 의미 |
|---|---|
| `HOSTNAME` | 대상 서버 또는 장비 |
| `CPU` | CPU 사용률 |
| `MEM` | 메모리 사용률 |
| `SEC EVENT` | 보안 이벤트 상태 |
| `NTP IP (TIME)` | NTP 동기화 서버 및 시각 |
| `SERVICE` | 지정 서비스 또는 프로세스 상태 |
| `ACC STATUS` | 계정 상태 |
| `DISK(>80%)` | 80% 초과 디스크 |
| `NFS` | NFS 상태 |

하단에는 다음 정보가 추가 출력된다.

```text
LICENSE STATUS SUMMARY
```

포함 항목:

```text
SSL 인증서
Machine 인증서
각종 솔루션 라이선스
분기별 비밀번호 변경 기한
```

## 9.3 2026-08-06 14:37 실행 시 확인된 주의 항목

### 디스크 80% 초과

| 호스트 | 표시 |
|---|---|
| `ccnbib01` | `/media(82%)` |
| `ccndb` | `/share(86%)` |
| `ccnstaters01` | `/data(81%)` |
| `ccnwas1` | `/DATA/ccndata(86%)` |
| `ccnwas2` | `/DATA/ccndata(86%)` |
| `sms_server` | `/DATA/ccndata(86%)` |

### NTP 비동기화 또는 확인 필요

| 호스트 | 표시 |
|---|---|
| `ccnprivacy` | `NoSync` |
| `ccnsearch` | `NoSync (08:30)` |
| `spam` | `NoSync` |

### 서비스 또는 프로세스 표시

| 호스트 | 표시 |
|---|---|
| `ccnweb1` | `httpd(Zombie:1)` |
| `ccnweb2` | `httpd(Zombie:1)` |
| `xcat` | `/usr/sbin/httpd(Down)` |

### 계정 상태

| 호스트 | 표시 |
|---|---|
| `ccnsearch` | `Exp(+881)` |

`Exp(+881)`의 정확한 산정 기준과 의미는 sysmon 소스 또는 계정 점검 스크립트에서 추가 확인해야 한다.

### 라이선스 만료가 가까운 항목

실행일 기준:

| 항목 | 잔여일 |
|---|---:|
| Expressway Certificate | D-27 |
| OZ Report License | D-35 |
| 2026 3 Quarter Password | D-55 |

## 9.4 운영자가 매일 볼 항목

```text
1. CPU와 메모리 비정상 수치
2. SEC EVENT가 Clean이 아닌 서버
3. NTP NoSync
4. SERVICE의 Down 또는 Zombie
5. ACC STATUS의 Exp 또는 비정상 표시
6. DISK(>80%) 항목
7. NFS 비정상
8. 가까운 라이선스 만료일
```

---

# 10. root win_dailycheck 전체 실행 구조

## 10.1 실행 흐름

```text
root
  ↓
win_dailycheck alias
  ↓
Vault 비밀번호 입력
  ↓
/etc/ansible/playbooks/win_dailycheck.yml 복호화 및 실행
  ↓
인벤토리 Windows 그룹의 16대 서버에 접속
  ↓
PowerShell로 시스템 정보 수집
  ↓
호스트별 JSON 결과를 Ansible 변수에 저장
  ↓
Xcat 로컬에 호스트별 SQL 파일 생성
  ↓
Xcat 로컬 MySQL의 win_monitoring DB에 INSERT
  ↓
임시 SQL 파일 삭제
  ↓
PLAY RECAP
  ↓
dailycheck.py 실행
  ↓
DB에서 서버별 최신 행 조회
  ↓
터미널 표 출력
```

## 10.2 실제 점검 대상 서버 수

2026-08-06 실행 결과 기준:

```text
Windows 서버 16대
```

확인된 호스트:

```text
1372gov
ccnctiada
ccnctiadb
ccnctiaws01
ccnctiaws02
ccnctipga
ccnctipgb
ccnctirgra
ccnctirgrb
ccnfaxsvr01
ccnivrcvp01
ccnivrcvp02
ccnivroamp
ccnnms
ccnpdf
ccnsvn
```

## 10.3 실행 성공 결과

모든 대상 서버의 PLAY RECAP:

```text
ok=5
changed=4
unreachable=0
failed=0
```

의미:

```text
16대 모두 Ansible 원격 접속 성공
16대 모두 PowerShell 수집 성공
16대 모두 SQL 생성 및 DB INSERT 성공
16대 모두 임시 SQL 파일 정리 성공
```

`changed=4`는 Windows 서버 설정이 네 번 변경됐다는 의미가 아니다.

다음 작업이 Ansible에서 기본적으로 `changed`로 표시되기 때문이다.

```text
win_shell 실행
SQL 파일 생성
MySQL shell 실행
SQL 파일 삭제
```

---

# 11. win_dailycheck.yml 상세 분석

파일:

```text
/etc/ansible/playbooks/win_dailycheck.yml
```

파일 자체도 Ansible Vault로 암호화되어 있다.

조회:

```bash
ansible-vault view /etc/ansible/playbooks/win_dailycheck.yml
```

## 11.1 Play 정의

```yaml
- name: Windows 서버 모니터링 (상태값 및 프로세스 상세화)
  hosts: Windows
  gather_facts: no
```

의미:

```text
인벤토리의 Windows 그룹 전체 실행
기본 facts 수집 안 함
PowerShell로 필요한 항목만 직접 수집
```

## 11.2 주요 변수

```yaml
mysql_db: "win_monitoring"
temp_dir: "/tmp/ansible_sql"

cpu_caution: 60
cpu_danger: 90
mem_caution: 60
mem_danger: 90
```

판정 기준:

| 항목 | Normal | Caution | Danger |
|---|---|---|---|
| CPU | 60% 미만 | 60% 이상 90% 미만 | 90% 이상 |
| Memory | 60% 미만 | 60% 이상 90% 미만 | 90% 이상 |

## 11.3 Task 1: 임시 디렉터리 준비

```yaml
- name: Ensure temp directory exists
  file:
    path: "{{ temp_dir }}"
    state: directory
    mode: '0777'
  delegate_to: localhost
```

실제 실행 위치:

```text
Xcat 서버 localhost
```

생성 경로:

```text
/tmp/ansible_sql
```

`0777` 권한은 보안상 개선 검토 대상이다.

현재 운영 영향도를 확인하기 전에 변경하면 안 된다.

## 11.4 Task 2: 시스템 지표 수집

모듈:

```yaml
win_shell
```

각 Windows 서버에서 PowerShell을 실행한다.

### CPU

```powershell
Get-Counter '\Processor(_Total)\% Processor Time'
```

소수점 첫째 자리까지 반올림한다.

### 메모리

```text
(전체 물리 메모리 - 사용 가능 메모리)
÷ 전체 물리 메모리
× 100
```

### 가동시간

```powershell
Win32_OperatingSystem.LastBootUpTime
```

표현 형식:

```text
144d 22h 46m
```

### 디스크

```powershell
Get-WmiObject Win32_LogicalDisk
Where-Object { $_.DriveType -eq 3 }
```

로컬 고정 디스크만 수집한다.

출력 예:

```text
C: [50.3/79.7GB] (63.1%) | D: [356.8/500GB] (71.4%)
```

현재 플레이북에는 디스크 상태를 `Normal/Caution/Danger`로 판정하는 로직은 없다.

디스크 사용량을 문자열로 수집하여 저장한다.

### 지정 프로세스

서버별 변수:

```yaml
process_name
```

PowerShell:

```powershell
Get-Process -Name $p
```

판정:

```text
프로세스 존재 → 프로세스명(OK)
프로세스 없음 → 프로세스명(Down)
```

요약:

```text
모두 존재 → p_sum = OK
하나라도 없음 → p_sum = Check
```

세부 결과:

```text
tomcat8(OK), vmtoolsd(OK), java(OK)
```

프로세스 목록은 각 서버의 `host_vars`에서 관리되는 것으로 판단된다.

## 11.5 JSON 변환

PowerShell 수집 결과를 압축 JSON으로 출력한다.

구조:

```json
{
  "cpu": 5.1,
  "cpu_status": "Normal",
  "mem": 69.2,
  "mem_status": "Caution",
  "uptime": "144d 22h 46m",
  "disk": "C: [50.3/79.7GB] (63.1%)",
  "p_sum": "OK",
  "p_det": "sqlservr(OK), Tomcat7(OK)"
}
```

Ansible 변수:

```yaml
register: win_raw
```

실제 JSON 문자열:

```text
win_raw.stdout
```

## 11.6 오류 처리

PowerShell 전체가 `try/catch`로 감싸져 있다.

오류 시 반환:

```json
{
  "cpu": 0,
  "cpu_status": "Error",
  "mem": 0,
  "mem_status": "Error",
  "uptime": "Error",
  "disk": "Error",
  "p_sum": "Check",
  "p_det": "WMI Error"
}
```

수집 오류가 발생해도 JSON을 만들어 DB에 Error 상태를 적재하도록 설계되어 있다.

## 11.7 Task 3: SQL 파일 생성

실행 위치:

```text
Xcat localhost
```

파일 예:

```text
/tmp/ansible_sql/ccnsvn.sql
/tmp/ansible_sql/ccnpdf.sql
```

INSERT 대상:

```text
win_monitoring.win_server_status
```

저장 컬럼:

```text
hostname
check_time
cpu_usage
mem_usage
uptime
cpu_status
memory_status
disk_status
process_status_summary
process_details
```

## 11.8 Task 4: MySQL 실행

명령 구조:

```bash
mysql -h localhost -u <계정> -p'<비밀번호>' win_monitoring < 호스트별.sql
```

실행 위치는 Xcat 서버 로컬이다.

따라서 데이터 흐름은 다음과 같다.

```text
Windows 서버
→ Ansible/PowerShell
→ Xcat 임시 SQL
→ Xcat MySQL
→ win_monitoring.win_server_status
```

## 11.9 Task 5: 임시 SQL 삭제

```yaml
state: absent
```

정상 실행 후 호스트별 SQL 파일은 삭제된다.

실패 시 잔여 파일 확인 경로:

```bash
ls -al /tmp/ansible_sql
```

---

# 12. Windows DB 구조와 실제 적재 데이터

## 12.1 DB

```text
win_monitoring
```

확인된 테이블:

```text
system_health
win_disk_inventory
win_server_status
win_systemcheck
```

## 12.2 win_server_status 컬럼

```text
id
hostname
check_time
cpu_usage
mem_usage
uptime
cpu_status
memory_status
disk_status
process_status_summary
process_details
json_data
```

## 12.3 현재 플레이북이 실제로 저장하는 컬럼

```text
hostname
check_time
cpu_usage
mem_usage
uptime
cpu_status
memory_status
disk_status
process_status_summary
process_details
```

`json_data`는 현재 `win_dailycheck.yml`의 INSERT 대상이 아니다.

따라서 최신 행에서 `json_data`가 NULL인 것은 현재 코드 기준으로 자연스럽다.

## 12.4 2026-08-06 데이터 적재 확인

확인된 실행 시각:

```text
08:32경
08:56경
13:45경
```

13:45 실행에서는 16대 모두 최신 행이 생성되었다.

예:

```text
ccnivrcvp01
CPU: 0.0
Memory: 59.0
Uptime: 144d 22h 45m
Process summary: OK
Process details: tomcat8(OK), vmtoolsd(OK), java(OK)
```

다른 서버들도 `process_status_summary=OK`와 등록 프로세스별 `(OK)` 값이 적재되었다.

따라서 2026-08-06 13:45 실행 시점에는 다음이 확인된다.

```text
Windows 서버 16대 원격 응답 성공
시스템 지표 수집 성공
등록된 지정 프로세스 모두 실행 중
DB 적재 성공
```

## 12.5 데이터 저장 방식

플레이북은 매 실행 시 `UPDATE`가 아니라 `INSERT`를 수행한다.

```text
실행할 때마다 서버별 신규 행 추가
```

따라서 `win_server_status`는 점검 이력 테이블이다.

---

# 13. dailycheck.py 상세 분석

파일:

```text
/etc/ansible/playbooks/pythonscript/dailycheck.py
```

역할:

```text
Windows 서버에 접속하지 않음
DB에 INSERT하지 않음
win_server_status의 최신 데이터를 SELECT
터미널 표 생성
```

## 13.1 조회 쿼리

```sql
SELECT hostname, cpu_usage, mem_usage, cpu_status,
       memory_status, disk_status, json_data, check_time
FROM win_server_status
WHERE id IN (
    SELECT MAX(id)
    FROM win_server_status
    GROUP BY hostname
)
ORDER BY hostname ASC;
```

각 호스트별 `id`가 가장 큰 최신 행 한 건을 조회한다.

## 13.2 출력 컬럼

```text
hostname
CPU
stat
Memory
stat
Disk Status
Service (Stopped)
Process Status
```

## 13.3 사용하지 않는 임계치 변수

Python 코드에는 다음 값이 있다.

```python
cpu_threshold = 50.0
memory_threshold = 60.0
```

하지만 실제 판정에는 사용하지 않는다.

CPU와 메모리 상태는 플레이북이 계산하여 DB에 저장한 값을 그대로 출력한다.

## 13.4 현재 데이터 구조와의 불일치

`dailycheck.py`는 다음 데이터를 `json_data`에서 찾는다.

```text
disks
health.svcs
health.procs
```

그러나 현재 플레이북은 프로세스 결과를 별도 컬럼에 저장한다.

```text
process_status_summary
process_details
```

그리고 `json_data`는 최신 데이터에서 NULL이다.

따라서 현재 Python 출력은 다음 현상을 보인다.

```text
DB의 process_status_summary = OK
DB의 process_details = 실제 프로세스 목록
최종 Process Status = N/A
```

이것은 프로세스 수집 실패가 아니다.

**수집과 DB 적재는 정상이고, Python이 실제 프로세스 컬럼을 읽지 않기 때문에 N/A로 표시되는 것이다.**

---

# 14. `All Running` 표시의 정확한 해석

## 14.1 실행 당일 실제 상태

2026-08-06 13:45 데이터 기준:

```text
16대 원격 접속 성공
16대 지표 수집 성공
16대 process_status_summary = OK
등록된 프로세스가 모두 (OK)
```

따라서 운영자가 전체 상태를 다음처럼 표현하는 것은 실무적으로 타당하다.

```text
All Running
```

정확한 의미:

```text
해당 실행에서 점검 대상으로 등록된 프로세스가 모두 실행 중
```

## 14.2 코드상 표시 근거

그러나 현재 최종 표의 `Service (Stopped) = All Running`은 실제 `process_status_summary`를 기준으로 출력된 값이 아니다.

현재 Python 로직:

```text
json_data.health.svcs가 비어 있음
→ 중지 서비스 목록도 비어 있음
→ All Running 출력
```

현재 플레이북에는 Windows 서비스 상태를 별도로 수집하는 코드가 확인되지 않았다.

따라서 다음을 구분해야 한다.

```text
실제 운영 상태:
등록된 프로세스 모두 정상 → All Running이라고 요약 가능

현재 리포트 구현:
서비스 데이터가 비어 있어도 All Running 출력
```

이번 실행에서는 실제 프로세스가 모두 OK이므로 결과 의미는 일치한다.

하지만 향후 프로세스 하나가 Down인 경우에도 현재 Python 코드가 다음처럼 표시할 가능성이 있다.

```text
DB process_status_summary = Check
DB process_details = tomcat8(Down), java(OK)

최종 표
Service (Stopped) = All Running
Process Status = N/A
```

따라서 문구 자체가 문제라기보다 **표시 기준이 실제 DB 프로세스 상태와 연결되지 않은 점**이 개선 대상이다.

## 14.3 현재 운영 판단 방법

현재는 다음 두 결과를 함께 확인해야 한다.

### Ansible PLAY RECAP

```text
unreachable=0
failed=0
```

### DB 프로세스 상태

```text
process_status_summary = OK
process_details의 모든 항목 = (OK)
```

두 조건을 만족하면:

```text
Windows 서버 접속 및 수집 정상
등록된 지정 프로세스 모두 정상
전체 All Running
```

으로 판단할 수 있다.

---

# 15. 2026-08-06 Windows 일일점검 결과 요약

## 15.1 접속 및 실행

```text
대상 서버: 16대
unreachable: 0
failed: 0
```

전체 수집 및 DB 적재 성공.

## 15.2 메모리 Caution

플레이북 기준 60% 이상 90% 미만.

확인된 서버 예:

```text
1372gov
ccnctiaws01
ccnctiaws02
ccnctirgra
ccnctirgrb
ccnfaxsvr01
ccnivroamp
ccnnms
```

## 15.3 디스크 주의

`ccnfaxsvr01`:

```text
C: 83.6%
```

플레이북에는 디스크 임계치 판정이 없으므로 화면에서 별도의 Caution/Danger 상태로 변환되지 않는다.

운영자가 문자열의 사용률을 직접 확인해야 한다.

## 15.4 프로세스

최신 DB 데이터에서 모든 서버:

```text
process_status_summary = OK
```

각 서버별 지정 프로세스도 `(OK)`로 저장됨.

---

# 16. Windows 일일점검 운영 체크리스트

## 16.1 실행 전

```bash
whoami
```

결과가 `root`인지 확인한다.

## 16.2 실행

```bash
win_dailycheck
```

Vault 비밀번호 입력.

## 16.3 Ansible 출력 확인

다음 항목을 우선 확인한다.

```text
UNREACHABLE
FAILED
```

정상 기준:

```text
모든 서버 unreachable=0
모든 서버 failed=0
```

## 16.4 최종 리포트 확인

```text
CPU Danger/Caution
Memory Danger/Caution
디스크 고사용률
Process Status
```

현재 `Process Status=N/A`는 실제 프로세스 미점검을 의미하지 않는다.

정확한 프로세스 결과는 DB의 다음 컬럼을 기준으로 확인한다.

```text
process_status_summary
process_details
```

## 16.5 DB 최신 데이터 확인

예시 SQL:

```sql
SELECT
    id,
    hostname,
    check_time,
    cpu_usage,
    mem_usage,
    uptime,
    cpu_status,
    memory_status,
    disk_status,
    process_status_summary,
    process_details
FROM win_monitoring.win_server_status
WHERE id IN (
    SELECT MAX(id)
    FROM win_monitoring.win_server_status
    GROUP BY hostname
)
ORDER BY hostname;
```

## 16.6 비정상 판단

### 서버 접속 실패

```text
unreachable > 0
```

확인 대상:

```text
서버 전원
네트워크
WinRM
방화벽
인벤토리 접속 정보
Windows 계정/비밀번호
```

### 플레이북 Task 실패

```text
failed > 0
```

확인 대상:

```text
PowerShell 실행
WMI
Get-Counter
JSON 변환
SQL 생성
MySQL 연결
DB 계정 권한
디스크 및 /tmp 권한
```

### 프로세스 이상

```text
process_status_summary = Check
```

`process_details`에서 `(Down)` 항목을 확인한다.

---

# 17. Cron 자동 실행 구조

`crontab -l`은 root와 ccnuser 모두 다음 오류가 발생했다.

```text
/usr/bin/crontab: Permission denied
```

따라서 다음 파일을 직접 조회했다.

```text
/var/spool/cron/root
/var/spool/cron/ccnuser
```

## 17.1 활성 Ansible Cron

### 매일 07:10

```cron
10 7 * * * /usr/bin/ansible-playbook -vvv \
--vault-password-file /etc/ansible/playbooks/txt/vault.txt \
/etc/ansible/playbooks/disk_inventory.yml \
>> /etc/ansible/playbooks/logs/ansible_cron.log 2>&1
```

### 매일 07:55

```cron
55 7 * * * /usr/bin/ansible-playbook -vvv \
--vault-password-file /etc/ansible/playbooks/txt/vault.txt \
/etc/ansible/playbooks/win_dailycheck.yml \
>> /etc/ansible/playbooks/logs/ansible_cron.log 2>&1
```

자동 실행은 `win_dailycheck.yml`만 수행하며 `dailycheck.py`는 실행하지 않는다.

따라서 Cron은 DB 적재가 목적이고, 수동 `win_dailycheck`는 DB 적재 후 화면 리포트까지 보여주는 구조다.

## 17.2 주석 처리된 Ansible Cron

```text
win_dailycheck7.yml
과거 win_dailycheck.yml
win_monitoring.yml
```

현재는 실행되지 않는다.

---

# 18. sysmon 및 ccnuser Cron

## 18.1 ccnuser Cron

| 주기 | 작업 |
|---|---|
| 매시 00분, 30분 | `l_cron_system_check.sh all all` |
| 매일 00:05 | `l_cron_collect_log.sh` |
| 매일 07:40 | `l_cron_system_df.sh daily` |
| 매주 금요일 07:40 | `l_cron_system_df.sh weekly` |

## 18.2 root에서 실행하는 sysmon 작업

| 주기 | 작업 |
|---|---|
| 매시 00분, 30분 | `p_run_syslog.sh` |
| 매일 07:00 | `all_disk.sh` |
| 매일 07:30 | `vvb_status.sh` |
| 매월 1일 00:05 | `monthly_report.sh` |
| 매월 1일 01:00 | `cleanup_logs.sh` |
| 매일 03:00 | `cleanup_scouter.sh` |

Linux `dailycheck` 대시보드의 원천 데이터를 어떤 Cron과 DB가 제공하는지는 sysmon 스크립트 분석으로 추가 확인해야 한다.

---

# 19. pdsh 운영

그룹 경로:

```text
/etc/dsh/group
```

확인된 그룹:

```text
all
others
rec
server
sta
tts
```

사용 예:

```bash
pdsh -g all "df -h"
```

Ansible과의 차이:

| 도구 | 용도 |
|---|---|
| Ansible | 플레이북 기반 자동화, 상태 수집, DB 적재 |
| pdsh | 여러 서버에 단순 명령을 즉시 병렬 실행 |

그룹 파일 권한은 `666`으로 확인되어 보안 개선 검토가 필요하지만, 영향도 분석 전 변경하면 안 된다.

---

# 20. 현재 확인된 기술적 주의사항

## 20.1 노후 버전

```text
CentOS 7
Ansible 2.9.27
Python 2.7.5
```

기존 코드 의존성을 분석하기 전 업그레이드 금지.

## 20.2 Vault 파일 권한

```text
-rw-r--r--
```

보안 개선 검토 필요.

## 20.3 임시 SQL 디렉터리 0777

```text
/tmp/ansible_sql
```

SQL 파일이 생성되는 동안 다른 사용자가 접근할 가능성이 있다.

## 20.4 DB 비밀번호 명령행 사용

```bash
mysql -p'<비밀번호>'
```

프로세스 목록 또는 상세 로그에 노출될 가능성을 검토해야 한다.

## 20.5 dailycheck.py 데이터 연결 불일치

```text
플레이북:
process_status_summary, process_details 저장

Python:
json_data.health.procs 조회
```

따라서 프로세스 최종 표시는 N/A로 나온다.

## 20.6 서비스 컬럼 명칭

현재 플레이북은 지정 프로세스를 점검하지만 최종 표에는:

```text
Service (Stopped)
Process Status
```

두 컬럼이 존재한다.

실제 서비스 수집은 현재 `win_dailycheck.yml`에서 확인되지 않았다.

## 20.7 최신 데이터 시각 검증

`dailycheck.py`는 호스트별 최대 `id`만 조회하고 `check_time`이 오늘인지 별도 검증하지 않는다.

다만 수동 `win_dailycheck`는 플레이북 성공 후에만 Python이 실행되므로 정상 실행 시 방금 적재된 행을 조회한다.

`root dailycheck`를 Python만 단독 실행할 경우 오래된 최신 행이 표시될 가능성을 염두에 둬야 한다.

## 20.8 디스크 임계치 없음

Windows 플레이북은 디스크 사용률을 수집하지만 상태 판정은 하지 않는다.

80% 이상 디스크를 자동 강조하려면 후속 개선이 필요하다.

---

# 21. 현재까지 확정된 운영 판단 기준

## Linux/sysmon 대시보드

정상 여부 판단:

```text
CPU/MEM 수치
SEC EVENT
NTP 동기화
SERVICE Down/Zombie
계정 만료
디스크 80% 초과
NFS
라이선스 잔여일
```

## Windows/Ansible

정상 여부 판단:

```text
PLAY RECAP:
unreachable=0
failed=0

DB:
오늘자 최신 데이터 존재
process_status_summary=OK
process_details에 Down 없음

지표:
CPU/Memory 상태
디스크 사용률 직접 확인
```

## All Running 판단

다음 조건을 만족하면 실무적으로 `All Running`으로 판단 가능하다.

```text
모든 Windows 서버 원격 접속 성공
모든 서버 수집 성공
모든 등록 프로세스가 (OK)
```

현재 최종 표의 `All Running` 출력 코드가 이 DB 값을 직접 참조하지 않는다는 점은 별도의 개선 사항이다.

---

# 22. 추가 분석 우선순위

Ansible을 완전히 파악하려면 다음 순서로 진행한다.

## 1순위: Windows host_vars

```text
/etc/ansible/playbooks/host_vars/*.yml
```

확인 내용:

```text
Windows 접속 계정
WinRM 설정
서버별 process_name
암호화 여부
```

민감정보 값은 공유하지 않고 변수명과 구조만 확인한다.

## 2순위: Vault 인벤토리

```text
/etc/ansible/hosts
```

확인 내용:

```text
Windows 그룹
redhat 그룹
centos 그룹
호스트별 그룹 구조
연결 변수
```

## 3순위: disk_inventory.yml

```text
/etc/ansible/playbooks/disk_inventory.yml
```

확인 내용:

```text
대상 OS와 그룹
수집 항목
DB 테이블
Windows/Linux 디스크 인벤토리 관계
```

## 4순위: linux_change_password.yml

```text
/etc/ansible/playbooks/linux_change_password.yml
```

확인 내용:

```text
계정 변경 방식
redhat/centos 분리 방식
host_vars 사용 방식
암호 해시 처리
```

## 5순위: web_dailycheck.yml

확인 내용:

```text
HTML 생성
/var/www/html 적재
Apache 연계
점검 대상
```

## 6순위: sysmon Linux 수집 구조

```text
monitor_dashboard.sh
l_cron_system_check.sh
p_run_syslog.sh
```

Linux dailycheck가 어떤 데이터 소스를 읽는지 확정한다.

---

# 23. 운영 중 변경 금지 항목

구조 파악이 완료될 때까지 다음 작업을 임의로 수행하지 않는다.

```text
Ansible 업그레이드
Python 업그레이드
CentOS 패키지 대규모 변경
Vault 파일 복호화 상태 유지
Vault 비밀번호 파일 권한 변경
/tmp/ansible_sql 권한 변경
Cron 수정
pdsh 그룹 파일 권한 변경
dailycheck.py 즉시 수정
playbook 즉시 수정
DB 테이블 구조 변경
```

개선이 필요한 항목도 먼저 백업, 영향도 분석, 테스트 후 반영해야 한다.

---

# 24. 최종 정리

현재 Xcat 서버의 일일 점검은 다음 두 축으로 운영된다.

```text
Linux 및 일부 장비
→ ccnuser
→ sysmon dailycheck 대시보드

Windows 서버
→ root
→ Ansible win_dailycheck
→ DB 적재
→ Python 리포트
```

Windows Ansible 점검은 실제로 다음을 정상 수행하고 있다.

```text
Windows 서버 16대 접속
CPU 수집
메모리 수집
가동시간 수집
로컬 디스크 수집
서버별 지정 프로세스 수집
MySQL DB 적재
```

2026-08-06 13:45 실행에서는 16대 모두:

```text
unreachable=0
failed=0
process_status_summary=OK
등록 프로세스 모두 (OK)
```

였으므로 실행 시점 전체 상태를 `All Running`으로 판단할 수 있다.

다만 후처리 `dailycheck.py`는 현재 플레이북이 저장하는 프로세스 컬럼과 연결되지 않아:

```text
Process Status = N/A
```

로 표시한다.

또한 `Service (Stopped) = All Running`은 실제 서비스 점검 결과가 아니라 비어 있는 `json_data`를 기준으로 표시된다.

따라서 현재 운영에서는 Ansible 실행 결과와 DB의 실제 프로세스 컬럼을 함께 확인해야 한다.

향후 개선 시에는 다음 구조가 바람직하다.

```text
process_status_summary=OK
→ All Running

process_status_summary=Check
→ process_details의 Down 항목 출력
```

현재 단계의 최우선 목표는 코드를 바로 변경하는 것이 아니라, 인벤토리와 `host_vars`, 나머지 플레이북을 추가 분석하여 전체 Ansible 운영 구조를 완전히 파악하는 것이다.

---

# 부록 A. 주요 경로

```text
/etc/ansible/ansible.cfg
/etc/ansible/hosts
/etc/ansible/playbooks
/etc/ansible/playbooks/win_dailycheck.yml
/etc/ansible/playbooks/disk_inventory.yml
/etc/ansible/playbooks/linux_change_password.yml
/etc/ansible/playbooks/web_dailycheck.yml
/etc/ansible/playbooks/host_vars
/etc/ansible/playbooks/pythonscript/dailycheck.py
/etc/ansible/playbooks/txt/vault.txt
/etc/ansible/playbooks/vault_password.txt
/etc/ansible/playbooks/logs/ansible_cron.log
/root/.bashrc
/home/ccnuser/.bashrc
/home/ccnuser/sysmon/sbin
/home/ccnuser/log/xcat
/var/spool/cron/root
/var/spool/cron/ccnuser
/etc/dsh/group
/tmp/ansible_sql
/var/www/html
```

---

# 부록 B. 매일 사용하는 핵심 명령

## Linux/sysmon 확인

```bash
su - ccnuser
dailycheck
```

## sysmon 로그 경로 이동

```bash
xcatlogs
```

## 최근 syslog 조회

```bash
viewlog
```

## 최근 warning 조회

```bash
syslog
```

## Windows Ansible 점검

```bash
su - root
win_dailycheck
```

## Vault 파일 조회

```bash
ansible-vault view /etc/ansible/hosts
ansible-vault view /etc/ansible/playbooks/win_dailycheck.yml
```

## Ansible 로그

```bash
tail -n 200 /etc/ansible/playbooks/logs/ansible_cron.log
```

---

# 부록 C. Windows 최신 결과 확인 SQL

```sql
SELECT
    id,
    hostname,
    check_time,
    cpu_usage,
    mem_usage,
    uptime,
    cpu_status,
    memory_status,
    disk_status,
    process_status_summary,
    process_details
FROM win_monitoring.win_server_status
WHERE id IN (
    SELECT MAX(id)
    FROM win_monitoring.win_server_status
    GROUP BY hostname
)
ORDER BY hostname;
```

프로세스 이상만 조회:

```sql
SELECT
    hostname,
    check_time,
    process_status_summary,
    process_details
FROM win_monitoring.win_server_status
WHERE id IN (
    SELECT MAX(id)
    FROM win_monitoring.win_server_status
    GROUP BY hostname
)
AND process_status_summary <> 'OK'
ORDER BY hostname;
```

오늘자 데이터 확인:

```sql
SELECT
    hostname,
    MAX(check_time) AS latest_check
FROM win_monitoring.win_server_status
WHERE check_time >= CURDATE()
GROUP BY hostname
ORDER BY hostname;
```
