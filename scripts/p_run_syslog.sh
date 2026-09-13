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

    IFS='|' read -r S1 S2 S3 S4 S5 S6 S7 S8 S9 S10 S11 S12 <<< "$DATA"

    FULL_LOG=$(echo "$DATA" | sed "s/'/ /g")

    # 1. CPU & MEM (숫자만 추출)
    CPU_VAL=$(echo "$S1" | sed 's/.*is //; s/[^0-9.]//g')
    MEM_VAL=$(echo "$S2" | sed 's/.*is //; s/[^0-9.]//g')

    # 2. DISK (경로 및 퍼센트 파싱)
    if echo "$S3" | grep -q "warning!!!"; then
        D_PATH=$(echo "$S3" | awk -F'warning!!! ' '{print $2}' | awk -F' disk' '{print $1}' | xargs)
        D_PER=$(echo "$S3" | sed 's/.*is //' | xargs)
        DISK="${D_PATH}(${D_PER})"
    else
        DISK=$(echo "$S3" | sed -e 's/.*are //' -e 's/.*is //' | xargs)
    fi

    # 3. 기타 상태 지표들
    NFS=$(echo "$S4" | sed 's/.*is //' | xargs)
    NTP=$(echo "$S5" | sed 's/.*is //; s/.*server of .* is //' | xargs)
    SVC=$(echo "$S6" | sed -E 's/([^ ]+) service of [^ ]+ is (active|inactive|failed|dead|running|stopped)/\1[\2] /g' | xargs)
    #SVC=$(echo "$S6" | sed -E 's/([^ ]+) service of [^ ]+ is ([a-z]+)/\1[\2] /g' | xargs)
    ACC=$(echo "$S7" | sed 's/.*are //' | xargs)
    SEC=$(echo "$S8" | xargs)

    # 4. UPTIME 및 하단 지표 (순서 교정 핵심)
    UPT=$(echo "$S9" | xargs)

    # CPU_CORE 추출
    CPUCR=$(echo "$S10" | sed 's/[^0-9]//g' | xargs)

    # Load Average 추출
    LOAD=$(echo "$S11" | sed 's/[^0-9.]//g' | xargs)

    # Out of Memory 추출
    OOM=$(echo "$S12" | sed 's/[^0-9]//g' | xargs)

    # 5. 데이터 보정 (빈 값일 경우 기본값 설정)
    CPU_VAL=${CPU_VAL:-0.00}
    MEM_VAL=${MEM_VAL:-0.00}
    LOAD=${LOAD:-0.00}
    OOM=${OOM:-0}
    CPUCR=${CPUCR:-0}

    CLEAN_DISK=$(echo "$DISK" | sed "s/'/ /g")
    CLEAN_SVC=$(echo "$SVC" | sed "s/'/ /g")

    QUERY="CALL sp_insert_syslog_simple(
        '$HOST',
        '$CPU_VAL',
        '$MEM_VAL',
        '$CLEAN_DISK',
        '$CLEAN_SVC',
        '$NTP',
        '$UPT',
        '$ACC',
        '$NFS',
        '$CPUCR',
        '$LOAD',
        '$OOM',
        '$FULL_LOG'
    );"

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
    
    CCN_CPU=$(awk "BEGIN {printf \"%.1f\", 100 - $CCN_IDLE}")
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
    CCN_DISK=$(awk '$5 ~ /[0-9]%/ {gsub(/%/,"",$5); if($5 > 80) print $6"("$5"%)"}' "$CCN_DIR/ccnsearch_df.txt" | xargs | tr ' ' ',')
    [ -z "$CCN_DISK" ] && CCN_DISK="Normal"

    # 4) Service Status
    CCN_SVC="active"
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
    
    # 데이터 정제 및 변수 초기화
    CLEAN_CCN_DISK=$(echo "$CCN_DISK" | sed "s/'/ /g")
    CLEAN_CCN_SVC=$(echo "$CCN_SVC" | sed "s/'/ /g")
    CCN_LOAD=${CCN_LOAD:-"0.00"}
    CCN_OOM=${CCN_OOM:-0}

    # 프로시저 호출
    QUERY="CALL sp_insert_syslog_simple(
        '$CCN_HOST', '$CCN_CPU', '$CCN_MEM', '$CLEAN_CCN_DISK', '$CLEAN_CCN_SVC', 
        '$CCN_NTP', '$CCN_UPTIME', '$CCN_ACC', '$CCN_NFS','$CCN_CPUCR', '$CCN_LOAD', $CCN_OOM, ''
    );"

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
