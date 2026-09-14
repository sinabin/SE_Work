# dailycheck 결과 읽는 법 (ccnuser 기준)

> 대상 스크립트: `/home/ccnuser/sysmon/sbin/monitor_dashboard.sh` (alias: `ccnuser`의 `dailycheck`)
> 실행: `su - ccnuser` → `dailycheck`
> 이 문서는 명령 실행 시 나오는 **SERVER MONITORING DASHBOARD** 표와 **LICENSE STATUS SUMMARY** 표의 각 컬럼/값이 무엇을 의미하는지 정리한 것입니다.

---

## 1. 전체 동작 개요

`dailycheck`는 xcat 서버에서 `pdsh`(원격 SSH 병렬 실행)로 대부분의 리눅스 서버를 점검하고, 방식이 다른 3종류 장비는 별도 로직으로 점검합니다.

| 대상 | 수집 방식 |
|---|---|
| 일반 리눅스 서버 (약 30여 대) | `pdsh -g all` — SSH로 접속해 원격에서 직접 쉘 명령 실행 |
| `ccnsearch` (Solaris) | pdsh 미사용. `/home/ccnuser/data/ccnsearch/`에 미리 쌓인 텍스트 파일을 파싱 |
| `vg1`, `vg2`, `ipcc_sw01`, `ipcc_sw02` (Cisco 네트워크 장비) | SSH 불가 대상이라 **SNMP** 프로토콜로 CPU/메모리/NTP/Uptime 등을 조회 |

결과는 화면 표로 출력됨과 동시에 `monitoring_history_YYYYMM.csv`와 MySQL `linux_server_status` 테이블에도 저장됩니다.

---

## 2. SERVER MONITORING DASHBOARD 컬럼 설명

```
| NO | HOSTNAME | CPU | MEM | SEC EVENT | NTP IP (TIME) | SERVICE | ACC STATUS | DISK(>80%) | NFS |
```

### NO
단순 순번(표 정렬 후 매겨짐). 서버 목록의 우선순위나 중요도와는 무관합니다.

### HOSTNAME
호스트명입니다. `vg1`/`vg2`/`ipcc_sw01`/`ipcc_sw02`는 **일반 리눅스 서버가 아니라 Cisco 네트워크 장비**(vg = 계열 장비, sw = 스위치)이며, SNMP로만 조회됩니다.

### CPU / MEM
- 최근 CPU 사용률(%) / 메모리 사용률(%)입니다.
- 임계치(기본 60%) 이상이면 **빨간색**, 미만이면 **초록색**.
- `N/A`(빨간색)로 표시되면 값을 못 가져온 것입니다. 특히 SNMP 대상(vg/ipcc) 장비는 SNMP 통신 실패 시 진짜 0%가 아니라 `N/A`로 뜨도록 되어 있습니다 — **0%와 N/A를 반드시 구분해서 보셔야 합니다.**

### SEC EVENT (보안 이벤트)
최근 1시간 내 `/var/log/secure`(또는 `auth.log`)의 `Failed password` 로그 건수를 기준으로 판정합니다.

| 표시 | 의미 |
|---|---|
| `Clean` (초록) | 이상 없음 |
| `LoginFail(N)` (빨강) | 최근 1시간 내 로그인 실패 1~9건 |
| `BruteForce(N)` (빨강) | 최근 1시간 내 로그인 실패 10건 이상 — 무차별 대입 공격 의심 |
| `-` | 해당 없음(SNMP 장비, ccnsearch 등 이 항목을 수집하지 않는 대상) |
| (스크립트 내부적으로 `NoLogPerm`) | 로그 파일 읽기 권한이 없어 점검 자체가 불가한 상태 — "이상 없음"이 아니라 "확인 못 함"이므로 주의 |

### NTP IP (TIME)
서버가 동기화하고 있는 NTP 서버 IP와, 그 정보를 조회한 시각입니다.

| 표시 | 의미 |
|---|---|
| `192.168.x.x (HH:MM:SS)` (초록) | 정상 동기화 중, 괄호 안은 조회 시각 |
| `NoSync` (빨강) | NTP 데몬은 떠 있지만 동기화가 안 된 상태 |
| `Down` (빨강) | NTP 데몬 자체가 죽어있음 |
| `NoData` (빨강, SNMP 대상 전용) | SNMP로 NTP 상태 값을 아예 못 받아옴 (장비가 살아있어도 이 OID만 실패할 수 있음) |
| `SnmpFail` (빨강, SNMP 대상 전용) | 장비와 SNMP 통신 자체가 안 됨 — CPU/MEM/SERVICE 등 이 행의 다른 값도 신뢰할 수 없음 |
| 시각 뒤 `*` 표시 | 장비 자체 시각이 아니라 xcat 서버의 로컬 시각으로 대체 표시된 것 (SNMP 대상 한정) |

### SERVICE
해당 서버에서 감시하도록 지정된 프로세스들의 상태입니다. (어떤 프로세스를 감시할지는 서버별로 미리 매핑되어 있습니다 — 예: 웹서버는 `httpd`, WAS는 `tomcat_*` 등)

| 표시 | 의미 |
|---|---|
| `Running` (초록) | 감시 대상 프로세스 전부 정상 |
| `프로세스명(Down)` (빨강) | 해당 프로세스가 아예 떠 있지 않음 |
| `프로세스명(Zombie:N)` (빨강) | 좀비 프로세스 N개 발견 |
| `프로세스명(Port:포트/Down)` (빨강) | 프로세스는 떠 있으나 지정된 포트가 응답 없음 |
| `프로세스명_conn_fail` / `_err(코드)` (빨강) | 80/8080/443 포트는 HTTP 응답 코드까지 확인 — 연결 실패 또는 5xx 에러 |
| `UPTIME:...` (초록/노랑) | SNMP 대상(vg/ipcc) 전용 표시. 장비 가동시간과 활성 포트 수 |
| `UPTIME:497+...` (**노랑**) | vg/ipcc 장비의 SNMP uptime 카운터가 100일 미만으로 잡혔을 때, 실제로는 훨씬 오래 켜져 있었을 가능성이 높아 "497일 이상"으로 보정 표기한 것 (장비 오류가 아니라 스크립트의 알려진 보정 로직) |
| `UPTIME:NoData` (빨강) | SNMP로 uptime 값 자체를 못 가져옴 |
| `SnmpFail:NoResponse` (빨강) | 장비와 통신 자체가 안 됨 |

### ACC STATUS (계정 상태)
지정된 점검 계정(대부분 root/ccnuser + 서버별 서비스 계정)의 비밀번호 만료 상태입니다.

| 표시 | 의미 |
|---|---|
| `Ok` (초록) | 만료 임박한 계정 없음 |
| `WARN(N)` (노랑) | N일 후 비밀번호 만료 예정 (기본 기준: 30일 이내) |
| `EXP(N)` (빨강) | 이미 만료됨 (N은 음수, 만료 후 경과일) |
| `MustChg` (빨강) | 다음 로그인 시 비밀번호를 강제로 바꿔야 하는 상태 |
| `SudoDenied` (빨강) | 점검용 sudo 권한이 없어 아예 확인이 불가한 상태 — "계정 정상"이 아니라 "점검 못 함" |
| `NoUser` (빨강) | 점검 대상 계정이 해당 서버에 존재하지 않음 |
| `NoChageCmd` (빨강) | `chage` 명령 자체가 서버에 없음 |
| `-` | 이 항목을 점검하지 않는 대상 |

### DISK(>80%)
사용률 80% 이상인 마운트만 표시됩니다.

| 표시 | 의미 |
|---|---|
| `OK` (초록) | 80% 넘는 마운트 없음 |
| `/경로(NN%)` (빨강) | 해당 경로가 80% 이상 사용 중 |
| `-` | 이 항목을 점검하지 않는 대상 |

### NFS
NFS 마운트 상태입니다.

| 표시 | 의미 |
|---|---|
| `OK` (초록) | NFS 마운트 정상 응답 |
| `Hang(TimeOut)` (빨강) | NFS가 마운트는 돼 있으나 응답 없이 멈춤(가장 위험한 신호 중 하나) |
| `InActive` (노랑) | NFS 마운트는 있는데 관련 데몬이 안 떠 있음 |
| `-` / `None` (노랑) | NFS를 사용하지 않는 서버 |

---

## 3. 색상 규칙 요약

| 색상 | 의미 |
|---|---|
| **초록** | 정상 |
| **노랑** | 주의가 필요하지만 즉시 장애는 아닌 상태 (임박한 만료, NFS 비활성 등) |
| **빨강** | 이상 발생 또는 "점검 자체가 실패해서 값을 신뢰할 수 없는 상태" — 두 경우가 같은 색으로 표시되므로, 빨간 항목은 실제 장애인지 점검 실패인지 값의 문구(NoData/SnmpFail/SudoDenied 등)로 구분해서 봐야 합니다.

---

## 4. 확인 우선순위 (운영 가이드 기준)

1. **CPU/MEM** 임계치 초과 여부
2. **SEC EVENT**가 `Clean`이 아닌 경우 (특히 `BruteForce`)
3. **NTP**가 `NoSync`/`Down`인 경우
4. **SERVICE**에 `Down`/`Zombie`가 있는 경우
5. **ACC STATUS**의 만료/에러
6. **DISK** 80% 초과
7. **NFS** 이상

정상 판단 기준: 위 항목이 전부 초록/`-`이고, SNMP 대상은 추가로 `SnmpFail`이 없어야 "정상"으로 간주합니다.

---

## 5. LICENSE STATUS SUMMARY 표

```
| HOSTNAME | LICENSE NAME | EXP.DATE | STATUS |
```

- **HOSTNAME**: 라이선스가 걸려있는 대상(장비/서비스명). 서버 호스트명이 아니라 `license_list.txt`에 등록된 분류명인 경우가 많습니다 (예: `WEB·WAS·WAF...`처럼 여러 대상 묶음으로 등록된 경우도 있음).
- **LICENSE NAME**: 라이선스/인증서 종류 (SSL Certificate, License 등)
- **EXP.DATE**: 만료일 (`YYYY-MM-DD`)
- **STATUS**:
  - `OK (D-N)`: 만료까지 N일 남음
  - `Expired (N days)`: 이미 만료됨 (N은 음수)
  - `Invalid Date (...)`: `license_list.txt`의 날짜 형식이 잘못 입력된 경우

---

## 6. 자주 헷갈리는 부분 정리

- **CPU/MEM `0%`와 `N/A`는 다릅니다.** `N/A`는 "0%로 측정됐다"가 아니라 "값을 못 가져왔다"는 뜻입니다.
- **`SEC EVENT`, `ACC STATUS`가 `-`인 건 "이상 없음"이 아니라 "이 서버는 이 항목을 점검 대상으로 관리하지 않는다"는 뜻**일 수 있습니다.
- **vg1/vg2/ipcc_sw01/ipcc_sw02는 리눅스 서버가 아니라 Cisco 네트워크 장비**이므로, SEC EVENT/ACC STATUS/DISK 같은 리눅스 전용 항목은 애초에 수집하지 않습니다(`-`로 고정 표시).
- **`UPTIME:497+`는 장비 이상이 아니라 스크립트의 알려진 보정 표기**입니다. SNMP의 uptime 카운터가 32비트 오버플로우 등으로 실제보다 짧게 잡힐 때가 있어, 100일 미만으로 조회되면 "497일 이상 가동"으로 보정해서 보여줍니다.
- **화면에는 안 나오지만** 실행 로그(`monitor_dashboard_run.log`)에 pdsh 실패, DB 접속 실패 등 스크립트 자체의 문제가 기록되니, 대시보드가 평소와 다르게 텅 비거나 이상하면 이 로그를 같이 확인하는 게 좋습니다.
