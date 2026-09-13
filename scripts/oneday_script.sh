# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash

# [환경 설정]
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_DIR="/home/ccnuser/log/xcat/monitoring_history"
RAW_DATA_FILE="$LOG_DIR/dashboard_temp_$(date +%s).raw"
DB_CONF="$LOG_DIR/.db_access.cnf"

DB_HOST="localhost"; DB_USER="kwj"; DB_PASS="${DB_PASS:-CHANGE_ME}"; DB_NAME="monitoring_db"

# 1. MySQL 보안 경고 방지를 위한 임시 설정 파일 생성
echo -e "[client]\npassword='$DB_PASS'" > "$DB_CONF"
chmod 600 "$DB_CONF"
trap "rm -f $RAW_DATA_FILE $DB_CONF" EXIT

# 2. 데이터 수집 템플릿 (UPTIME 포함 10개 필드)
REMOTE_CMD_TEMPLATE='
    UPTIME_VAL=$(uptime -p | sed "s/up //")
    CPU_USAGE=$(vmstat 1 2 | awk "NR==4 {print 100-\$15}")
    MEM_USAGE=$(awk "/MemTotal/ {t=\$2} /MemAvailable/ {a=\$2} END {if(a>0) printf \"%.0f\", ((t-a)/t)*100; else print 0}" /proc/meminfo)
    DISK_CHECK=$(df -hP | awk "0+\$5 >= 80 {p=\$6\"(\"\$5\") \"} END {if(p==\"\")print \"OK\"; else print p}")
    echo "$CPU_USAGE|$MEM_USAGE|$UPTIME_VAL|$DISK_CHECK|OK|NTP|OK|Ok|Clean"
'

# 3. 데이터 실행 및 정렬
{
    if command -v pdsh >/dev/null 2>&1; then pdsh -g all "$REMOTE_CMD_TEMPLATE" 2>/dev/null | sed 's/: /|/'; fi
} | sort > "$RAW_DATA_FILE"

# 4. DB 적재 (보안 경고 및 1366 에러 방지)
CUR_TIME=$(date '+%Y-%m-%d %H:%M:%S')
while IFS="|" read -r HOST CPU MEM UPTIME DISK NFS NTP SVC ACC SEC; do
    # 숫자 값 세척 (빈 값이면 0으로)
    CPU_VAL=$(echo "${CPU//[^0-9]/}"); CPU_VAL=${CPU_VAL:-0}
    MEM_VAL=$(echo "${MEM//[^0-9]/}"); MEM_VAL=${MEM_VAL:-0}

    QUERY="INSERT INTO server_status (check_time, hostname, cpu_usage, mem_usage, uptime, disk_info, nfs_status, ntp_info, service_status, acc_status, sec_event)
           VALUES ('$CUR_TIME', '$HOST', $CPU_VAL, $MEM_VAL, '$UPTIME', '$DISK', '$NFS', '$NTP', '$SVC', '$ACC', '$SEC');"
    
    # --defaults-extra-file 사용하여 보안 경고 제거
    mysql --defaults-extra-file="$DB_CONF" -h"$DB_HOST" -u"$DB_USER" "$DB_NAME" -e "$QUERY"
done < "$RAW_DATA_FILE"

echo "모니터링 완료 및 DB 적재 성공."
