# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash

# 1. 테스트할 IP와 커뮤니티 값을 직접 넣으세요 (변수 사용 X)
TARGET="192.168.3.66"
COMM="${SNMP_COMMUNITY:-CHANGE_ME}"

echo "========================================"
echo "진단 시작: $TARGET"
echo "========================================"

# 2. snmpget 명령어 위치 확인
SNMP_PATH=$(which snmpget)
echo "1. snmpget 위치: $SNMP_PATH"

if [ -z "$SNMP_PATH" ]; then
    echo "   [!] 오류: snmpget 명령어를 찾을 수 없습니다."
    exit 1
fi

# 3. EngineTime 조회 (원본 데이터 확인)
echo "2. OID 조회 시도 (.1.3.6.1.6.3.10.2.1.3.0)"
RAW_DATA=$($SNMP_PATH -v2c -c $COMM -Oqv $TARGET .1.3.6.1.6.3.10.2.1.3.0 2>&1)

echo "   -> 원본 응답값: [$RAW_DATA]"

# 4. 숫자만 추출 테스트
CLEAN_DATA=$(echo "$RAW_DATA" | tr -dc '0-9')
echo "   -> 숫자만 추출: [$CLEAN_DATA]"

# 5. 계산 테스트
if [ -n "$CLEAN_DATA" ]; then
    DAYS=$((CLEAN_DATA / 86400))
    echo "   -> 계산 결과: ${DAYS}일"
else
    echo "   -> [!] 숫자 추출 실패. 통신 에러 또는 설정 문제."
fi

echo "========================================"
