#!/bin/bash

# ***** Start background FastAPI server for Authentication Service

./start-auth-server.sh "$@" > logs/windfire-security-server.log 2>&1 &