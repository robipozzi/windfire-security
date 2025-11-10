source ../setenv.sh

PROCESS_TO_KILL=authService.py
PID=

# ***** Stop FastAPI server for Authentication Service
main()
{
    getPid
    if [ -z "$PID" ]; then
        echo "${blu}No running process found for $PROCESS_TO_KILL, so far so good, exiting ...${end}"
        return 0
    else
        echo ${blu}PID = $PID, stop it${end}
        kill -9 $PID
        echo ${blu}Check if process has been stopped${end}
        getPid
    fi
}

getPid()
{
    echo ${blu}Getting PID for $PROCESS_TO_KILL ...${end}
    ps aux | grep $PROCESS_TO_KILL
    PID=$(pgrep -f $PROCESS_TO_KILL)
    return $pid
}

# ***** MAIN EXECUTION
main