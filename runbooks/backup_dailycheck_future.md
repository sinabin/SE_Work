# Backup Dailycheck — Future Integration Notes

## 현재 목표

CCNNMS 등 백업 관리 화면에서 export한 일일 로그를 Xcat로 가져와 자동 파싱하고 다음 형태로 문서화하는 방향이 논의되었다.

```text
대상/정책 | 백업 시작시간 | 종료시간 | 결과 | 오류코드 | 비고
```

희망 산출물:

- HTML 일일점검표
- Excel 일일점검표
- 향후 Spring Boot dashboard 연계

현재 이 ZIP에는 실제 백업 로그 파서 원본이 포함되어 있지 않다.
백업 export TXT 샘플이 추가되면 파서 규칙을 이 runbook에 구체화한다.
