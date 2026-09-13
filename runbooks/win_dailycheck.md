# Windows Ansible Dailycheck Runbook

## 실행

```bash
su - root
win_dailycheck
```

## 정상 기준

PLAY RECAP에서 각 대상이:

```text
unreachable=0
failed=0
```

DB에서는 최신 데이터의:

```text
process_status_summary=OK
process_details에 (Down) 없음
```

을 확인한다.

## 주의

후처리 표의 `Process Status=N/A`가 실제 프로세스 수집 실패를 의미하지 않을 수 있다.
상세 구조와 SQL은 `docs/XCAT_ANSIBLE_ARCHITECTURE.md` 참조.
