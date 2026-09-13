# SE_업무 Codex Local Project

이 프로젝트는 ChatGPT의 `SE_업무`에서 축적된 운영 맥락을 로컬 Codex 프로젝트로 옮겨 사용하기 위한 패키지다.

## 빠른 시작

1. ZIP을 원하는 로컬 경로에 압축 해제한다.
2. Codex에서 압축 해제한 `SE_업무_Codex_Project` 폴더를 연다.
3. 첫 요청은 다음처럼 시작하는 것을 권장한다.

```text
AGENTS.md와 docs/PROJECT_CONTEXT.md를 먼저 읽고 이 저장소의 SE 운영 환경을 파악해.
그 다음 현재 작업에 필요한 관련 문서와 스크립트만 추가로 확인해.
```

4. Git을 사용할 경우:

```bash
git init
git add .
git commit -m "Initial SE operations context"
```

## 디렉터리

```text
SE_업무_Codex_Project/
├── AGENTS.md
├── README.md
├── SECURITY_NOTES.md
├── SOURCE_MANIFEST.md
├── .gitignore
├── .env.example
├── docs/
├── runbooks/
├── scripts/
├── config/
├── reports/reference/
├── notes/
└── secrets/
```

## 중요한 보안 사항

업로드된 원본 스크립트 일부에는 실제 DB 비밀번호와 SNMP Community가 평문으로 포함되어 있었다.
이 패키지의 `scripts/`에는 해당 값들을 환경변수/자리표시자로 치환한 사본만 포함한다.
원본 비밀값은 ZIP에 포함하지 않았다.

실제 운영에 사용할 경우 `.env.example`을 참고하되, 실제 비밀값은 Git에 커밋하지 않는 별도 방식으로 주입한다.

## 이 패키지의 성격

- 운영 서버에 그대로 배포하는 설치 패키지가 아니다.
- Codex가 환경을 이해하고 분석/수정안을 제시하도록 하는 로컬 지식 저장소다.
- 실제 반영 전에는 운영 서버의 최신 파일과 반드시 비교한다.
