# OZ Report License Change Runbook

과거 확인 기준 라이선스 경로:

```text
/usr/oz/oz70/WEB-INF/license/ozlicense.xml
```

기본 흐름:

```text
기존 라이선스 백업
→ 신규 ozlicense.xml 교체
→ 권한 확인
→ 대상 tomcat_call 인스턴스 순차 재시작
→ 프로세스/로그 확인
```

ccnwas1/2는 Active-Active 운영으로 인지된 이력이 있어 한 대씩 순차 작업하는 방식이 선호된다.
실제 L4/세션 구조는 작업 전에 재확인한다.
