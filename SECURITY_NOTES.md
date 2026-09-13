# Security Notes

## 원본 파일에서 확인된 민감정보

업로드된 원본 스크립트 일부에는 다음 종류의 값이 평문으로 존재했다.

- MySQL 사용자/비밀번호
- SNMP Community
- 과거 운영 DB 접속 비밀번호

이 ZIP은 다른 계정 및 로컬 Codex에서 재사용하는 목적이므로 **실제 비밀값을 포함하지 않는다.**

## 패키징 시 처리

- `DB_PASS="..."` → `DB_PASS="${DB_PASS:-CHANGE_ME}"`
- VVB SNMP Community → `${VVB_SNMP_COMMUNITY:-CHANGE_ME}`
- 일반 SNMP Community → `${SNMP_COMMUNITY:-CHANGE_ME}`
- 과거 `mysql -p'평문비밀번호'` 형태 → `MYSQL_PWD="$LEGACY_DB_PASS" mysql ...`

## 주의

현재 `scripts/` 사본은 보안 이관용 사본이다. 실제 운영 서버와의 완전한 동작 동일성을 보장하지 않는다.
운영 반영 전 다음을 수행한다.

```bash
diff -u /운영/원본.sh scripts/대상.sh
bash -n scripts/대상.sh
```

특히 cron에서 실행할 경우 환경변수가 자동 로드되지 않을 수 있으므로, 실제 비밀 주입 방식은 운영 환경에 맞게 설계해야 한다.
