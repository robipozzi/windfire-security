source ../setenv.sh

# ***** Create Python Virtual environment
run()
{
    echo ${grn}Creating Python3 Virtual Environment ...${end}
    python3 -m venv $PYTORCH_TEST_VIRTUAL_ENV
    echo ${grn}Python3 Virtual Environment created${end}
}

# ***** MAIN EXECUTION
run