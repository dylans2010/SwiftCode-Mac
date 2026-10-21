#!/usr/bin/env bash
# Double-click this script to view Developer Documentation in Safari

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

PORT=8765
echo "========================================================"
echo " Starting Apple Developer Documentation Web Server..."
echo " Opening http://localhost:$PORT/documentation/developerdocumentation"
echo " Press Ctrl+C to stop the server."
echo "========================================================"

(sleep 1 && open "http://localhost:$PORT/documentation/developerdocumentation") &
python3 -m http.server $PORT
