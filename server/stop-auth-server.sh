#!/bin/bash
source ../setenv.sh

# ***** Stop Windfire Security Authentication Server

PROCESS_TO_KILL=authServer.py
PID=

# ***** Stop FastAPI server for Authentication Service
main()
{
    getPid
    if [ -z "$PID" ]; then
        echo -e "${BLU}No running process found for $PROCESS_TO_KILL, so far so good, exiting ...${RESET}"
        return 0
    else
        echo -e "${BLU}PID = $PID, stop it${RESET}"
        kill -9 $PID
        echo -e "${BLU}Check if process has been stopped${RESET}"
        getPid
    fi
}

getPid()
{
    echo -e "${BLU}Getting PID for $PROCESS_TO_KILL ...${RESET}"
    ps aux | grep $PROCESS_TO_KILL
    PID=$(pgrep -f $PROCESS_TO_KILL)
    return $pid
}

# ***** MAIN EXECUTION
main