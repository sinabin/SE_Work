# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash

NODE_FILE="nodes.txt"

if [ ! -f "$NODE_FILE" ] ; then
   echo "오류 : $NODE_FILE 파일이 없습니다"
   exit 1
fi

echo "--- 디스크 사용량 80% 초과 노드 점검 시작 ---"

while read -r node; do
#    echo "점검 중인 서버: $node"
#    node=$(echo "$node" | tr -d '\r')
    node=$(echo "$node")
    [ -z "$node" ] && continue

    echo "-------------------------------"
    echo " 접속시도중 : [$node] "
    
    #ssh -n "$node" "df -h" 2>&1
    ssh -n "$node" "df -h | tail -n +2 | awk '{print \$5, \$6}'" < /dev/null | while read -r usage_raw mount ; do 

        usage=$(echo "$usage_raw" | tr -d '%')

        if [ "$usage" -ge 80 ]; then
           echo " [!경고] $mount 파티션이 ${usage}% 사용 중 입니다."
        fi
done

done < "$NODE_FILE"

echo "------------ 완료 -------------"
