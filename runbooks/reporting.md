# Reporting Runbook

보고서 생성 전 `docs/REPORT_STYLE_GUIDE.md`를 따른다.

운영 결과를 표로 만들 때 권장 컬럼:

```text
대상 | 점검항목 | 점검결과 | 조치내용 | 최종상태
```

취약점 조치 가능 여부:

```text
항목 | 대상 | 조치 가능 여부 | 조치 기준 | 불가/예외 사유 | 일정
```

문서에서 실제 서버 암호, DB 암호, Vault 암호, SNMP Community는 제거한다.
