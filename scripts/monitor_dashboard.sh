# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash

# ==============================================================================
# 1. 환경 설정 및 변수 정의
# ==============================================================================
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TXT_DIR="$SCRIPT_DIR/txt_file"
LOG_DIR="/home/ccnuser/log/xcat/monitoring_history"

# 데이터 파일 경로
LICENSE_FILE="$TXT_DIR/license_list.txt"
ACCOUNT_FILE="$TXT_DIR/server_account_list.txt"
SERVICE_FILE="$TXT_DIR/server_service_list.txt"

# 로그 및 임시 파일 경로
HISTORY_CSV="$LOG_DIR/monitoring_history_$(date +%Y%m).csv"
RUN_LOG="$LOG_DIR/monitor_dashboard_run.log"

# MySQL 접속 정보
DB_HOST="localhost"
DB_USER="kwj"
DB_PASS="${DB_PASS:-CHANGE_ME}"
DB_NAME="monitoring_db"

# 모니터링 임계치 (Thresholds)
CPU_LIMIT=60
MEM_LIMIT=60
DISK_LIMIT=80
LICENSE_WARN_DAYS=30
PASS_WARN_DAYS=30

# 타임아웃 및 기본 사용자 설정
DEFAULT_CHECK_USER="ccnuser"
HTTP_TIMEOUT_SEC=3
NFS_TIMEOUT_SEC=3

# 초기화 작업
mkdir -p "$TXT_DIR" "$LOG_DIR"
if [ ! -f "$LICENSE_FILE" ]; then touch "$LICENSE_FILE"; fi

# --- [개선] 동시 실행 방지 (cron 실행이 겹치는 것을 막음) ---
LOCK_FILE="/tmp/monitor_dashboard.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 이미 실행 중인 인스턴스가 있어 종료합니다." >> "$RUN_LOG"
    exit 1
fi

# --- [개선] 임시 데이터 파일: mktemp으로 생성 (동시 실행 시 파일명 충돌 방지) ---
RAW_DATA_FILE=$(mktemp "$LOG_DIR/dashboard_temp_XXXXXX.raw")

# --- [개선] 스크립트 자체 실행 로그: 표준에러만 로그 파일에 누적 (화면 출력은 그대로 유지) ---
exec 2>>"$RUN_LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] monitor_dashboard.sh 실행 시작" >> "$RUN_LOG"

# 스크립트 종료 시 임시 파일 자동 삭제 (Trap)
trap 'rm -f "$RAW_DATA_FILE"; flock -u 200' EXIT

# --- [개선] SQL 값 이스케이프 함수 (작은따옴표 이스케이프로 쿼리 깨짐/인젝션 방지) ---
sql_escape() {
    printf '%s' "$1" | sed "s/'/''/g"
}

# --- [개선] MySQL 사전 접속 확인 (DB가 죽어있으면 매 호스트마다 에러가 쏟아지는 것을 방지) ---
DB_AVAILABLE=true
if ! MYSQL_PWD="$DB_PASS" mysqladmin -h"$DB_HOST" -u"$DB_USER" ping --connect-timeout=3 >/dev/null 2>>"$RUN_LOG"; then
    DB_AVAILABLE=false
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] MySQL 접속 실패 — 이번 실행은 화면 출력만 진행하고 DB 저장은 생략합니다." >> "$RUN_LOG"
fi


# ==============================================================================
# 2. 매핑 데이터 생성 (Pre-processing)
# ==============================================================================

# 2-1. 사용자 계정 매핑 생성
USER_MAPPING_CODE=""
if [ -f "$ACCOUNT_FILE" ]; then
    USER_MAPPING_CODE=$(awk '
        !/^#/ && NF>=2 {
            gsub(/\r/, "", $1); gsub(/\r/, "", $2);
            if ($1 in map) { map[$1] = map[$1] " " $2 } else { map[$1] = $2 }
        }
        END { for (h in map) { printf "*\"%s\"*) TARGET_USERS=\"%s\" ;;\n", h, map[h] } }
    ' "$ACCOUNT_FILE")
fi

# 2-2. 서비스 리스트 매핑 생성
SERVICE_MAPPING_CODE=""
if [ -f "$SERVICE_FILE" ]; then
    SERVICE_MAPPING_CODE=$(awk -F'|' '
        !/^#/ && NF>=2 {
            gsub(/\r/, "", $1); gsub(/\r/, "", $2);
            gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2);
            printf "*\"%s\"*) CHECK_LIST=\"%s\" ;;\n", $1, $2
        }
    ' "$SERVICE_FILE")
else
    SERVICE_MAPPING_CODE="*) CHECK_LIST=\"sshd crond\" ;;"
fi


# ==============================================================================
# 3. 원격 점검 스크립트 템플릿 (Remote Command)
# ==============================================================================
REMOTE_CMD_TEMPLATE='
    export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
    HOSTNAME=$(uname -n | tr -d " ")

    case "$HOSTNAME" in
        __SERVICE_MAPPING_BLOCK__
        *) CHECK_LIST="sshd crond" ;;
    esac

    SVC_FAIL_LIST=""
    SVC_STATUS="OK"

    for item in $CHECK_LIST; do
        SVC_NAME="${item%%:*}"
        SVC_PORT="${item##*:}"
        if [ "$SVC_NAME" == "$SVC_PORT" ]; then SVC_PORT=""; fi

        PROC_INFO=$(ps -ef | grep "$SVC_NAME" | grep -v grep | grep -v "CHECK_LIST" | grep -v "bash")

        if [ -z "$PROC_INFO" ]; then
            SVC_FAIL_LIST="$SVC_FAIL_LIST $SVC_NAME(Down)"
            SVC_STATUS="FAIL"
        else
            ZOMBIE_CNT=$(echo "$PROC_INFO" | grep "<defunct>" | wc -l)
            if [ "$ZOMBIE_CNT" -gt 0 ]; then
                SVC_FAIL_LIST="$SVC_FAIL_LIST $SVC_NAME(Zombie:$ZOMBIE_CNT)"
                SVC_STATUS="FAIL"
            fi

            if [ -n "$SVC_PORT" ] && [[ "$SVC_PORT" =~ ^[0-9]+$ ]]; then
                if (echo > /dev/tcp/localhost/$SVC_PORT) >/dev/null 2>&1; then
                    if [[ "$SVC_PORT" =~ ^(80|8080|443)$ ]]; then
                        if ! command -v curl >/dev/null 2>&1; then
                            SVC_FAIL_LIST="$SVC_FAIL_LIST ${SVC_NAME}(CurlMissing)"
                            SVC_STATUS="FAIL"
                        else
                            PROTOCOL="http"; [ "$SVC_PORT" == "443" ] && PROTOCOL="https"
                            HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout __HTTP_TIMEOUT__ "$PROTOCOL://localhost:$SVC_PORT" 2>/dev/null)

                            if [ "$HTTP_CODE" == "000" ] || [ -z "$HTTP_CODE" ]; then
                                SVC_FAIL_LIST="$SVC_FAIL_LIST ${SVC_NAME}_conn_fail"
                                SVC_STATUS="FAIL"
                            elif [[ "$HTTP_CODE" =~ ^5 ]]; then
                                SVC_FAIL_LIST="$SVC_FAIL_LIST ${SVC_NAME}_err($HTTP_CODE)"
                                SVC_STATUS="FAIL"
                            fi
                        fi
                    fi
                else
                    SVC_FAIL_LIST="$SVC_FAIL_LIST ${SVC_NAME}(Port:$SVC_PORT/Down)"
                    SVC_STATUS="FAIL"
                fi
            fi
        fi
    done

    if [ "$SVC_STATUS" == "FAIL" ]; then SVC_MSG=$(echo $SVC_FAIL_LIST | sed "s/^ //g"); else SVC_MSG="OK"; fi

     LOG_FILE="/var/log/secure"
     [ ! -f "$LOG_FILE" ] && LOG_FILE="/var/log/auth.log"
     SEC_MSG="Clean"
     if [ -r "$LOG_FILE" ]; then
         CUR_HOUR=$(date "+%b %e %H")
         FAIL_CNT=$(sudo -n grep "Failed password" "$LOG_FILE" 2>/dev/null | grep "$CUR_HOUR" | grep -v "grep" | wc -l)
         if [ "$FAIL_CNT" -ge 10 ]; then SEC_MSG="BruteForce(${FAIL_CNT})"
         elif [ "$FAIL_CNT" -ge 1 ]; then SEC_MSG="LoginFail(${FAIL_CNT})"
         fi
     else
         SEC_MSG="NoLogPerm"
     fi



    CPU_IDLE=$(vmstat 1 2 | awk "NR==2 {for(i=1;i<=NF;i++){if(\$i==\"id\"){c=i;break}}} NR==4 {print (c>0?\$c:\$15)}")
    [[ ! "$CPU_IDLE" =~ ^[0-9]+$ ]] && CPU_IDLE=100
    CPU_USAGE=$(( 100 - CPU_IDLE ))

    MEM_USAGE=$(awk "/MemTotal/ {t=\$2} /MemAvailable/ {a=\$2} /MemFree/ {f=\$2} /Buffers/ {b=\$2} /^Cached/ {c=\$2}
                     END {
                        if(a>0) used=t-a;
                        else { if(b==\"\")b=0; if(c==\"\")c=0; used=t-(f+b+c) }
                        if(t>0) printf \"%.0f\", (used/t)*100; else print 0
                     }" /proc/meminfo)

    # --- [개선] NTP: chronyc sources의 피어 검출뿐 아니라 tracking의 Leap status까지 확인
    #     (Leap status가 Normal이 아니면 피어가 잡혀도 실제로는 비정상 동기화 상태일 수 있음) ---
    NTP_PEER=""
    if command -v chronyc >/dev/null 2>&1; then
        PEER=$(chronyc -n sources | awk "\$1 ~ /\*/ {print \$2}")
        if [ -n "$PEER" ]; then
            LEAP=$(chronyc tracking 2>/dev/null | awk -F: "/Leap status/ {gsub(/^[ \t]+/,\"\",\$2); print \$2}")
            if [ -z "$LEAP" ] || [ "$LEAP" == "Normal" ]; then
                NTP_PEER="$PEER"
            else
                NTP_PEER="NoSync"
            fi
        fi
    fi

    if [ -z "$NTP_PEER" ] && command -v ntpq >/dev/null 2>&1; then
        PEER=$(ntpq -pn | awk "/^\*/ {print \$1}" | sed "s/^\*//")
        [ -n "$PEER" ] && NTP_PEER="$PEER"
    fi
    if [ -z "$NTP_PEER" ]; then
        if pgrep -f "ntpd" >/dev/null 2>&1 || pgrep -f "chronyd" >/dev/null 2>&1; then NTP_PEER="NoSync"
        else NTP_PEER="Down"; fi
    fi
    NTP_FINAL="$NTP_PEER ($(date "+%H:%M:%S"))"

    if awk '\''$3 == "nfs" || $3 == "nfs4" {found=1} END {exit !found}'\'' /proc/mounts; then
        timeout __NFS_TIMEOUT__ df -P -t nfs -t nfs4 >/dev/null 2>&1
        RET=$?
        if [ $RET -eq 0 ]; then NFS_RES="OK"
        elif [ $RET -eq 124 ]; then NFS_RES="Hang(TimeOut)"
        else
            if ! pgrep -x "nfsd" >/dev/null 2>&1 && ! pgrep -x "rpc.mountd" >/dev/null 2>&1; then NFS_RES="InActive"
            else NFS_RES="Error($RET)"; fi
        fi
    else NFS_RES="None"; fi
    

    DISK_CHECK=$(df -hP | awk -v limit=__DISK_LIMIT__ "0+\$5 >= limit {print \$6\"(\"\$5\")\"}")
    [ -z "$DISK_CHECK" ] && DISK_RES="OK" || DISK_RES="$DISK_CHECK"

    TARGET_USERS="__DEFAULT_CHECK_USER__"
    case "$HOSTNAME" in __USER_MAPPING_BLOCK__ esac
    FINAL_ACC_MSG=""
    for u in $TARGET_USERS; do
        # --- [개선] chage 명령 자체가 없는 경우와 sudo 거부, 대상 계정 없음을 구분해서 표시
        #     (기존에는 전부 뭉뚱그려 ChkErr로만 표시되어 원인 파악이 어려웠음) ---
        if ! command -v chage >/dev/null 2>&1; then
            FINAL_ACC_MSG="${FINAL_ACC_MSG} $u:NoChageCmd"
            continue
        fi
        CHAGE_RAW=$(sudo -n LC_ALL=C chage -l "$u" 2>&1)
        if echo "$CHAGE_RAW" | grep -qi "no such user\|does not exist"; then
            FINAL_ACC_MSG="${FINAL_ACC_MSG} $u:NoUser"
            continue
        fi
        if echo "$CHAGE_RAW" | grep -qi "^sudo:"; then
            FINAL_ACC_MSG="${FINAL_ACC_MSG} $u:SudoDenied"
            continue
        fi
        CHAGE_INFO="$CHAGE_RAW"
        if [ -z "$CHAGE_INFO" ]; then FINAL_ACC_MSG="${FINAL_ACC_MSG} $u:ChkErr"; continue; fi
        EXP_STR=$(echo "$CHAGE_INFO" | grep "Password expires" | cut -d: -f2 | sed "s/^ //g")
        LAST_CHG=$(echo "$CHAGE_INFO" | grep "Last password change" | cut -d: -f2 | sed "s/^ //g")
        if [[ "$LAST_CHG" == *"must be changed"* ]] || [[ "$EXP_STR" == *"must be changed"* ]]; then
            FINAL_ACC_MSG="${FINAL_ACC_MSG} $u:MustChg"
        elif [ "$EXP_STR" != "never" ]; then
            EXP_SEC=$(date -d "$EXP_STR" +%s 2>/dev/null)
            NOW_SEC=$(date +%s)
            if [ -n "$EXP_SEC" ]; then
                DIFF_DAYS=$(( ($EXP_SEC - $NOW_SEC) / 86400 ))
                if [ $DIFF_DAYS -lt 0 ]; then FINAL_ACC_MSG="${FINAL_ACC_MSG} $u:EXP($DIFF_DAYS)"
                elif [ $DIFF_DAYS -le __PASS_WARN_DAYS__ ]; then FINAL_ACC_MSG="${FINAL_ACC_MSG} $u:WARN($DIFF_DAYS)"
                fi
            else FINAL_ACC_MSG="${FINAL_ACC_MSG} $u:DateErr"; fi
        fi
    done
    if [ -z "$FINAL_ACC_MSG" ]; then ACC_RES="Ok"; else ACC_RES=$(echo $FINAL_ACC_MSG | sed "s/^ //g"); fi

    # --- [개선] Uptime: uptime -p(표준 pretty 포맷)를 우선 사용하고, 실패 시에만 기존 파싱 방식으로 폴백
    #     (기존의 cut -d'p' 방식은 로케일/호스트명에 'p'가 포함된 경우 등 예외 케이스에 취약) ---
    UPT_VAL=$(uptime -p 2>/dev/null | sed "s/^up //")
    if [ -z "$UPT_VAL" ]; then
        UPT_RAW=$(uptime)
        UPT_VAL=$(echo $UPT_RAW | cut -d'p' -f2- | cut -d',' -f1,2)
    fi
    [ -z "$UPT_VAL" ] && UPT_VAL="Unknown"

    # DISK_CHECK가 여러 줄일 경우 한 줄로 병합 (예: /data1(85%) /data2(90%))
    DISK_RES=$(echo $DISK_CHECK | xargs) 
    [ -z "$DISK_RES" ] && DISK_RES="OK"

    # SVC_MSG, ACC_RES 등도 혹시 모를 줄바꿈 제거
    SVC_MSG=$(echo "$SVC_MSG" | xargs)
    ACC_RES=$(echo "$ACC_RES" | xargs)
    
    # 최종 출력 시 파이프(|)로 연결된 한 줄만 생성
    echo "$CPU_USAGE|$MEM_USAGE|$DISK_RES|$NFS_RES|$NTP_FINAL|$SVC_MSG|$ACC_RES|$SEC_MSG|$UPT_VAL"
'

REMOTE_CMD="${REMOTE_CMD_TEMPLATE/__USER_MAPPING_BLOCK__/$USER_MAPPING_CODE}"
REMOTE_CMD="${REMOTE_CMD/__SERVICE_MAPPING_BLOCK__/$SERVICE_MAPPING_CODE}"
REMOTE_CMD="${REMOTE_CMD/__HTTP_TIMEOUT__/$HTTP_TIMEOUT_SEC}"
REMOTE_CMD="${REMOTE_CMD/__NFS_TIMEOUT__/$NFS_TIMEOUT_SEC}"
REMOTE_CMD="${REMOTE_CMD/__DISK_LIMIT__/$DISK_LIMIT}"
REMOTE_CMD="${REMOTE_CMD/__DEFAULT_CHECK_USER__/$DEFAULT_CHECK_USER}"
REMOTE_CMD="${REMOTE_CMD/__PASS_WARN_DAYS__/$PASS_WARN_DAYS}"


# ==============================================================================
# 4. 메인 실행 및 데이터 수집
# ==============================================================================
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH

{
    # --- [개선] pdsh 실행 결과가 비어있을 때(설정 오류 등) 원인 파악용 로그 남김 ---
    if command -v pdsh >/dev/null 2>&1; then
        PDSH_OUT=$(pdsh -g all "$REMOTE_CMD" 2>>"$RUN_LOG")
        if [ -z "$PDSH_OUT" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] pdsh 결과가 비어 있습니다 (pdsh 설정/그룹(all) 확인 필요)" >> "$RUN_LOG"
        fi
        echo "$PDSH_OUT" | sed 's/: /|/'
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] pdsh 명령을 찾을 수 없습니다" >> "$RUN_LOG"
    fi

    CCN_DIR="/home/ccnuser/data/ccnsearch"
    if [ -d "$CCN_DIR" ]; then
        CPU_USAGE=$(awk '/CPU states:/ {for(i=1;i<=NF;i++){if($i=="idle,")val=$(i-1)} sub("%","",val); printf "%.0f", 100-val}' "$CCN_DIR/ccnsearch_cpu.txt" 2>/dev/null)
        [ -z "$CPU_USAGE" ] && CPU_USAGE=0
        MEM_USAGE=$(awk '/Memory:/ && /phys mem/ {t=$2;f=$5; sub("M","",t);sub("M","",f); if(t>0) printf "%.0f",((t-f)/t)*100}' "$CCN_DIR/ccnsearch_cpu.txt" 2>/dev/null)
        [ -z "$MEM_USAGE" ] && MEM_USAGE=0
        DISK_RES=$(awk -v limit="$DISK_LIMIT" 'NR>1 {for(i=1;i<=NF;i++){if($i~/%/){s=$i;gsub(/[^0-9]/,"",s);if(s+0>=limit)print $(NF)"("$i") "}}}' "$CCN_DIR/ccnsearch_df.txt" 2>/dev/null)
        [ -z "$DISK_RES" ] && DISK_RES="OK"
        NTP_PEER=$(awk '$1 ~ /^[*o]/ {print $1}' "$CCN_DIR/ccnsearch_ntpp.txt" 2>/dev/null | tr -d '*o' | head -n 1)
        [ -z "$NTP_PEER" ] && NTP_PEER="NoSync"
        LOG_TIME=$(head -n 1 "$CCN_DIR/ccnsearch.txt" 2>/dev/null | cut -d_ -f2)
        [ -z "$LOG_TIME" ] && LOG_TIME="00:00"
        NTP_FINAL="$NTP_PEER ($LOG_TIME)"
        SVC_FAIL=""
        for proc in named isc cmanager java; do
            PROC_LINES=$(grep "$proc" "$CCN_DIR/ccnsearch.txt" 2>/dev/null | grep -v grep)
            if [ -z "$PROC_LINES" ]; then SVC_FAIL="$SVC_FAIL $proc(Down)"
            else
                ZOMBIE_CNT=$(echo "$PROC_LINES" | grep "defunct" | wc -l)
                if [ "$ZOMBIE_CNT" -gt 0 ]; then SVC_FAIL="$SVC_FAIL $proc(Zombie:$ZOMBIE_CNT)"; fi
            fi
        done
        [ -z "$SVC_FAIL" ] && SVC_MSG="OK" || SVC_MSG="Fail:$SVC_FAIL"
        read ACC_STAT ACC_DATE ACC_MAX <<< $(awk '/ccnuser/ {print $2, $3, $5}' "$CCN_DIR/ccnsearch_ac.txt" 2>/dev/null)
        ACC_RES="Ok"
        if [ -n "$ACC_STAT" ]; then
            if [ "$ACC_STAT" != "PS" ] && [ "$ACC_STAT" != "NP" ]; then ACC_RES="Warn($ACC_STAT)"
            elif [ -n "$ACC_DATE" ] && [ -n "$ACC_MAX" ]; then
                NOW_SEC=$(date +%s); LAST_SEC=$(date -d "$ACC_DATE" +%s 2>/dev/null)
                if [ -n "$LAST_SEC" ]; then
                    DIFF_DAYS=$(( (NOW_SEC - LAST_SEC) / 86400 ));
                    if [ "$DIFF_DAYS" -gt "$ACC_MAX" ]; then OVER=$((DIFF_DAYS - ACC_MAX)); ACC_RES="Exp(+$OVER)"
                    elif [ "$DIFF_DAYS" -ge $((ACC_MAX - PASS_WARN_DAYS)) ]; then REMAIN=$((ACC_MAX - DIFF_DAYS)); ACC_RES="Warn(D-$REMAIN)"
                    fi
                fi
            fi
        else ACC_RES="ChkErr"; fi
        echo "ccnsearch|$CPU_USAGE|$MEM_USAGE|$DISK_RES|$NFS_RES|$NTP_FINAL|$SVC_MSG|$ACC_RES|-|Unknown"
    fi

    # ==========================================================================
    # Cisco(SNMP) 대상 — vg1/vg2/ipcc_sw01/ipcc_sw02
    # SNMP 방어로직: 1) 도달성 선체크  2) 필드별 실패값 방어  3) 화면 색상 반영(6번 섹션 awk)
    # ==========================================================================
    CISCO_TARGETS="1.vg1 2.vg2 3.ipcc_sw01 4.ipcc_sw02"
    SNMP_COMM="${SNMP_COMMUNITY:-CHANGE_ME}"
    SNMP_OPTS="-t 1 -r 1 -v2c -c $SNMP_COMM -Oqv"
    for cisco in $CISCO_TARGETS; do
        cisco=$(echo "$cisco" | tr -d '[:space:]')
        if ! command -v snmpget >/dev/null 2>&1; then echo "$cisco|0|0|-|-|ToolMissing|Check|-|-|-"; continue; fi

        case "$cisco" in
            "1.vg1"|"2.vg2") TARGET_NTP="192.168.3.110" ;;
            "3.ipcc_sw01"|"4.ipcc_sw02") TARGET_NTP="192.168.3.66" ;;
            *) TARGET_NTP="Unknown" ;;
        esac

        # --- SNMP 도달성 선체크: 표준 sysUpTime OID로 한 번 찔러본다 (아래 uptime 계산에도 재사용) ---
        PROBE=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.2.1.1.3.0 2>/dev/null)
        if [ -z "$PROBE" ] || [[ "$PROBE" == *"Timeout"* ]] || [[ "$PROBE" == *"No Response"* ]] || [[ "$PROBE" == *"No Such"* ]]; then
            echo "$cisco|0|0|-|None|SnmpFail ($(date "+%H:%M:%S"))|SnmpFail:NoResponse|-|-|-"
            continue
        fi
        UPTIME_RAW="$PROBE"

        # CPU
        CISCO_CPU=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.4.1.9.9.109.1.1.1.1.5.1 2>/dev/null)
        if ! [[ "$CISCO_CPU" =~ ^[0-9]+$ ]]; then CISCO_CPU=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.4.1.9.2.1.58.0 2>/dev/null); fi
        if [[ "$CISCO_CPU" =~ ^[0-9]+$ ]]; then
            [ "$CISCO_CPU" -gt 100 ] && CISCO_CPU=100
        else
            CISCO_CPU=-1
        fi

        # 메모리
        MEM_USED=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.4.1.9.9.48.1.1.1.5.1 2>/dev/null)
        MEM_FREE=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.4.1.9.9.48.1.1.1.6.1 2>/dev/null)
        if [[ "$MEM_USED" =~ ^[0-9]+$ ]] && [[ "$MEM_FREE" =~ ^[0-9]+$ ]] && [ $((MEM_USED + MEM_FREE)) -gt 0 ]; then
            CISCO_MEM=$(awk -v u="$MEM_USED" -v f="$MEM_FREE" 'BEGIN { printf "%.0f", (u/(u+f))*100 }')
        else
            CISCO_MEM=-1
        fi

        # 장비 시각 (실패 시 xcat 로컬 시각으로 대체하되 * 표시로 출처 구분)
        RAW_TIME=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.2.1.25.1.2.0 2>/dev/null)
        if [[ "$RAW_TIME" == *"No Such"* ]] || [[ -z "$RAW_TIME" ]]; then
            TIME_ONLY="$(date "+%H:%M:%S")*"
        else
            TIME_ONLY=$(echo "$RAW_TIME" | awk -F, '{print $2}' | cut -d. -f1)
        fi

        # NTP 동기화 상태 (SYNC_STATE 비어있음=NoData, 3/alarm=NoSync로 명확히 구분)
        SYNC_STATE=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.4.1.9.9.168.1.1.1.0 2>/dev/null)
        if [ -z "$SYNC_STATE" ] || [[ "$SYNC_STATE" == *"No Such"* ]]; then
            CISCO_NTP="NoData ($TIME_ONLY)"
        elif [[ "$SYNC_STATE" == "3" ]] || [[ "$SYNC_STATE" == *"alarm"* ]]; then
            CISCO_NTP="NoSync ($TIME_ONLY)"
        else
            CISCO_NTP="$TARGET_NTP ($TIME_ONLY)"
        fi

        # Uptime
        UPTIME_CLEAN=$(echo "$UPTIME_RAW" | sed 's/Timeticks:.*) //' | sed 's/^ //')
        PRETTY_TIME=$(echo "$UPTIME_CLEAN" | sed 's/ days, /:/g' | sed 's/ day, /:/g')
        if [[ "$UPTIME_CLEAN" == *"days"* ]]; then DAY_ONLY=$(echo "$UPTIME_CLEAN" | awk -F' days' '{print $1}' | awk '{print $NF}'); else DAY_ONLY=0; fi
        NEED_FIX=true   # vg1/vg2/ipcc_sw01/ipcc_sw02 전부 100일 미만 시 497+ 보정 대상
        if [ -z "$UPTIME_CLEAN" ] || [[ "$UPTIME_RAW" == *"No Such"* ]]; then
            UPTIME_FMT="UPTIME:NoData"
        elif [[ "$DAY_ONLY" =~ ^[0-9]+$ ]]; then
            if [ "$NEED_FIX" = true ] && [ "$DAY_ONLY" -lt 100 ]; then UPTIME_FMT="UPTIME:497+${PRETTY_TIME}"; else UPTIME_FMT="UPTIME:${PRETTY_TIME}"; fi
        else
            UPTIME_FMT="Down"
        fi

        # 포트 up 개수
        PORT_UP_CNT=$(snmpwalk $SNMP_OPTS "$cisco" .1.3.6.1.2.1.2.2.1.8 2>/dev/null | grep -cE "^1$|^up$")

        echo "$cisco|$CISCO_CPU|$CISCO_MEM|-|None|$CISCO_NTP|$UPTIME_FMT, Port:$PORT_UP_CNT|-|-|-"
    done
} | sort > "$RAW_DATA_FILE"


# ==============================================================================
# 5. 데이터 저장 (CSV & MySQL - 서버 상태)
# ==============================================================================
CUR_TIME=$(date '+%Y-%m-%d %H:%M:%S')

if [ ! -f "$HISTORY_CSV" ]; then
    echo "Time,Hostname,CPU,MEM,DISK,NFS,NTP,Service,Account,Security,Uptime" > "$HISTORY_CSV"
fi

while IFS="|" read -r HOST CPU MEM DISK NFS NTP SVC ACC SEC UPT; do
    [ -z "$HOST" ] && continue

    echo "$CUR_TIME,$HOST,$CPU,$MEM,\"$DISK\",$NFS,\"$NTP\",\"$SVC\",\"$ACC\",$SEC,\"$UPT\"" >> "$HISTORY_CSV"

    # --- [개선] DB가 접속 불가 상태면 INSERT 자체를 건너뛰어 에러 스팸 방지 ---
    [ "$DB_AVAILABLE" = false ] && continue

    CPU_VAL=$(echo "$CPU" | tr -d '%')
    MEM_VAL=$(echo "$MEM" | tr -d '%')

    DISK_ESC=$(sql_escape "$(echo "$DISK" | tr -d '\r\n')")
    SVC_ESC=$(sql_escape "$(echo "$SVC" | tr -d '\r\n')")
    NTP_ESC=$(sql_escape "$(echo "$NTP" | tr -d '\r\n')")
    UPT_ESC=$(sql_escape "$(echo "$UPT" | tr -d '\r\n')")
    HOST_ESC=$(sql_escape "$HOST")
    ACC_ESC=$(sql_escape "$ACC")
    SEC_ESC=$(sql_escape "$SEC")

    QUERY="INSERT INTO linux_server_status 
           (check_time, hostname, cpu_usage, mem_usage, disk_warning, nfs_status, ntp_info, service_info, acc_status, sec_event, uptime)
           VALUES 
           ('$CUR_TIME', '$HOST_ESC', '$CPU_VAL', '$MEM_VAL', '$DISK_ESC', '$NFS', '$NTP_ESC', '$SVC_ESC', '$ACC_ESC', '$SEC_ESC', '$UPT_ESC');"

    # --- [개선] 에러는 화면이 아닌 실행 로그로만 기록 ---
    MYSQL_PWD="$DB_PASS" mysql -h"$DB_HOST" -u"$DB_USER" "$DB_NAME" -e "$QUERY" 2>>"$RUN_LOG"

done < "$RAW_DATA_FILE"


# ==============================================================================
# 6. 결과 화면 출력
# ==============================================================================
echo ""; echo "========================================================================================================================================================================================="
echo "                                                                        SERVER MONITORING DASHBOARD"
echo "                                                                         Time: $CUR_TIME"
echo "========================================================================================================================================================================================="
printf "| %-2s | %-18s | %-6s | %-6s | %-12s | %-28s | %-40s | %-16s | %-18s | %-8s |\n" "NO" "HOSTNAME" "CPU" "MEM" "SEC EVENT" "NTP IP (TIME)" "SERVICE" "ACC STATUS" "DISK(>80%)" "NFS"
echo "========================================================================================================================================================================================="

awk -F "|" -v cpu_lim="$CPU_LIMIT" -v mem_lim="$MEM_LIMIT" '
BEGIN { RED="\033[1;31m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RESET="\033[0m"; count=0 }
function print_cell(t,c,w) { l=length(t); p=w-l; if(p<0)p=0; printf "%s%s%s%*s",c,t,RESET,p,"" }
{
    count++;
    h=$1; cpu=$2+0; mem=$3+0; disk=$4; nfs=$5; ntp=$6; svc=$7; acc=$8; sec=$9; upt=$10;

    # --- [개선] HOSTNAME도 다른 컬럼처럼 길면 잘라서 표가 깨지지 않도록 처리 ---
    if(length(h)>18) h=substr(h,1,16)".."
    printf "| %-2d | %-18s | ", count, h

    if (cpu < 0) print_cell("N/A", RED, 6); else if (cpu >= cpu_lim) print_cell(cpu"%", RED, 6); else print_cell(cpu"%", GREEN, 6); printf " | "
    if (mem < 0) print_cell("N/A", RED, 6); else if (mem >= mem_lim) print_cell(mem"%", RED, 6); else print_cell(mem"%", GREEN, 6); printf " | "
    if(index(sec,"Brute")>0 || index(sec,"Fail")>0) print_cell(sec,RED,12); else if(sec=="Clean") print_cell("Clean",GREEN,12); else print_cell("-",GREEN,12); printf " | "
    if(length(ntp)>28) ntp=substr(ntp,1,26)"..";
    if(index(ntp,"Down")>0 || index(ntp,"NoSync")>0 || index(ntp,"NoData")>0 || index(ntp,"SnmpFail")>0) print_cell(ntp,RED,28); else print_cell(ntp,GREEN,28); printf " | "
    if(index(svc,"Zombie")>0 || index(svc,"Fail")>0 || index(svc,"Down")>0 || index(svc,"err")>0 || index(svc,"Missing")>0 || index(svc,"NoData")>0) {
        if(length(svc)>40) svc=substr(svc,1,40); print_cell(svc,RED,40);
    } else if(index(svc,"UPTIME")>0) {
        if(index(svc,"497+")>0) print_cell(svc,YELLOW,40); else print_cell(svc,GREEN,40);
    } else { print_cell("Running",GREEN,40); } printf " | "
    if(index(acc,"EXP")>0 || index(acc,"Must")>0 || index(acc,"SudoDenied")>0 || index(acc,"NoUser")>0 || index(acc,"NoChageCmd")>0) print_cell(acc,RED,16); else if(acc=="Ok") print_cell(acc,GREEN,16); else if(acc=="-"||acc=="") print_cell("-",GREEN,16); else print_cell(acc,YELLOW,16); printf " | "
    if(disk=="OK") print_cell("OK",GREEN,18); else if(disk=="-"||disk=="") print_cell("-",GREEN,18); else { if(length(disk)>18) disk=substr(disk,1,18); print_cell(disk,RED,18) } printf " | "
    if(nfs=="OK") print_cell("OK",GREEN,8); else if(index(nfs,"InActive")>0) print_cell("InActive",YELLOW,8); else if(nfs=="None"||nfs=="-"||nfs=="") print_cell("-",YELLOW,8); else print_cell(nfs,RED,8);
    printf " |\n"
}' "$RAW_DATA_FILE"

echo "========================================================================================================================================================================================="
echo ""
# ==============================================================================
# 7. 라이선스 상태 요약 및 DB 저장 
# ==============================================================================
echo "========================================================================================================================================================================================="
echo "                                                                          [LICENSE STATUS SUMMARY]"
echo "========================================================================================================================================================================================="
printf "| %-48s | %-48s | %-20s | %-56s |\n" "HOSTNAME" "LICENSE NAME" "EXP.DATE" "STATUS"
echo "========================================================================================================================================================================================="

while IFS="|" read -r L_HOST L_YY L_MM L_DD L_NAME || [ -n "$L_HOST" ]; do
    [[ "$L_HOST" =~ ^# ]] || [ -z "$L_HOST" ] && continue 

    # 1. 공백 제거 (Trim)
    L_HOST=$(echo "$L_HOST" | xargs)
    L_YY=$(echo "$L_YY" | xargs)
    L_MM=$(echo "$L_MM" | xargs)
    L_DD=$(echo "$L_DD" | xargs)
    L_NAME=$(echo "$L_NAME" | xargs)

    # 2. 날짜 문자열 생성 (연도는 2자리만 관리되므로 "20"을 고정 접두어로 사용 — 2000~2099년만 지원)
    F_YY=$(printf "%02s" "$L_YY" | tr ' ' '0')
    F_MM=$(printf "%02s" "$L_MM" | tr ' ' '0')
    F_DD=$(printf "%02s" "$L_DD" | tr ' ' '0')
    
    FULL_DATE="20${F_YY}-${F_MM}-${F_DD}"
    
    # 3. 날짜 유효성 체크 및 계산
    if ! date -d "$FULL_DATE" >/dev/null 2>&1; then
        STATUS_MSG="Invalid Date ($FULL_DATE)"
    else
        EXP_SEC=$(date -d "$FULL_DATE" +%s)
        NOW_SEC=$(date -d "today 00:00:00" +%s) # 오늘 0시 기준
        DAYS_DIFF=$(( (EXP_SEC - NOW_SEC) / 86400 ))
        
        if [ $DAYS_DIFF -lt 0 ]; then
            STATUS_MSG="Expired ($DAYS_DIFF days)"
        else
            STATUS_MSG="OK (D-$DAYS_DIFF)"
        fi
    fi

    # 4. 화면 출력
    printf "| %-48s | %-48s | %-20s | %-56s |\n" "$L_HOST" "$L_NAME" "$FULL_DATE" "$STATUS_MSG"

    # 5. MySQL 저장 (DB 접속 불가 시 건너뜀, 값은 이스케이프 처리)
    if [ "$DB_AVAILABLE" = true ]; then
        L_HOST_ESC=$(sql_escape "$L_HOST")
        L_NAME_ESC=$(sql_escape "$L_NAME")
        STATUS_MSG_ESC=$(sql_escape "$STATUS_MSG")

        L_QUERY="INSERT INTO license_status (target_group, expiry_date, license_name, status_summary, updated_at)
                 VALUES ('$L_HOST_ESC', '$FULL_DATE', '$L_NAME_ESC', '$STATUS_MSG_ESC', '$CUR_TIME')
                 ON DUPLICATE KEY UPDATE expiry_date='$FULL_DATE', status_summary='$STATUS_MSG_ESC', updated_at='$CUR_TIME';"

        # --- [개선] 에러는 화면이 아닌 실행 로그로만 기록 ---
        MYSQL_PWD="$DB_PASS" mysql -h"$DB_HOST" -u"$DB_USER" "$DB_NAME" -e "$L_QUERY" 2>>"$RUN_LOG"
    fi

done < "$LICENSE_FILE"

echo "========================================================================================================================================================================================="
echo ""

echo "[$(date '+%Y-%m-%d %H:%M:%S')] monitor_dashboard.sh 실행 종료" >> "$RUN_LOG"
