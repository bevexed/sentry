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
sync_files() {
    echo "  ..."

    #  rsync  --evasive  --whole-file  --relative
    cd "$LOCAL_PATH"
    rsync -avz --progress --whole-file --relative \
        docker-compose.yml \
        sentry.conf.py \
        .env \
        nginx.conf \
        clickhouse/ \
        patches/ \
        relay/ \
        scripts/ \
        sentry-images/ \
        "$SERVER:$REMOTE_PATH"
    cd - > /dev/null
    
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
    
    echo "  ..."
    sync_files
}

# 
main "$@"
