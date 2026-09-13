# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash
# 파일명: run_syslog.sh

# =================================================================================
# 1. 환경 설정 및 로그/DB 정보
# =================================================================================
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH

DB_HOST="localhost"; DB_USER="kwj"; DB_PASS="${DB_PASS:-CHANGE_ME}"; DB_NAME="monitoring_db"
DB_CONF="/tmp/.db_access.cnf"

# 로그 저장 경로 설정
LOG_BASE_DIR="/home/ccnuser/log/xcat/sys_logs"
CURRENT_TIME=$(date +%Y-%m-%d_%H%M%S)
LOG_FILE="${LOG_BASE_DIR}/syslog_${CURRENT_TIME}.log"
TMP_RAW="/tmp/pdsh_raw_${CURRENT_TIME}.tmp"

mkdir -p "$LOG_BASE_DIR"
echo -e "[client]\npassword='$DB_PASS'" > "$DB_CONF"
chmod 600 "$DB_CONF"

trap "rm -f $DB_CONF $TMP_RAW" EXIT

# =================================================================================
# 2. 데이터 수집 (PDSH)
# =================================================================================
echo ">>> 전체 서버 데이터 수집 시작..."
pdsh -g all "/home/ccnuser/sysmon/bin/all.sh" 2>/dev/null > "$TMP_RAW"

# =================================================================================
# 3. 서버별 파싱, 로그 기록 및 DB 적재
# =================================================================================
while read -r LINE; do
    # 1. 호스트명과 데이터 분리
    HOST=$(echo "$LINE" | awk -F':' '{print $1}' | xargs)
    DATA=$(echo "$LINE" | cut -d':' -f2- | xargs)
    [ -z "$DATA" ] && continue

    # ---------------------------------------------------------
    # [복구된 부분] 로컬 서버에 텍스트 로그 기록
    # ---------------------------------------------------------
    echo "---------- [ SERVER: $HOST ] ----------" >> "$LOG_FILE"
    echo "Data: $DATA" >> "$LOG_FILE"
    echo "Time: $(date)" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    # ---------------------------------------------------------
    # [데이터 파싱] DB 적재용 필드 분리
    # ---------------------------------------------------------
    IFS='|' read -r S1 S2 S3 S4 S5 S6 S7 S8 S9 S10 S11 <<< "$DATA"

    # CPU & MEM (숫자만)
    CPU_VAL=$(echo "$S1" | sed 's/.*is //; s/[^0-9.]//g')
    MEM_VAL=$(echo "$S2" | sed 's/.*is //; s/[^0-9.]//g')

    # DISK (80% 이상 경로 포함 파싱)
#    DISK=$(echo "$S3" | sed -r "s/[A-Z][a-z]{2} [0-9 ]+ [0-9:]+ warning!!! //g" \
#                      | sed "s/ disk state of $HOST is /(/g" \
#                      | sed 's/%/%),/g' \
#                      | sed 's/,$//' | xargs)

    # 1. 먼저 양 끝의 파이프(|)와 불필요한 공백 제거
    S3_CLEAN=$(echo "$S3" | tr -d '|')

    # 2. 연쇄 sed 처리 (호스트명 부분에 정규식 사용 권장)
    DISK=$(echo "$S3_CLEAN" | sed -r "s/[A-Z][a-z]{2} [0-9 ]+ [0-9:]+ warning!!! //g" \
                            | sed -r "s/ disk state of [^ ]+ is /(/g" \
                            | sed 's/%/%),/g' \
                            | sed 's/,$//' | xargs)

    # 3. 결과 확인 (비어있으면 Normal)
    [ -z "$DISK" ] && DISK="Normal"

    # 데이터가 비어있거나 "OK"인 경우 Normal로 표시
    if [ -z "$DISK" ] || [ "$DISK" == "OK" ]; then
        DISK="Normal"
    fi    

    # 기타 상태 지표들
    NFS=$(echo "$S4" | sed 's/.*is //' | tr -d "'" | xargs)
    NTP=$(echo "$S5" | sed 's/.*is //; s/.*server of .* is //' | tr -d "'" | xargs)
    SVC=$(echo "$S6" | sed 's/.*is //' | tr -d "'" | xargs)
    ACC=$(echo "$S7" | sed 's/.*are //' | tr -d "'" | xargs)
    SEC=$(echo "$S8" | xargs)
    UPT=$(echo "$S9" | tr -d "'" | xargs)

    # Load Average 추출
    LOAD=$(echo "$S10" | sed 's/[^0-9.]//g' | xargs)

    # out of memory 
    OOM=$(echo "$S11" | sed 's/[^0-9]//g' | xargs)
    OOM=${OOM:-0}

    # 4. 데이터 보정 및 DB 실행
    CPU_VAL=${CPU_VAL:-0.00} 
    MEM_VAL=${MEM_VAL:-0.00} 
    LOAD=${LOAD:-0.00}
    CUR_SQL_TIME=$(date '+%Y-%m-%d %H:%M:%S')

    QUERY="INSERT INTO system_syslogs 
           (check_time, hostname, cpu_usage, mem_usage, disk_status, svc_status, ntp_info, uptime, acc_status, nfs_status, load_average, out_of_memory)
           VALUES 
           ('$CUR_SQL_TIME', '$HOST', $CPU_VAL, $MEM_VAL, '$DISK', '$SVC', '$NTP', '$UPT', '$ACC', '$NFS', '$LOAD', '$OOM');"

    mysql --defaults-extra-file="$DB_CONF" -h"$DB_HOST" -u"$DB_USER" "$DB_NAME" -e "$QUERY" 2>/dev/null

done < "$TMP_RAW"


# =================================================================================
# 4. 특수 서버 (ccnsearch) 로컬 파일 파싱 및 적재 (수정본)
# =================================================================================
CCN_DIR="/home/ccnuser/data/ccnsearch"
CCN_HOST="ccnsearch"

if [ -d "$CCN_DIR" ]; then
    echo ">>> $CCN_HOST 데이터 파싱 및 DB 적재 시작..."

    # 1) CPU & Uptime 파싱
    CCN_IDLE=$(grep "CPU states" "$CCN_DIR/ccnsearch_cpu.txt" | awk '{print $3}' | sed 's/%//')
    if [ -z "$CCN_IDLE" ]; then CCN_IDLE="100"; fi
    
    CCN_CPU=$(awk "BEGIN {printf \"%.2f\", 100 - $CCN_IDLE}")
    CCN_UPTIME=$(grep "up" "$CCN_DIR/ccnsearch_cpu.txt" | awk -F'up ' '{print $2}' | xargs)

    # 2) Memory 파싱 (솔라리스 top 기준 필드 위치 수정)
    CCN_PHYS=$(grep "Memory" "$CCN_DIR/ccnsearch_cpu.txt" | awk '{print $2}' | sed 's/[^0-9]//g')
    CCN_FREE=$(grep "Memory" "$CCN_DIR/ccnsearch_cpu.txt" | awk '{print $5}' | sed 's/[^0-9]//g')
    
    if [ -n "$CCN_PHYS" ] && [ -n "$CCN_FREE" ] && [ "$CCN_PHYS" -gt 0 ]; then
        CCN_MEM=$(awk "BEGIN {printf \"%.2f\", (($CCN_PHYS - $CCN_FREE) / $CCN_PHYS) * 100}")
    else
        CCN_MEM="0.00"
    fi

    # 3) Disk 파싱 (5번째 필드가 %인 솔라리스 df 대응)
    CCN_DISK=$(awk '$5 ~ /[0-9]%/ {
        gsub(/%/,"",$5); 
        if($5 >= 80) print $6"("$5"%)"
    }' "$CCN_DIR/ccnsearch_df.txt" | xargs | tr ' ' ',')
    
    [ -z "$CCN_DISK" ] && CCN_DISK="Normal"

#    CCN_DISK=$(awk '$5 ~ /[0-9]%/ {gsub(/%/,"",$5); if($5 > 80) print $6"("$5"%)"}' "$CCN_DIR/ccnsearch_df.txt" | xargs | tr ' ' ',')
#    [ -z "$CCN_DISK" ] && CCN_DISK="Normal"

    # 4) Service Status
    CCN_SVC="OK"
    for PROC in "isc" "cmanager" "java"; do
        if ! grep -q "$PROC" "$CCN_DIR/ccnsearch.txt"; then
            CCN_SVC="Warning($PROC Down)"
            break
        fi
    done

    # 5) 기타 정보
    CCN_NTP=$(grep "online" "$CCN_DIR/ccnsearch_ntps.txt" | awk '{print $1}' | xargs)
    [ -z "$CCN_NTP" ] && CCN_NTP="Offline"
    CCN_NFS="OK"
    CCN_ACC=$(grep "ccnuser" "$CCN_DIR/ccnsearch_ac.txt" | awk '{print $1}' | xargs)

    # 6) DB 적재
    CUR_SQL_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    
    QUERY="INSERT INTO system_syslogs
           (check_time, hostname, cpu_usage, mem_usage, disk_status, svc_status, ntp_info, uptime, acc_status, nfs_status)
           VALUES
           ('$CUR_SQL_TIME', '$CCN_HOST', $CCN_CPU, $CCN_MEM, '$CCN_DISK', '$CCN_SVC', '$CCN_NTP', '$CCN_UPTIME', '$CCN_ACC', '$CCN_NFS');"

    mysql --defaults-extra-file="$DB_CONF" -h"$DB_HOST" -u"$DB_USER" "$DB_NAME" -e "$QUERY"

    # 로그 기록
    echo "---------- [ SERVER: $CCN_HOST (Local File) ] ----------" >> "$LOG_FILE"
    echo "Data: CPU:$CCN_CPU%, MEM:$CCN_MEM%, DISK:$CCN_DISK, SVC:$CCN_SVC" >> "$LOG_FILE"
    echo "Time: $(date)" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
fi

# ---------------------------------------------------------
# 3. [기능 1] 3일 지난 로그 일별 압축 (Daily Archiving)
# ---------------------------------------------------------

cd "$LOG_BASE_DIR" || exit 1
for i in {3..7}; do
    TARGET_DATE=$(date -d "$i days ago" +%Y-%m-%d)
    DAILY_ARCHIVE="syslogs_${TARGET_DATE}.tar.gz"
    if [ -f "$DAILY_ARCHIVE" ]; then continue; fi
    TARGET_LOGS=$(ls syslog_${TARGET_DATE}_*.log 2>/dev/null)
    if [ -n "$TARGET_LOGS" ]; then
        tar -czf "$DAILY_ARCHIVE" $TARGET_LOGS 2>> "$LOG_FILE" && rm -f $TARGET_LOGS
    fi
done

LAST_MONTH=$(date -d "last month" +%Y-%m)
MONTHLY_DIR="${LOG_BASE_DIR}/${LAST_MONTH}"
MOVES_TARGET=$(ls syslogs_${LAST_MONTH}-*.tar.gz 2>/dev/null)
if [ -n "$MOVES_TARGET" ]; then
    if [ ! -d "$MONTHLY_DIR" ]; then mkdir -p "$MONTHLY_DIR"; fi
    mv $MOVES_TARGET "$MONTHLY_DIR/"
fi
echo ">>> 모든 작업 완료. 로그 파일: $LOG_FILE"
