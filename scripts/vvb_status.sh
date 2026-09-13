# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash

set -e

# --- [환경 설정] ---
VVB_IP=("192.168.3.94" "192.168.3.95")
COMMUNITY="${VVB_SNMP_COMMUNITY:-CHANGE_ME}"
DB_USER="kwj"
DB_PASS="${DB_PASS:-CHANGE_ME}"
DB_NAME="monitoring_db"

echo "===================================================="
echo "모니터링 시작: $(date '+%Y-%m-%d %H:%M:%S')"

for ip in "${VVB_IP[@]}"
do
    echo "------------------------------------------------"
    echo "Target: $ip 분석 중..."

    HOSTNAME="Unknown"
    UPTIME="Unknown"
    CPU_USAGE=0
    MEM_PERC=0.00
    RESULT="SUCCESS"
    ERROR_MSG="Normal" # 에러가 없을 때 기본값

    RAW_DATA=$(snmpget -v2c -c "$COMMUNITY" -t 2 -r 1 -Ovq "$ip" .1.3.6.1.2.1.1.5.0 2>&1)
    EXIT_CODE=$?

    if [ $EXIT_CODE -ne 0 ]; then
        RESULT="FAIL"
        ERROR_MSG=$(echo "$RAW_DATA" | tr -d "'")
        echo "[ERROR] $ip : $ERROR_MSG"
    else
        HOSTNAME=$(echo "$RAW_DATA" | tr -d '"' | awk '{print $1}')
        
        # Uptime 수집
        UPTIME=$(snmpget -v2c -c "$COMMUNITY" -t 2 -Ov "$ip" .1.3.6.1.2.1.1.3.0 2>/dev/null | sed 's/.*) //')
        
        # CPU 수집
        CPU_USAGE=$(snmpget -v2c -c "$COMMUNITY" -t 2 -Ovq "$ip" .1.3.6.1.2.1.25.3.3.1.2.1 2>/dev/null || echo 0)

        # 메모리 수집 및 계산 (Units 반영 검증)
        M_TOTAL=$(snmpget -v2c -c "$COMMUNITY" -Ovq "$ip" .1.3.6.1.2.1.25.2.3.1.5.1 2>/dev/null || echo 0)
        M_USED=$(snmpget -v2c -c "$COMMUNITY" -Ovq "$ip" .1.3.6.1.2.1.25.2.3.1.6.1 2>/dev/null || echo 0)

        if [ "$M_TOTAL" -gt 0 ]; then
            # 메모리 점유율 계산: $ \frac{Used}{Total} \times 100 $
            MEM_PERC=$(echo "scale=2; ($M_USED / $M_TOTAL) * 100" | bc)
            MEM_PERC=$(printf "%.2f" "$MEM_PERC")
        fi
        echo "[SUCCESS] $HOSTNAME ($ip) 데이터 수집 완료"
    fi

    SQL="INSERT INTO vvb_status (ip, hostname, uptime, cpu, mem, result, error_msg, checked_at) \
    VALUES ('$ip', '$HOSTNAME', '$UPTIME', $CPU_USAGE, $MEM_PERC, '$RESULT', '$ERROR_MSG', NOW());"

    export MYSQL_PWD=$DB_PASS
    # DB 입력 실행
    mysql -u"$DB_USER" -D"$DB_NAME" -e "$SQL"

    if [ $? -eq 0 ]; then
        echo ">> DB 저장 완료"
    else
        echo ">> DB 저장 실패 (SQL 문법 확인)"
    fi
done

echo "===================================================="
