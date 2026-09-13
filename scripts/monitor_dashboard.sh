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
RAW_DATA_FILE="$LOG_DIR/dashboard_temp_$(date +%s).raw"

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

# 스크립트 종료 시 임시 파일 자동 삭제 (Trap)
trap "rm -f $RAW_DATA_FILE" EXIT


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
#ntp
    NTP_PEER=""
    if command -v chronyc >/dev/null 2>&1; then
        PEER=$(chronyc -n sources | awk "\$1 ~ /\*/ {print \$2}")
        [ -n "$PEER" ] && NTP_PEER="$PEER"
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
        CHAGE_INFO=$(sudo -n LC_ALL=C chage -l "$u" 2>/dev/null)
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

    # 업타임 수집 변수 추가
    UPT_RAW=$(uptime)

    UPT_VAL=$(echo $UPT_RAW | cut -d'p' -f2- | cut -d',' -f1,2)

    if [ -z "$UPT_VAL" ]; then
        UPT_VAL="Unknown"
    fi

    
    ############################### 251226 수정#####################################
    #UPT_VAL=$(uptime -p | sed "s/up //")
    #[ -z "$UPT_VAL" ] && UPT_VAL="Unknown"

    # 1. DISK_RES 줄바꿈 제거 (여러 개일 경우 콤마로 구분)
    #[ -z "$DISK_CHECK" ] && DISK_RES="OK" || DISK_RES=$(echo $DISK_CHECK | tr '\n' ',' | sed 's/,$//')

    # 2. 서비스/계정 메시지 공백 및 줄바꿈 정리
    #SVC_MSG=$(echo $SVC_MSG | tr -d '\n')
    #ACC_RES=$(echo $ACC_RES | tr -d '\n')

    # 3. 최종 출력 (순서 고정)
    # 호스트네임은 마스터 스크립트에서 붙여준다고 가정하면 아래와 같이 출력
    # echo "$CPU_USAGE|$MEM_USAGE|$DISK_RES|$NFS_RES|$NTP_FINAL|$SVC_MSG|$ACC_RES|$SEC_MSG|$UPT_VAL"

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
    if command -v pdsh >/dev/null 2>&1; then
        pdsh -g all "$REMOTE_CMD" 2>/dev/null | sed 's/: /|/'
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
        CISCO_CPU=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.4.1.9.9.109.1.1.1.1.5.1 2>/dev/null)
        if ! [[ "$CISCO_CPU" =~ ^[0-9]+$ ]]; then CISCO_CPU=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.4.1.9.2.1.58.0 2>/dev/null); fi
        CISCO_CPU=$(echo "$CISCO_CPU" | awk '{if($1~/^[0-9]+$/){if($1>100)print 100; else print $1} else print 0}')
        MEM_USED=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.4.1.9.9.48.1.1.1.5.1 2>/dev/null)
        MEM_FREE=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.4.1.9.9.48.1.1.1.6.1 2>/dev/null)
        [[ ! "$MEM_USED" =~ ^[0-9]+$ ]] && MEM_USED=0
        [[ ! "$MEM_FREE" =~ ^[0-9]+$ ]] && MEM_FREE=0
        CISCO_MEM=$(awk -v u="$MEM_USED" -v f="$MEM_FREE" 'BEGIN { t=u+f; if(t>0) printf "%.0f", (u/t)*100; else print "0" }')
        RAW_TIME=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.2.1.25.1.2.0 2>/dev/null)
        if [[ "$RAW_TIME" == *"No Such"* ]] || [[ -z "$RAW_TIME" ]]; then TIME_ONLY=$(date "+%H:%M:%S"); else TIME_ONLY=$(echo "$RAW_TIME" | awk -F, '{print $2}' | cut -d. -f1); fi
        SYNC_STATE=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.4.1.9.9.168.1.1.1.0 2>/dev/null)
        if [[ "$SYNC_STATE" == "3" ]] || [[ "$SYNC_STATE" == *"alarm"* ]]; then CISCO_NTP="NoSync ($TIME_ONLY)"; else CISCO_NTP="$TARGET_NTP ($TIME_ONLY)"; fi
        UPTIME_RAW=$(snmpget $SNMP_OPTS "$cisco" .1.3.6.1.2.1.1.3.0 2>/dev/null)
        UPTIME_CLEAN=$(echo "$UPTIME_RAW" | sed 's/Timeticks:.*) //' | sed 's/^ //')
        PRETTY_TIME=$(echo "$UPTIME_CLEAN" | sed 's/ days, /:/g' | sed 's/ day, /:/g')
        if [[ "$UPTIME_CLEAN" == *"days"* ]]; then DAY_ONLY=$(echo "$UPTIME_CLEAN" | awk -F' days' '{print $1}' | awk '{print $NF}'); else DAY_ONLY=0; fi
        [[ " 1.vg1 2.vg2 3.ipcc_sw01 4.ipcc_sw02 " =~ " $cisco " ]] && NEED_FIX=true || NEED_FIX=false
        if [[ "$DAY_ONLY" =~ ^[0-9]+$ ]]; then
            if [ "$NEED_FIX" = true ] && [ "$DAY_ONLY" -lt 100 ]; then UPTIME_FMT="UPTIME:497+${PRETTY_TIME}"; else UPTIME_FMT="UPTIME:${PRETTY_TIME}"; fi
        else UPTIME_FMT="Down"; fi
        PORT_UP_CNT=$(snmpwalk $SNMP_OPTS "$cisco" .1.3.6.1.2.1.2.2.1.8 2>/dev/null | grep -cE "^1$|^up$")
        echo "$cisco|$CISCO_CPU|$CISCO_MEM|-|None|$CISCO_NTP|$UPTIME_FMT, Port:$PORT_UP_CNT|-|-|-|$UPTIME_CLEAN"
    done
} | sort > "$RAW_DATA_FILE"


# ==============================================================================
# 5. 데이터 저장 (CSV & MySQL - 서버 상태)
# ==============================================================================
#CUR_TIME=$(date '+%Y-%m-%d %H:%M:%S')
#
## 5-1. CSV 저장 및 MySQL 저장
#if [ ! -f "$HISTORY_CSV" ]; then echo "Time,Hostname,CPU,MEM,DISK,NFS,NTP,Service,Account,Security" > "$HISTORY_CSV"; fi
#
#while IFS="|" read -r HOST CPU MEM DISK NFS NTP SVC ACC SEC UPT; do
#    echo "$CUR_TIME,$HOST,$CPU,$MEM,$DISK,$NFS,$NTP,$SVC,$ACC,$SEC,$UPT" >> "$HISTORY_CSV"
#
#    # 5-2. MySQL 저장 (linux_server_status 테이블)
#    # 수치에서 % 등 특수문자 제거 후 깔끔하게 입력
#    CPU_VAL=$(echo "$CPU" | tr -d '%')
#    MEM_VAL=$(echo "$MEM" | tr -d '%')
#    
#    QUERY="INSERT INTO linux_server_status (check_time, hostname, cpu_usage, mem_usage, disk_warning, nfs_status, ntp_info, service_info, acc_status, sec_event, uptime)
#           VALUES ('$CUR_TIME', '$HOST', '$CPU_VAL', '$MEM_VAL', '$DISK', '$NFS', '$NTP', '$SVC', '$ACC', '$SEC', '$UPT');"
#
#    MYSQL_PWD="$DB_PASS" mysql -h"$DB_HOST" -u"$DB_USER" "$DB_NAME" -e "$QUERY" 2>/dev/null
#done < "$RAW_DATA_FILE"


    CUR_TIME=$(date '+%Y-%m-%d %H:%M:%S')

    if [ ! -f "$HISTORY_CSV" ]; then 
    echo "Time,Hostname,CPU,MEM,DISK,NFS,NTP,Service,Account,Security,Uptime" > "$HISTORY_CSV"
    fi

    # RAW_DATA_FILE을 읽을 때 혹시 모를 빈 줄이나 잘못된 줄바꿈 방지
    while IFS="|" read -r HOST CPU MEM DISK NFS NTP SVC ACC SEC UPT; do
    [ -z "$HOST" ] && continue

    echo "$CUR_TIME,$HOST,$CPU,$MEM,\"$DISK\",$NFS,\"$NTP\",\"$SVC\",\"$ACC\",$SEC,\"$UPT\"" >> "$HISTORY_CSV"

    CPU_VAL=$(echo "$CPU" | tr -d '%')
    MEM_VAL=$(echo "$MEM" | tr -d '%')
    
    DISK_ESC=$(echo "$DISK" | tr -d '\r\n')
    SVC_ESC=$(echo "$SVC" | tr -d '\r\n')
    NTP_ESC=$(echo "$NTP" | tr -d '\r\n')
    UPT_ESC=$(echo "$UPT" | tr -d '\r\n')

    QUERY="INSERT INTO linux_server_status 
           (check_time, hostname, cpu_usage, mem_usage, disk_warning, nfs_status, ntp_info, service_info, acc_status, sec_event, uptime)
           VALUES 
           ('$CUR_TIME', '$HOST', '$CPU_VAL', '$MEM_VAL', '$DISK_ESC', '$NFS', '$NTP_ESC', '$SVC_ESC', '$ACC', '$SEC', '$UPT_ESC');"
    
    #DB insert 확인
    #echo "실행될 쿼리: $QUERY"    

    MYSQL_PWD="$DB_PASS" mysql -h"$DB_HOST" -u"$DB_USER" "$DB_NAME" -e "$QUERY"
    
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
    
    printf "| %-2d | %-18s | ", count, h
    
    if (cpu >= cpu_lim) print_cell(cpu"%", RED, 6); else print_cell(cpu"%", GREEN, 6); printf " | "
    if (mem >= mem_lim) print_cell(mem"%", RED, 6); else print_cell(mem"%", GREEN, 6); printf " | "
    if(index(sec,"Brute")>0 || index(sec,"Fail")>0) print_cell(sec,RED,12); else if(sec=="Clean") print_cell("Clean",GREEN,12); else print_cell("-",GREEN,12); printf " | "
    if(length(ntp)>28) ntp=substr(ntp,1,26)".."; if(index(ntp,"Down")>0 || index(ntp,"NoSync")>0) print_cell(ntp,RED,28); else print_cell(ntp,GREEN,28); printf " | "
    if(index(svc,"Zombie")>0 || index(svc,"Fail")>0 || index(svc,"Down")>0 || index(svc,"err")>0 || index(svc,"Missing")>0) {
        if(length(svc)>40) svc=substr(svc,1,40); print_cell(svc,RED,40);
    } else if(index(svc,"UPTIME")>0) {
        if(index(svc,"497+")>0) print_cell(svc,YELLOW,40); else print_cell(svc,GREEN,40);
    } else { print_cell("Running",GREEN,40); } printf " | "
    if(index(acc,"EXP")>0 || index(acc,"Must")>0) print_cell(acc,RED,16); else if(acc=="Ok") print_cell(acc,GREEN,16); else if(acc=="-"||acc=="") print_cell("-",GREEN,16); else print_cell(acc,YELLOW,16); printf " | "
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

    # 2. 날짜 문자열 생성 (에러 방지: %s 사용하여 문자열로 결합)
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

    # 5. MySQL 저장
    L_QUERY="INSERT INTO license_status (target_group, expiry_date, license_name, status_summary, updated_at)
             VALUES ('$L_HOST', '$FULL_DATE', '$L_NAME', '$STATUS_MSG', '$CUR_TIME')
             ON DUPLICATE KEY UPDATE expiry_date='$FULL_DATE', status_summary='$STATUS_MSG', updated_at='$CUR_TIME';"
    
    MYSQL_PWD="$DB_PASS" mysql -h"$DB_HOST" -u"$DB_USER" "$DB_NAME" -e "$L_QUERY" 2>/dev/null

done < "$LICENSE_FILE"

echo "========================================================================================================================================================================================="
echo ""
