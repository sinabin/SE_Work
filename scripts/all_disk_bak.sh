# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash

# =================================================================================
# [환경 설정 및 DB 정보]
# =================================================================================
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH

DB_HOST="localhost"
DB_USER="kwj"
DB_PASS="${DB_PASS:-CHANGE_ME}"
DB_NAME="monitoring_db"
DB_CONF="/tmp/.db_disk_access.cnf"

# MySQL 보안 경고 방지용 설정 파일 생성
echo -e "[client]\npassword='$DB_PASS'" > "$DB_CONF"
chmod 600 "$DB_CONF"

CONFIG_FILE="/home/ccnuser/sysmon/sbin/txt_file/alldisk_list.txt"
CCN_DF_FILE="/home/ccnuser/data/ccnsearch/ccnsearch_df.txt"

BASE_LOG_DIR="/home/ccnuser/log/xcat/disk_logs"
YEAR=$(date +%Y)
CURRENT_LOG_DIR="${BASE_LOG_DIR}/${YEAR}"

# 연도 디렉토리가 없으면 생성 (2027년이 되면 자동으로 2027 폴더 생성)
if [ ! -d "$CURRENT_LOG_DIR" ]; then
    mkdir -p "$CURRENT_LOG_DIR"
fi

# 로그 파일 경로 설정
LOG_FILE="${CURRENT_LOG_DIR}/weekly_disk_$(date +%Y-%m-%d).log"

# 이제 모든 echo 출력을 이 LOG_FILE로 보냅니다.

# 스크립트 종료 시 임시 파일 삭제
trap "rm -f $DB_CONF" EXIT

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: 설정 파일($CONFIG_FILE)이 없습니다."
    exit 1
fi

CUR_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# ---------------------------------------------------------------------------------
# 1. 정보 수집 및 병합 (PDSH + Local File)
# ---------------------------------------------------------------------------------
PDSH_OUTPUT=$(pdsh -g all "df -h" 2>/dev/null)
CCN_OUTPUT=""
if [ -f "$CCN_DF_FILE" ]; then
    CCN_OUTPUT=$(awk 'NR>1 {print "ccnsearch: " $0}' "$CCN_DF_FILE")
fi
ALL_DISK_INFO="${PDSH_OUTPUT}\n${CCN_OUTPUT}"

# ---------------------------------------------------------------------------------
# 2. 데이터 처리 및 DB 적재
# ---------------------------------------------------------------------------------
echo "디스크 정보를 수집하여 DB에 적재 중입니다..."

# 순서 보장을 위한 카운터 변수 초기화
seq_no=1

grep -vE '^\s*#|^\s*$' "$CONFIG_FILE" | while read -r LINE; do

    read -r -a ARR <<< "$LINE"
    HOST=${ARR[0]}

    for ((i=1; i<${#ARR[@]}; i++)); do
        TARGET_PATH=${ARR[i]}

        RESULT=$(echo -e "$ALL_DISK_INFO" | awk -v h="$HOST:" -v p="$TARGET_PATH" '
            function to_gb(raw_val) {
                val = raw_val + 0
                unit = toupper(substr(raw_val, length(raw_val)))
                if (unit == "T") return val * 1024
                if (unit == "G") return val
                if (unit == "M") return val / 1024
                if (unit == "K") return val / 1024 / 1024
                return val
            }
            $1 == h && ($NF == p || $6 == p || $7 == p) {
                size_gb  = to_gb($3)
                used_gb  = to_gb($4)
                avail_gb = to_gb($5)
                use_pct = $6
                printf "%.2f %.2f %.2f %s", size_gb, used_gb, avail_gb, use_pct
                exit
            }
        ')

        if [ -n "$RESULT" ]; then
            read SIZE_G USED_G AVAIL_G PERC <<< "$RESULT"

            # 만약 테이블에 sort_order 컬럼을 만들지 않으면, 이 순서대로 쌓이게 됨.
            QUERY="INSERT INTO disk_inventory (check_time, hostname, mount_point, total_gb, used_gb, avail_gb, use_percent, sort_order)
                   VALUES ('$CUR_TIME', '$HOST', '$TARGET_PATH', $SIZE_G, $USED_G, $AVAIL_G, '$PERC', $seq_no);"

            mysql --defaults-extra-file="$DB_CONF" -h"$DB_HOST" -u"$DB_USER" "$DB_NAME" -e "$QUERY"

            printf "[OK] %-15s | %-20s | %s (Seq: %d)\n" "$HOST" "$TARGET_PATH" "$PERC" "$seq_no"
            
            # 다음 항목을 위해 순서 번호 증가
            ((seq_no++))
        else
            printf "[FAIL] %-15s | %-20s | Not Found\n" "$HOST" "$TARGET_PATH"
        fi
    done
done

echo "모든 데이터가 설정 파일 순서대로 DB에 저장되었습니다."
