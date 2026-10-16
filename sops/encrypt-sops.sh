#!/bin/bash
source ../common.sh

# ***** Encrypt / decrypt files with sops and age
#
# Usage: ./encrypt-sops.sh [function] [input file] [output file]
#   function    : 1=Encrypt, 2=Decrypt (asked interactively if omitted)
#   input file  : file to encrypt or decrypt (asked interactively if omitted)
#   output file : defaults to <input file>.sops.json when encrypting,
#                 and to <input file> without .sops.json when decrypting
#
# Files are encrypted in sops binary mode stored as JSON, so any file (keys, certificates, .env, ...)
# is supported. The age key file defaults to $DEFAULT_SOPS_AGE_KEY_FILE (from common.sh); it is asked
# interactively and can also be preset with the SOPS_AGE_KEY_FILE environment variable.

# ===== VARIABLES =====
SCRIPT=encrypt-sops.sh
FUNCTION_CHOICE=$1
FUNCTION=
INPUT_FILE=$2
OUTPUT_FILE=$3
AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-$DEFAULT_SOPS_AGE_KEY_FILE}
AGE_RECIPIENT=
OUTPUT_IN_PROGRESS=false

# ===== MAIN FUNCTION =====
main()
{
    trap cleanup EXIT
    checkPreRequisites
    getAgeKeyFile
    $FUNCTION
}

# ===== FUNCTION SELECTION FUNCTION =====
chooseFunction()
{
    if [ -z "$FUNCTION_CHOICE" ]; then
        echo -e "${GREEN}Choose function : ${RESET}"
        echo -e "${GREEN}1. Encrypt a file with sops${RESET}"
        echo -e "${GREEN}2. Decrypt a file with sops${RESET}"
        read FUNCTION_CHOICE
    fi
    case $FUNCTION_CHOICE in
        1)  FUNCTION=encryptFile
            ;;
        2)  FUNCTION=decryptFile
            ;;
        *)  printf "\n${RED}No valid option selected${RESET}\n"
            FUNCTION_CHOICE=
            chooseFunction
            ;;
    esac
}

# ===== ENCRYPT FILE FUNCTION =====
encryptFile()
{
    echo -e "${BLU}************************************${RESET}"
    echo -e "${BLU}***** Encrypt a file with sops *****${RESET}"
    echo -e "${BLU}************************************${RESET}"
    echo

    getInputFile
    if [ -z "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="${INPUT_FILE}${SOPS_ENCRYPTED_SUFFIX}"
    fi
    confirmOverwrite

    # 1) Encrypt input file for the age public key of the selected key file
    echo -e "Encrypting ${BLU}$INPUT_FILE${RESET} for age recipient ${BOLD}$AGE_RECIPIENT${RESET} ..."
    OUTPUT_IN_PROGRESS=true
    sops -e --age "$AGE_RECIPIENT" --input-type binary --output-type json "$INPUT_FILE" > "$OUTPUT_FILE" \
        || { echo -e "${RED}Error: failed to encrypt $INPUT_FILE${RESET}" >&2; exit 1; }

    # 2) Check that the encrypted file decrypts back to the same bytes
    echo "Checking that the encrypted file decrypts back to the original ..."
    SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" sops -d --input-type json --output-type binary "$OUTPUT_FILE" | cmp -s - "$INPUT_FILE" \
        || { echo -e "${RED}Error: round trip check failed, $OUTPUT_FILE does not decrypt to $INPUT_FILE${RESET}" >&2; exit 1; }
    OUTPUT_IN_PROGRESS=false
    echo -e "File encrypted to ${BLU}$OUTPUT_FILE${RESET} (round trip check OK)"
    echo

    # 3) Optionally delete the plain file
    deletePlainFile
}

# ===== DECRYPT FILE FUNCTION =====
decryptFile()
{
    echo -e "${BLU}************************************${RESET}"
    echo -e "${BLU}***** Decrypt a file with sops *****${RESET}"
    echo -e "${BLU}************************************${RESET}"
    echo

    getInputFile
    if [ -z "$OUTPUT_FILE" ]; then
        if [[ "$INPUT_FILE" != *"$SOPS_ENCRYPTED_SUFFIX" ]]; then
            echo -e "${RED}Error: $INPUT_FILE does not end with $SOPS_ENCRYPTED_SUFFIX, pass the output file as third argument${RESET}" >&2
            exit 1
        fi
        OUTPUT_FILE="${INPUT_FILE%"$SOPS_ENCRYPTED_SUFFIX"}"
    fi
    confirmOverwrite

    # Decrypted content may be secret (e.g. a private key): readable by the owner only
    echo -e "Decrypting ${BLU}$INPUT_FILE${RESET} ..."
    OUTPUT_IN_PROGRESS=true
    ( umask 077 && SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" sops -d --input-type json --output-type binary "$INPUT_FILE" > "$OUTPUT_FILE" ) \
        || { echo -e "${RED}Error: failed to decrypt $INPUT_FILE (is it encrypted for the age key in $AGE_KEY_FILE?)${RESET}" >&2; exit 1; }
    chmod 600 "$OUTPUT_FILE"
    OUTPUT_IN_PROGRESS=false
    echo -e "File decrypted to ${BLU}$OUTPUT_FILE${RESET} (mode 0600)"
    echo
    echo -e "${YELLOW}Reminder: if $OUTPUT_FILE holds a secret, delete it as soon as you no longer need it:${RESET}"
    echo "    rm -f \"$OUTPUT_FILE\""
    echo
}

# ===== HELPER FUNCTIONS =====
checkPreRequisites()
{
    for CMD in sops age-keygen; do
        if ! command -v "$CMD" >/dev/null 2>&1; then
            echo -e "${RED}Error: $CMD is required but was not found on the PATH (install it with: brew install sops age)${RESET}" >&2
            exit 1
        fi
    done
}

getAgeKeyFile()
{
    read -r -p "Enter age key file [${AGE_KEY_FILE}]: " INPUT_AGE_KEY_FILE
    if [[ -n "$INPUT_AGE_KEY_FILE" ]]; then
        AGE_KEY_FILE=${INPUT_AGE_KEY_FILE/#\~/$HOME}
    fi
    if [ ! -r "$AGE_KEY_FILE" ]; then
        echo -e "${RED}Error: age key file not found or not readable: $AGE_KEY_FILE${RESET}" >&2
        exit 1
    fi
    AGE_RECIPIENT=$(age-keygen -y "$AGE_KEY_FILE" 2>/dev/null | head -1)
    if [ -z "$AGE_RECIPIENT" ]; then
        echo -e "${RED}Error: no valid age identity found in $AGE_KEY_FILE${RESET}" >&2
        exit 1
    fi
    echo -e "Using age key file ${BLU}$AGE_KEY_FILE${RESET}"
    echo
}

getInputFile()
{
    while [ -z "$INPUT_FILE" ]; do
        read -r -p "Enter file path: " INPUT_FILE
        INPUT_FILE=${INPUT_FILE/#\~/$HOME}
    done
    if [ ! -f "$INPUT_FILE" ]; then
        echo -e "${RED}Error: file not found: $INPUT_FILE${RESET}" >&2
        exit 1
    fi
}

confirmOverwrite()
{
    if [ -e "$OUTPUT_FILE" ]; then
        echo -e "${YELLOW}Output file already exists: ${BLU}$OUTPUT_FILE${RESET}"
        read -r -p "Overwrite it? [y/N]: " OVERWRITE
        if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
            echo "Nothing changed"
            exit 0
        fi
    fi
}

deletePlainFile()
{
    read -r -p "Delete the plain file $INPUT_FILE now? [y/N]: " DELETE_PLAIN
    if [[ "$DELETE_PLAIN" =~ ^[Yy]$ ]]; then
        rm -f "$INPUT_FILE" || { echo -e "${RED}Error: failed to delete $INPUT_FILE${RESET}" >&2; exit 1; }
        echo -e "Plain file ${BLU}$INPUT_FILE${RESET} deleted"
    else
        echo -e "${YELLOW}Plain file $INPUT_FILE kept: if it holds a secret, delete it once $OUTPUT_FILE is stored safely:${RESET}"
        echo "    rm -f \"$INPUT_FILE\""
    fi
    echo
}

cleanup()
{
    # Never leave a partial or unverified output file behind
    if [ "$OUTPUT_IN_PROGRESS" = true ]; then
        rm -f "$OUTPUT_FILE"
    fi
}

# ##############################################
# #################### MAIN ####################
# ##############################################
chooseFunction
main
