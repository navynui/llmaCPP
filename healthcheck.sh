#!/bin/bash

# Configuration
HOST="localhost"
PORT="8080"
ENDPOINT="/health"
URL="http://$HOST:$PORT$ENDPOINT"

echo "--- Health Check Report ($(date)) ---"

# 1. Check llama-server status
# We use a short timeout to avoid hanging
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$URL")

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "Server Status: [ OK ] (HTTP 200)"
    STATUS=0
else
    echo "Server Status: [ FAIL ] (HTTP $HTTP_STATUS)"
    STATUS=1
fi

# 2. System Utilization
echo "--- System Utilization ---"

# CPU Usage
CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
echo "CPU Usage: $CPU_LOAD"

# Memory Usage
MEM_INFO=$(free -m | awk 'NR==2{printf "Memory: %s/%sMB (%.2f%%)", $3,$2,$3*100/$2}')
echo "$MEM_INFO"

# GPU Usage (NVIDIA)
if command -v nvidia-smi &> /dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | awk -F', ' '{printf "GPU Util: %s%% | VRAM: %s/%sMB (%.2f%%)", $1, $2, $3, $2*100/$3}')
    echo "$GPU_INFO"
else
    echo "GPU Info: Not available (nvidia-smi not found)"
fi

echo "------------------------------------"

exit $STATUS
