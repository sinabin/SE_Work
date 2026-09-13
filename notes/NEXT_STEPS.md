# Recommended Next Steps

1. 운영 Xcat에서 최신 스크립트를 다시 수집하여 이 저장소 사본과 비교
2. Ansible 핵심 파일 추가
   - `/etc/ansible/hosts` (민감값 제거본)
   - `win_dailycheck.yml` (민감값 제거본)
   - `host_vars/*.yml` 구조
   - `dailycheck.py`
3. 실제 cron 현황을 텍스트로 export하여 `docs/`에 추가
4. Spring Boot dashboard 소스가 시작되면 `app/` 또는 `dashboard/` 디렉터리 생성
5. 백업 export TXT 샘플과 파서를 `backup/` 영역으로 추가
6. 운영 변경 이력을 `CHANGELOG.md` 또는 Git commit으로 관리
