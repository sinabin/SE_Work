# NOTE: Codex 이관용 사본. 원본의 평문 비밀정보는 환경변수/CHANGE_ME로 치환됨.
#!/bin/bash

TARGET_DIR="/home/ccnuser/scouter/server/database"
RETENTION_ARCHIVE_DAYS=30 
RETENTION_DELETE_DAYS=90 

if [ ! -d "$TARGET_DIR" ]; then
    echo "[ERROR] Target directory does not exist: $TARGET_DIR"
    exit 1
fi

cd "$TARGET_DIR" || exit 1

echo "================================================="
echo " Scouter Database Cleanup Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================="

echo "[1] Archiving directories older than $RETENTION_ARCHIVE_DAYS days..."

find . -maxdepth 1 -mindepth 1 -type d -regextype posix-extended -regex '\./[0-9]{8}' -mtime +$RETENTION_ARCHIVE_DAYS | while read -r DIR_PATH; do
    DIR_NAME=$(basename "$DIR_PATH")
    ARCHIVE_NAME="${DIR_NAME}.tar.gz"

    echo " -> Archiving $DIR_NAME to $ARCHIVE_NAME..."
    
    tar -czf "$ARCHIVE_NAME" "$DIR_NAME" --remove-files
    
    if [ $? -eq 0 ]; then
        echo "    Successfully archived and removed original directory: $DIR_NAME"
    else
        echo "    [ERROR] Failed to archive $DIR_NAME"
    fi
done

echo "[2] Deleting archives older than $RETENTION_DELETE_DAYS days..."

find . -maxdepth 1 -type f -regextype posix-extended -regex '\./[0-9]{8}\.tar\.gz' -mtime +$RETENTION_DELETE_DAYS | while read -r FILE_PATH; do
    FILE_NAME=$(basename "$FILE_PATH")
    
    echo " -> Deleting old archive: $FILE_NAME"
    rm -f "$FILE_PATH"
done

echo "================================================="
echo " Cleanup Finished: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================="
