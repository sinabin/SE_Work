# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash

# 1. 경로 설정 (필요에 따라 절대경로로 수정하세요)
BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_DIR="/home/ccnuser/log/xcat/monitoring_history"       # CSV 파일이 있는 경로
REPORT_DIR="/home/ccnuser/log/xcat/monthly_report" # 결과 리포트가 저장될 경로

mkdir -p "$REPORT_DIR"

# 2. 현재 연월 가져오기 (예: 202512)
current_month=$(date +%Y%m)

# 3. 파일명 구성
INPUT_FILE="$LOG_DIR/monitoring_history_${current_month}.csv"
OUTPUT_FILE="$REPORT_DIR/avg_usage_${current_month}.csv"

# 4. 파일 존재 여부 확인 후 계산
if [ -f "$INPUT_FILE" ]; then
    awk -F',' '
    NR > 1 {
        sum_cpu[$2] += $3;
        sum_mem[$2] += $4;
        count[$2]++;
    }
    END {
        print "Hostname,CPU_Avg,MEM_Avg";
        for (host in count) {
            printf "%s,%.2f,%.2f\n", host, sum_cpu[host]/count[host], sum_mem[host]/count[host];
        }
    }' "$INPUT_FILE" > "$OUTPUT_FILE"
    echo "리포트 생성 완료: $OUTPUT_FILE"
else
    echo "오류: 파일을 찾을 수 없습니다 ($INPUT_FILE)"
fi
