# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash
# DB 정보
DB_USER="kwj"
DB_PASS="${DB_PASS:-CHANGE_ME}"; DB_NAME="monitoring_db"
SAVE_DIR="/home/ccnuser/log/xcat/daily_reports"

mkdir -p "$SAVE_DIR"
FILE_NAME="Server_Report_$(date +%Y%m%d).csv"

mysql -u$DB_USER -p$DB_PASS $DB_NAME -e "SELECT * FROM disk_inventory WHERE check_time >= DATE_SUB(NOW(), INTERVAL 1 DAY) ORDER BY check_time DESC;" > "$SAVE_DIR/$FILE_NAME"

echo "Report Generated: $SAVE_DIR/$FILE_NAME"
