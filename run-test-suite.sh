#!/bin/bash
# ***** Windfire Security one-shot test suite
# Offline tier (pytest, Keycloak mocked) + live tier (end-to-end against dev, test or prod).
# For dev, the local auth server is started in the background when it isn't already running.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ===== VARIABLES =====
TESTS_DIR=$SCRIPT_DIR/tests
SERVER_DIR=$SCRIPT_DIR/server
REPORTS_DIR=$TESTS_DIR/reports
SUITE_VENV=$TESTS_DIR/$PYTHON_SUITE_VIRTUAL_ENV
SUITE_PYTHON=$SUITE_VENV/bin/python
CLIENT_REPO=$HOME/dev/windfire-security-client
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SERVER_START_TIMEOUT=30
SERVER_STOP_TIMEOUT=10

ENVIRONMENT=""
SCOPE=all
PYTEST_EXPR=""
NO_START=false
KEEP_SERVER=false
ASSUME_YES=false
VERBOSE=false

TARGET_HOST=""
TARGET_PORT=""
TARGET_ROOT_CA=""
STARTED_PID=""
SERVER_LOG=""
UNIT_RESULT="NOT RUN"
LIVE_RESULT="NOT RUN"
LIVE_NOTE=""
EXIT_CODE=0

# ===== MAIN FUNCTION =====
main()
{
    echo -e "${BOLD}${BLU}##########################################################${RESET}"
    echo -e "${BOLD}${BLU}############### Windfire Security test suite ##############${RESET}"
    echo -e "${BOLD}${BLU}##########################################################${RESET}"
    echo

    parse_args "$@"
    if [ "$SCOPE" != "unit" ] && [ -z "$ENVIRONMENT" ]; then
        selectEnvironment
    fi

    setup_venv || exit 1
    mkdir -p "$REPORTS_DIR"

    if [ "$SCOPE" != "live" ]; then
        run_unit_tier
    fi
    if [ "$SCOPE" != "unit" ]; then
        run_live_tier
    fi

    print_summary
    exit $EXIT_CODE
}

# ===== VIRTUAL ENVIRONMENT =====
# Rebuilt when a requirements file changes, so a merged dependabot bump is what really gets tested
setup_venv()
{
    if [ ! -x "$SUITE_PYTHON" ]; then
        echo -e "${MAGENTA}Creating Python virtual environment $SUITE_VENV ...${RESET}"
        python3 -m venv "$SUITE_VENV" || { echo -e "${RED}Cannot create $SUITE_VENV${RESET}"; return 1; }
    fi
    local client_marker="client:absent"
    [ -d "$CLIENT_REPO" ] && client_marker="client:present"
    local stamp
    stamp=$( { cat "$TESTS_DIR/requirements.txt" "$SERVER_DIR/requirements.txt" "$SCRIPT_DIR/test/requirements.txt"; echo "$client_marker"; } | shasum -a 256 | cut -d' ' -f1)
    local stamp_file=$SUITE_VENV/.requirements.sha256
    if [ "$(cat "$stamp_file" 2>/dev/null)" != "$stamp" ]; then
        echo -e "${MAGENTA}Installing test suite dependencies ...${RESET}"
        "$SUITE_PYTHON" -m pip install -q --disable-pip-version-check -r "$TESTS_DIR/requirements.txt" || { echo -e "${RED}Dependency installation failed${RESET}"; return 1; }
        if [ -d "$CLIENT_REPO" ]; then
            "$SUITE_PYTHON" -m pip install -q --disable-pip-version-check -e "$CLIENT_REPO" || { echo -e "${RED}Installation of $CLIENT_REPO failed${RESET}"; return 1; }
        else
            echo -e "${YELLOW}$CLIENT_REPO not found: the client and flow tests will be skipped${RESET}"
        fi
        echo "$stamp" > "$stamp_file"
    fi
}

# ===== OFFLINE TIER =====
run_unit_tier()
{
    echo -e "${BOLD}${CYAN}===== Offline tier (Keycloak mocked, no network) =====${RESET}"
    run_pytest unit "$TESTS_DIR/unit" unit
    UNIT_RESULT=$TIER_RESULT
    echo
}

# ===== LIVE TIER =====
run_live_tier()
{
    echo -e "${BOLD}${CYAN}===== Live tier: $ENVIRONMENT =====${RESET}"
    read_target

    if [ -z "$TARGET_HOST" ] || [ -z "$TARGET_PORT" ]; then
        # pytest skips every live test with the "not configured" message
        echo -e "${YELLOW}Environment '$ENVIRONMENT' is not configured in tests/environments.json${RESET}"
        run_pytest live "$TESTS_DIR/live" live
        LIVE_RESULT=$TIER_RESULT
        LIVE_NOTE="environment not configured, tests skipped"
        return
    fi

    if [ "$ENVIRONMENT" = "prod" ] && ! confirm_prod; then
        LIVE_RESULT="NOT RUN"
        LIVE_NOTE="cancelled"
        [ $EXIT_CODE -eq 0 ] && EXIT_CODE=1
        return
    fi

    get_test_credentials

    if [ "$ENVIRONMENT" = "dev" ] && [ "$TARGET_HOST" = "localhost" ]; then
        if ! ensure_local_server; then
            LIVE_RESULT=FAIL
            [ $EXIT_CODE -eq 0 ] && EXIT_CODE=1
            return
        fi
    elif ! server_healthy; then
        echo -e "${RED}Windfire Security server not reachable at https://$TARGET_HOST:$TARGET_PORT${RESET}"
        LIVE_RESULT=FAIL
        LIVE_NOTE="server not reachable at $TARGET_HOST:$TARGET_PORT"
        [ $EXIT_CODE -eq 0 ] && EXIT_CODE=1
        return
    fi

    run_pytest live "$TESTS_DIR/live" live --env "$ENVIRONMENT"
    LIVE_RESULT=$TIER_RESULT
}

# Host, port and Root CA of the environment, with the same overrides the tests apply
read_target()
{
    local values
    values=$(cd "$TESTS_DIR" && "$SUITE_PYTHON" -c '
import sys
from suite_helpers import load_env_cfg
cfg = load_env_cfg(sys.argv[1])
print(cfg.get("host") or "", cfg.get("port") or "", cfg.get("root_ca") or "")
' "$ENVIRONMENT") || { echo -e "${RED}Cannot read tests/environments.json${RESET}"; exit 1; }
    read -r TARGET_HOST TARGET_PORT TARGET_ROOT_CA <<< "$values"
}

confirm_prod()
{
    echo -e "${RED}${BOLD}##################################################################${RESET}"
    echo -e "${RED}${BOLD}  PRODUCTION: read-only tests against $TARGET_HOST:$TARGET_PORT${RESET}"
    echo -e "${RED}${BOLD}##################################################################${RESET}"
    if [ "$ASSUME_YES" = true ]; then
        return 0
    fi
    local answer
    read -r -p "Continue? [y/N] " answer
    [[ "$answer" =~ ^[yY]$ ]]
}

# Credentials from WINDFIRE_TEST_USERNAME / WINDFIRE_TEST_PASSWORD (/ WINDFIRE_TEST_SERVICE), else asked once
get_test_credentials()
{
    if [ -n "$WINDFIRE_TEST_USERNAME" ] && [ -n "$WINDFIRE_TEST_PASSWORD" ]; then
        return
    fi
    if [ ! -t 0 ]; then
        # No terminal to ask on (getCredentials would loop on an empty password)
        echo -e "${YELLOW}No credentials and no terminal: the tests that need a login are skipped${RESET}"
        return
    fi
    echo -e "${BLU}Credentials for the live tests (or export WINDFIRE_TEST_USERNAME / WINDFIRE_TEST_PASSWORD):${RESET}"
    getCredentials
    export WINDFIRE_TEST_USERNAME="$USERNAME"
    export WINDFIRE_TEST_PASSWORD="$PASSWORD"
    export WINDFIRE_TEST_SERVICE="$AUTH_SERVICE_TEST"
}

server_healthy()
{
    local code
    code=$(curl -s -o /dev/null -m 3 --cacert "$TARGET_ROOT_CA" -w '%{http_code}' "https://$TARGET_HOST:$TARGET_PORT/v1/monitor/health" 2>/dev/null)
    [ "$code" = "200" ]
}

# ===== LOCAL AUTH SERVER (dev) =====
ensure_local_server()
{
    # The tests target the port the local server really listens on: API_PORT_SECURE in server/.env
    local env_port
    env_port=$(getEnvFileValue "$SERVER_DIR/.env" API_PORT_SECURE)
    if [ -z "$WINDFIRE_SECURITY_PORT" ] && [ -n "$env_port" ] && [ "$env_port" != "$TARGET_PORT" ]; then
        echo -e "${YELLOW}server/.env API_PORT_SECURE=$env_port differs from tests/environments.json dev port $TARGET_PORT: using $env_port${RESET}"
        TARGET_PORT=$env_port
        export WINDFIRE_SECURITY_PORT=$env_port
    fi

    if server_healthy; then
        echo -e "${GREEN}Windfire Security server already running on $TARGET_HOST:$TARGET_PORT: using it${RESET}"
        return 0
    fi
    if [ "$NO_START" = true ]; then
        echo -e "${RED}No Windfire Security server on $TARGET_HOST:$TARGET_PORT and -n given: start it with server/start-auth-server.sh${RESET}"
        LIVE_NOTE="no server running (-n)"
        return 1
    fi

    SERVER_LOG=$REPORTS_DIR/server-dev-$TIMESTAMP.log
    echo -e "${BLU}Starting Windfire Security server in background on port $TARGET_PORT (log: $SERVER_LOG) ...${RESET}"
    ( cd "$SERVER_DIR" && exec "$SUITE_PYTHON" authServer.py --port "$TARGET_PORT" ) > "$SERVER_LOG" 2>&1 &
    STARTED_PID=$!

    local i
    for ((i = 0; i < SERVER_START_TIMEOUT; i++)); do
        if ! kill -0 "$STARTED_PID" 2>/dev/null; then
            echo -e "${RED}The server exited during startup. Last lines of $SERVER_LOG:${RESET}"
            tail -n 30 "$SERVER_LOG"
            STARTED_PID=""
            LIVE_NOTE="server failed to start"
            return 1
        fi
        if server_healthy; then
            echo -e "${GREEN}Server ready (PID $STARTED_PID)${RESET}"
            return 0
        fi
        sleep 1
    done
    echo -e "${RED}The server did not answer within ${SERVER_START_TIMEOUT}s. Last lines of $SERVER_LOG:${RESET}"
    tail -n 30 "$SERVER_LOG"
    LIVE_NOTE="server not ready after ${SERVER_START_TIMEOUT}s"
    return 1
}

# Stops only the server this script started (never one started by hand)
cleanup()
{
    if [ -z "$STARTED_PID" ] || ! kill -0 "$STARTED_PID" 2>/dev/null; then
        return
    fi
    if [ "$KEEP_SERVER" = true ]; then
        echo -e "${YELLOW}Server left running (-K): PID $STARTED_PID, log $SERVER_LOG${RESET}"
        return
    fi
    echo -e "${BLU}Stopping the Windfire Security server started by the suite (PID $STARTED_PID) ...${RESET}"
    kill -TERM "$STARTED_PID" 2>/dev/null
    local i
    for ((i = 0; i < SERVER_STOP_TIMEOUT; i++)); do
        kill -0 "$STARTED_PID" 2>/dev/null || return
        sleep 1
    done
    kill -KILL "$STARTED_PID" 2>/dev/null
}

# ===== PYTEST =====
# run_pytest <tier> <path> <marker> [extra args]; sets TIER_RESULT and EXIT_CODE
run_pytest()
{
    local tier=$1 path=$2 marker=$3
    shift 3
    local args=(-c "$TESTS_DIR/pytest.ini" "$path" -m "$marker"
                --junitxml "$REPORTS_DIR/${ENVIRONMENT:-offline}-$tier-$TIMESTAMP.xml" "$@")
    [ -n "$PYTEST_EXPR" ] && args+=(-k "$PYTEST_EXPR")
    if [ "$VERBOSE" = true ]; then
        args+=(-v)
    else
        args+=(-q)
    fi
    "$SUITE_PYTHON" -m pytest "${args[@]}"
    local rc=$?
    case $rc in
        0) TIER_RESULT=PASS ;;
        5) TIER_RESULT="NO TESTS" ;;  # -k selected nothing in this tier
        *) TIER_RESULT=FAIL
           [ $EXIT_CODE -eq 0 ] && EXIT_CODE=$rc ;;
    esac
}

print_result()
{
    local name=$1 result=$2 note=$3
    local color=$YELLOW
    [ "$result" = PASS ] && color=$GREEN
    [ "$result" = FAIL ] && color=$RED
    echo -e "  $name ${color}${BOLD}$result${RESET}${note:+ ($note)}"
}

print_summary()
{
    echo
    echo -e "${BOLD}===== Summary =====${RESET}"
    [ "$SCOPE" != "live" ] && print_result "Offline tier:" "$UNIT_RESULT"
    [ "$SCOPE" != "unit" ] && print_result "Live tier ($ENVIRONMENT):" "$LIVE_RESULT" "$LIVE_NOTE"
    echo -e "  JUnit reports in ${REPORTS_DIR}"
    if [ $EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}${BOLD}ALL PASSED${RESET}"
    else
        echo -e "${RED}${BOLD}FAILED${RESET}"
    fi
}

# ===== ARGUMENT PARSING =====
parse_args()
{
    local opt
    while getopts ":e:s:k:nKyvh" opt; do
        case $opt in
            e) ENVIRONMENT=$OPTARG ;;
            s) SCOPE=$OPTARG ;;
            k) PYTEST_EXPR=$OPTARG ;;
            n) NO_START=true ;;
            K) KEEP_SERVER=true ;;
            y) ASSUME_YES=true ;;
            v) VERBOSE=true ;;
            h) print_help; exit 0 ;;
            :) echo -e "${RED}Error: option -$OPTARG needs a value${RESET}"; echo "Use -h for usage information"; exit 1 ;;
            *) echo -e "${RED}Error: unknown option -$OPTARG${RESET}"; echo "Use -h for usage information"; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))
    if [ $# -gt 0 ]; then
        echo -e "${RED}Error: unexpected argument '$1'${RESET}"
        exit 1
    fi
    case "$ENVIRONMENT" in
        ""|dev|test|prod) ;;
        *) echo -e "${RED}Error: invalid environment '$ENVIRONMENT'${RESET}"; echo "Valid options: dev, test, prod"; exit 1 ;;
    esac
    case "$SCOPE" in
        unit|live|all) ;;
        *) echo -e "${RED}Error: invalid scope '$SCOPE'${RESET}"; echo "Valid options: unit, live, all"; exit 1 ;;
    esac
}

print_help()
{
    echo -e "${BOLD}USAGE:${RESET}"
    echo -e "    ./run-test-suite.sh [-e dev|test|prod] [-s unit|live|all] [-k <expr>] [-n] [-K] [-y] [-v] [-h]"
    echo
    echo -e "${BOLD}OPTIONS:${RESET}"
    echo -e "    -e ENV     Environment of the live tier: dev, test or prod. Asked for when missing"
    echo -e "    -s SCOPE   unit (offline only), live (live only) or all. Default: all"
    echo -e "    -k EXPR    Only run the tests matching the pytest -k expression"
    echo -e "    -n         Never start the local auth server (dev); fail if none is running"
    echo -e "    -K         Keep the auth server started by the suite running after the tests"
    echo -e "    -y         Don't ask for confirmation before testing prod"
    echo -e "    -v         Verbose pytest output"
    echo -e "    -h         Show this help"
    echo
    echo -e "${BOLD}CREDENTIALS:${RESET}"
    echo -e "    The live tier reads WINDFIRE_TEST_USERNAME, WINDFIRE_TEST_PASSWORD and WINDFIRE_TEST_SERVICE"
    echo -e "    (default service: windfire-calendar-srv). If they are missing, it asks for them."
    echo
    echo -e "${BOLD}EXAMPLES:${RESET}"
    echo -e "    ./run-test-suite.sh                  # asks for the environment, runs everything"
    echo -e "    ./run-test-suite.sh -s unit          # offline tier only, no network"
    echo -e "    ./run-test-suite.sh -e dev           # starts the local server if needed, runs everything"
    echo -e "    ./run-test-suite.sh -e prod -y       # read-only tests against raspberry01"
    echo -e "    ./run-test-suite.sh -e dev -k verify # only the tests whose name contains 'verify'"
}

# ===== EXECUTION =====
trap cleanup EXIT
trap 'exit 130' INT TERM
main "$@"
