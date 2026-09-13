# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash

# 로그가 쌓이는 기본 디렉토리
LOG_DIR="/home/ccnuser/log/xcat/disk_logs"

# 1. 지난달의 연도(YYYY)와 월(MM) 계산 (예: 2026-03)
PREV_YEAR=$(date -d "last month" +%Y)
PREV_MONTH=$(date -d "last month" +%m)

# 2. 연도별 디렉토리 생성 (예: /disk_logs/2026)
TARGET_DIR="${LOG_DIR}/${PREV_YEAR}"
mkdir -p "$TARGET_DIR"

cd "$LOG_DIR" || exit 1

# 3. 지난달 로그 파일들 찾기 (파일명에 2026-03 이 포함된 모든 .log)
FILES=$(ls *_${PREV_YEAR}-${PREV_MONTH}-*.log 2>/dev/null)

if [ -n "$FILES" ]; then
    echo "[$(date)] ${PREV_MONTH}월 로그 정리 시작..."
    
    # 4. 파일을 연도별 디렉토리로 이동
    mv *_${PREV_YEAR}-${PREV_MONTH}-*.log "$TARGET_DIR/"
    
    # 5. 이동한 디렉토리로 이동하여 압축
    cd "$TARGET_DIR"
    ARCHIVE_NAME="disk_logs_${PREV_YEAR}-${PREV_MONTH}.tar.gz"
    tar -czf "$ARCHIVE_NAME" *_${PREV_YEAR}-${PREV_MONTH}-*.log
    
    # 6. 압축 성공 시 원본 로그 삭제 (디렉토리 안에는 .tar.gz만 남음)
    if [ $? -eq 0 ]; then
        rm -f *_${PREV_YEAR}-${PREV_MONTH}-*.log
        echo "[$(date)] ${PREV_YEAR}/${PREV_MONTH}월 로그 정리 및 압축 완료."
    fi
else
    echo "[$(date)] 정리할 ${PREV_MONTH}월 로그 파일이 없습니다."
fi
