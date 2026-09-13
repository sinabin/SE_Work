# Linux / sysmon Dailycheck Runbook

## 실행

```bash
su - ccnuser
dailycheck
```

`dailycheck`는 `/home/ccnuser/sysmon/sbin/monitor_dashboard.sh`를 가리키는 운영 이력이 있다.

## 우선 확인

1. CPU / MEM 비정상
2. SEC EVENT가 `Clean`이 아닌 대상
3. NTP `NoSync` / `Down`
4. SERVICE `Down`, `Zombie`, 오류
5. ACC STATUS 만료/경고
6. DISK 80% 이상
7. NFS 이상
8. LICENSE 잔여일

## 관련 파일

- `scripts/monitor_dashboard.sh`
- `scripts/p_run_syslog.sh`
- `config/server_service_list.txt`
- `config/server_account_list.txt`
- `config/license_list.txt`
