#!/bin/bash

# Sentry Docker  1.0
#  1.0 - 2025-01-07 - 
#  
#  1.0 - 2025-01-07 - 
#  

# 
SERVER="root@192.168.8.89"
REMOTE_PATH="/home/sentry/"
LOCAL_PATH="/Users/b/WebstormProjects/sentry-docker"

# 
FILES_TO_SYNC=(
    "docker-compose.yml"
    "sentry.conf.py"
#    ".env"
    "nginx.conf"
    "clickhouse/"
    "relay/"
    "scripts/"
)

# 
sync_files() {
    echo "  ..."
    
    #  rsync  --evasive  --whole-file 
    rsync -avz --progress --whole-file \
        "$LOCAL_PATH/docker-compose.yml" \
        "$LOCAL_PATH/sentry.conf.py" \
        "$LOCAL_PATH/.env" \
        "$LOCAL_PATH/nginx.conf" \
        "$LOCAL_PATH/clickhouse/" \
        "$LOCAL_PATH/relay/" \
        "$LOCAL_PATH/scripts/" \
        "$SERVER:$REMOTE_PATH"
    
    if [ $? -eq 0 ]; then
        echo " !"
    else
        echo " !"
    fi
}

# 
main() {
    echo "=== Sentry Docker  ==="
    echo " : $SERVER"
    echo " : $LOCAL_PATH"
    echo " : $REMOTE_PATH"
    echo ""
    
    echo "  :"
    for file in "${FILES_TO_SYNC[@]}"; do
        echo "  - $file"
    done
    echo ""
    
    echo "  ..."
    sync_files
}

# 
main "$@"
