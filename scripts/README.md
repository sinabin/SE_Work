# scripts/

이 디렉터리는 사용자가 업로드한 운영 스크립트의 **Codex 분석용 사본**이다.

보안상 실제 DB 비밀번호와 SNMP Community는 제거되어 있으며, 일부 파일은 환경변수를 요구한다.
실제 운영 반영 전에 운영 서버의 최신 원본과 diff를 비교한다.

권장 검사:

```bash
bash -n 대상.sh
git diff
```

주요 파일:

- `monitor_dashboard.sh`: Linux/장비 통합 모니터링 대시보드
- `p_run_syslog.sh`, `run_syslog.sh`: pdsh 결과 파싱/로그/DB 적재
- `all_disk.sh`, `main_disk.sh`: 디스크 수집
- `cleanup_logs.sh`, `cleanup_scouter.sh`: 보관/정리
- `vvb_status.sh`, `test_snmp.sh`: SNMP 점검
