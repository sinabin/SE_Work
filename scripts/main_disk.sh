# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash

# [환경 설정]
#source /etc/profile
#source ~/.bash_profile
#export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH



echo "[$(date '+%Y-%m-%d %H:%M:%S')] 디스크 점검을 시작합니다."

CONFIG_FILE="/home/ccnuser/sysmon/sbin/txt_file/maindisk_list.txt" 

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: 설정 파일($CONFIG_FILE)이 없습니다."
    exit 1
fi

echo "모든 서버의 디스크 정보를 수집 중입니다."
ALL_DISK_INFO=$(pdsh -g all "df -h" 2>/dev/null)

echo "==================================================================================="
# [수정] 헤더에 Avail(G) 추가 및 구분선 길이 조정
printf "%-15s | %-20s | %-9s | %-9s | %-9s | %-6s\n" "Hostname" "Target Mount" "Size(G)" "Used(G)" "Avail(G)" "Use%"
echo "---------------===-----------------------------------------------------------------"

grep -vE '^\s*#|^\s*$' "$CONFIG_FILE" | while read -r LINE; do

    read -r -a ARR <<< "$LINE"
    HOST=${ARR[0]}

    for ((i=1; i<${#ARR[@]}; i++)); do
        TARGET_PATH=${ARR[i]}

        # awk 내부 로직
        RESULT=$(echo "$ALL_DISK_INFO" | awk -v h="$HOST:" -v p="$TARGET_PATH" '
            
            # 단위 변환 함수 (G로 통일)
            function to_gb(raw_val) {
                val = raw_val + 0
                unit = toupper(substr(raw_val, length(raw_val)))
                
                if (unit == "T") return val * 1024
                if (unit == "G") return val
                if (unit == "M") return val / 1024
                if (unit == "K") return val / 1024 / 1024
                return val 
            }

            $1 == h && $NF == p {
                # Size($3), Used($4), Avail($5) 모두 변환
                size_gb  = to_gb($3)
                used_gb  = to_gb($4)
                avail_gb = to_gb($5)

            #    use_pct = $6
            #    sub(/%/, "", use_pct)

                # 결과 출력: Size Used Avail Use%
                printf "%.1f %.1f %.1f %s\n", size_gb, used_gb, avail_gb, $6
            }
        ')

        if [ -n "$RESULT" ]; then
            # [수정] 변수 4개 받기 (Size, Used, Avail, Use%)
            read SIZE_G USED_G AVAIL_G PERC <<< "$RESULT"
            
            # [수정] Avail 컬럼 추가하여 출력
            printf "%-15s | %-20s | %-9s | %-9s | %-9s | %-6s\n" "$HOST" "$TARGET_PATH" "$SIZE_G" "$USED_G" "$AVAIL_G" "$PERC"
        else
            printf "%-15s | %-20s | %-9s | %-28s\n" "$HOST" "$TARGET_PATH" "Not Found" ""
        fi
    done
done

echo "==================================================================================="

