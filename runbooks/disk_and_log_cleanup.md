# Disk / Log Cleanup Runbook

## 1. 우선 조회

```bash
df -h
du -xsh /* 2>/dev/null | sort -h
```

Xcat 일괄 확인은 `scripts/main_disk.sh`, `scripts/all_disk.sh`, `scripts/check_disk.sh`를 참고한다.

## 2. 로그 정리

관련 스크립트:

- `scripts/cleanup_logs.sh`
- `scripts/cleanup_scouter.sh`

삭제/압축 전 반드시 보존 주기와 현재 디스크 여유 공간을 확인한다.

## 3. WAS

과거 ccnwas1/2에서 catalina 로그가 대용량을 차지한 이력이 있다.
최근 운영 로그를 직접 확인한 뒤 기존 월별 압축 정책과 충돌하지 않게 정리한다.
