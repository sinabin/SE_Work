# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash

# 사용법: ./check_disk.sh [마운트포인트]
# 예시: ./check_disk.sh /data

MOUNT_POINT=$1

if [ -z "$MOUNT_POINT" ]; then
    echo "마운트 포인트가 입력되지 않았습니다. 기본값 '/'을 확인합니다."
    echo "사용법 예시: $0 /var"
    MOUNT_POINT="/"
fi

echo "======================================================================"
echo " 대상 그룹: all | 확인 마운트: $MOUNT_POINT"
echo "======================================================================"
printf "%-15s | %-15s | %-8s | %-8s | %-6s\n" "Hostname" "Mounted On" "Size" "Avail" "Use%"
echo "----------------------------------------------------------------------"

# pdsh 실행 및 awk를 이용한 파싱
# $1: Hostname: (콜론 포함)
# $2: Filesystem
# $3: Size
# $4: Used
# $5: Avail
# $6: Use%
# $7: Mounted on

pdsh -g all "df -h" 2>/dev/null | awk -v target="$MOUNT_POINT" '
{
    if ($NF == target) {
        # 호스트명 뒤의 콜론(:) 제거
        hostname = substr($1, 1, length($1)-1)
        
        # 포맷에 맞춰 출력 (호스트명, 마운트위치, 전체크기, 남은크기, 사용률)
        printf "%-15s | %-15s | %-8s | %-8s | %-6s\n", hostname, $NF, $3, $5, $6
    }
}' | sort  # 호스트명 순으로 정렬

echo "======================================================================"



