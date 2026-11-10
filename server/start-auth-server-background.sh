#!/bin/bash

# ***** Start background FastAPI server for Authentication Service
# Console output (stdout/stderr) goes to logs/windfire-security.log, like the systemd unit on the Raspberry.
# The app's own rotating log stays in logs/windfire-security-server.log, written by the app itself.

cd "$(dirname "$0")" || exit 1
mkdir -p logs

CONSOLE_LOG=logs/windfire-security.log
APP_LOG=logs/windfire-security-server.log

./start-auth-server.sh "$@" >> "$CONSOLE_LOG" 2>&1 &
PID=$!

echo "Windfire Security Authentication Server started in background (PID $PID)"
echo "  Console output: $(pwd)/$CONSOLE_LOG"
echo "  App log:        $(pwd)/$APP_LOG"
echo "  Stop it with:   $(pwd)/stop-auth-server.sh"
