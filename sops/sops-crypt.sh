#!/usr/bin/env bash
#
# ***** Encrypt / decrypt files with sops and age
#
# Two modes:
#   file mode (default) : any file (keys, certificates, .env, ...) is encrypted in sops binary mode
#                         and stored as JSON in <file>.sops.json; decryption writes the original bytes back
#   in-place mode (-i)  : structured files (YAML, JSON, .env, INI) are encrypted / decrypted in place,
#                         keys stay readable and only values are encrypted
#
# Usage:
#   ./sops-crypt.sh                                          # fully interactive
#   ./sops-crypt.sh -e -f WindfireKeycloakRootCA.key         # -> WindfireKeycloakRootCA.key.sops.json
#   ./sops-crypt.sh -d -f WindfireKeycloakRootCA.key.sops.json -o /tmp/ca.key
#   ./sops-crypt.sh -e -i -f secrets.yaml                    # encrypt values of secrets.yaml in place
#   ./sops-crypt.sh 1 <input file> [output file]             # legacy encrypt-sops.sh form (1=Encrypt, 2=Decrypt)
#
# The age key file defaults to $DEFAULT_SOPS_AGE_KEY_FILE (from common.sh), and can be preset with the
# SOPS_AGE_KEY_FILE environment variable.

# common.sh reads $1 and other possibly unset variables: source it before enabling nounset
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../common.sh"
set -euo pipefail

# ===== VARIABLES =====
OPERATION=""
IN_PLACE=false
KEY=""
INPUT_FILE=""
OUTPUT_FILE=""
REMOVE_PLAIN=false
ASSUME_YES=false
DEFAULT_KEY_FILE="${SOPS_AGE_KEY_FILE:-$DEFAULT_SOPS_AGE_KEY_FILE}"
KEY_FILE=""
RECIPIENTS=""
SOPS_CMD=()
TMP_FILE=""
OUTPUT_IN_PROGRESS=false

usage()
{
    cat <<EOF
Usage: $(basename "$0") [-e|-d] [-i] [-k <age key>] [-f <input file>] [-o <output file>] [-r] [-y] [-h]
       $(basename "$0") [1|2] [<input file>] [<output file>]

Encrypt or decrypt a file with sops and age. Any option not given is asked interactively.

  -e          Encrypt the file
  -d          Decrypt the file
  -i          In-place mode for structured files (YAML, JSON, .env, INI): keys stay readable.
              Without -i the file is encrypted in binary mode to <file>$SOPS_ENCRYPTED_SUFFIX
  -k <key>    Age key file (default: $DEFAULT_KEY_FILE).
              For encryption one or more age public keys (age1...,age1...) are accepted too
  -f <file>   File to encrypt / decrypt
  -o <file>   Output file (file mode only). Defaults to <file>$SOPS_ENCRYPTED_SUFFIX when encrypting
              and to <file> without $SOPS_ENCRYPTED_SUFFIX when decrypting
  -r          Delete the plain file after a verified encryption (file mode only)
  -y          Do not ask for confirmation (also overwrites an existing output file)
  -h          Show this help

Positional arguments are accepted for compatibility with encrypt-sops.sh:
  1|2|encrypt|decrypt   operation (1=Encrypt, 2=Decrypt)
  <input file>          same as -f
  <output file>         same as -o
EOF
}

# ===== HELPER FUNCTIONS =====
die()
{
    echo -e "${RED}Error: $*${RESET}" >&2
    exit 1
}

warn()
{
    echo -e "${YELLOW}$*${RESET}"
}

expand_tilde()
{
    case "$1" in
        "~") echo "$HOME" ;;
        "~/"*) echo "$HOME/${1#\~/}" ;;
        *) echo "$1" ;;
    esac
}

is_sops_encrypted()
{
    grep -Eq '^sops:|^sops_|"sops"[[:space:]]*:|^\[sops\]' "$1"
}

confirm()
{
    local answer
    [[ "$ASSUME_YES" == true ]] && return 0
    read -r -p "$1 [y/N]: " answer || answer=""
    [[ "$answer" =~ ^([yY]|[yY][eE][sS])$ ]]
}

cleanup()
{
    # Never leave a partial or unverified output file behind
    if [[ "$OUTPUT_IN_PROGRESS" == true && -n "$OUTPUT_FILE" ]]; then
        rm -f "$OUTPUT_FILE"
    fi
    if [[ -n "$TMP_FILE" ]]; then
        rm -f "$TMP_FILE"
    fi
}

# ===== ARGUMENTS =====
parseArguments()
{
    local opt
    while getopts ":edik:f:o:ryh" opt; do
        case "$opt" in
            e) OPERATION="encrypt" ;;
            d) OPERATION="decrypt" ;;
            i) IN_PLACE=true ;;
            k) KEY="$OPTARG" ;;
            f) INPUT_FILE="$OPTARG" ;;
            o) OUTPUT_FILE="$OPTARG" ;;
            r) REMOVE_PLAIN=true ;;
            y) ASSUME_YES=true ;;
            h) usage; exit 0 ;;
            :) die "option -$OPTARG requires an argument" ;;
            *) usage >&2; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    # Legacy encrypt-sops.sh positional form: [1|2] [input file] [output file]
    if [[ $# -gt 0 ]]; then
        case "$1" in
            1 | encrypt) [[ -n "$OPERATION" ]] || OPERATION="encrypt"; shift ;;
            2 | decrypt) [[ -n "$OPERATION" ]] || OPERATION="decrypt"; shift ;;
        esac
    fi
    if [[ $# -gt 0 ]]; then
        [[ -n "$INPUT_FILE" ]] || INPUT_FILE="$1"
        shift
    fi
    if [[ $# -gt 0 ]]; then
        [[ -n "$OUTPUT_FILE" ]] || OUTPUT_FILE="$1"
        shift
    fi
    [[ $# -eq 0 ]] || die "too many arguments: $*"

    if [[ "$IN_PLACE" == true ]]; then
        [[ -z "$OUTPUT_FILE" ]] || die "an output file cannot be used with in-place mode (-i)"
        [[ "$REMOVE_PLAIN" == false ]] || die "-r cannot be used with in-place mode (-i)"
    fi
}

checkPreRequisites()
{
    local cmd
    for cmd in sops age-keygen; do
        command -v "$cmd" >/dev/null 2>&1 \
            || die "$cmd is required but was not found on the PATH (install it with: brew install sops age)"
    done
}

chooseOperation()
{
    # COLUMNS=1 makes select list one entry per line
    local choice COLUMNS=1
    [[ -z "$OPERATION" ]] || return 0
    echo -e "${GREEN}Choose function : ${RESET}"
    PS3="Choice: "
    select choice in "Encrypt a file with sops" "Decrypt a file with sops" "Quit"; do
        case "$REPLY" in
            1) OPERATION="encrypt"; break ;;
            2) OPERATION="decrypt"; break ;;
            3) exit 0 ;;
            *) echo -e "${RED}No valid option selected${RESET}" ;;
        esac
    done
    [[ -n "$OPERATION" ]] || exit 0
}

getAgeKey()
{
    if [[ -z "$KEY" && "$ASSUME_YES" != true ]]; then
        read -r -e -p "Enter age key file [$DEFAULT_KEY_FILE]: " KEY || true
    fi
    KEY="$(expand_tilde "${KEY:-$DEFAULT_KEY_FILE}")"

    if [[ "$KEY" == age1* ]]; then
        [[ "$OPERATION" == "encrypt" ]] \
            || die "decryption needs the private age key file, not a public key ($KEY)"
        RECIPIENTS="$KEY"
        return 0
    fi

    [[ -r "$KEY" ]] || die "age key file not found or not readable: $KEY"
    KEY_FILE="$KEY"
    RECIPIENTS="$(age-keygen -y "$KEY_FILE" 2>/dev/null | paste -sd, -)" || RECIPIENTS=""
    [[ -n "$RECIPIENTS" ]] || die "no valid age identity found in $KEY_FILE"
}

getInputFile()
{
    while [[ -z "$INPUT_FILE" ]]; do
        read -r -e -p "Enter file to $OPERATION: " INPUT_FILE || die "no file given"
    done
    INPUT_FILE="$(expand_tilde "$INPUT_FILE")"
    [[ -f "$INPUT_FILE" ]] || die "file not found: $INPUT_FILE"

    if [[ "$OPERATION" == "encrypt" ]] && is_sops_encrypted "$INPUT_FILE"; then
        die "$INPUT_FILE already looks sops-encrypted"
    fi
    if [[ "$OPERATION" == "decrypt" ]] && ! is_sops_encrypted "$INPUT_FILE"; then
        die "$INPUT_FILE does not look sops-encrypted"
    fi
}

getOutputFile()
{
    if [[ "$IN_PLACE" == true ]]; then
        OUTPUT_FILE="$INPUT_FILE"
        return 0
    fi
    if [[ -z "$OUTPUT_FILE" ]]; then
        if [[ "$OPERATION" == "encrypt" ]]; then
            OUTPUT_FILE="${INPUT_FILE}${SOPS_ENCRYPTED_SUFFIX}"
        else
            [[ "$INPUT_FILE" == *"$SOPS_ENCRYPTED_SUFFIX" ]] \
                || die "$INPUT_FILE does not end with $SOPS_ENCRYPTED_SUFFIX, pass the output file with -o"
            OUTPUT_FILE="${INPUT_FILE%"$SOPS_ENCRYPTED_SUFFIX"}"
        fi
    fi
    OUTPUT_FILE="$(expand_tilde "$OUTPUT_FILE")"
    [[ "$OUTPUT_FILE" != "$INPUT_FILE" ]] || die "output file is the same as the input file, use -i for in-place mode"

    if [[ -e "$OUTPUT_FILE" ]]; then
        warn "Output file already exists: $OUTPUT_FILE"
        confirm "Overwrite it?" || { echo "Nothing changed"; exit 0; }
    fi
}

# ===== SOPS COMMAND =====
buildSopsCommand()
{
    if [[ "$IN_PLACE" == true ]]; then
        # Format is inferred from the original filename; the result is written to a temp file first
        if [[ "$OPERATION" == "encrypt" ]]; then
            SOPS_CMD=(sops --config /dev/null encrypt --age "$RECIPIENTS" --filename-override "$INPUT_FILE" "$INPUT_FILE")
        else
            SOPS_CMD=(env SOPS_AGE_KEY_FILE="$KEY_FILE" sops decrypt --filename-override "$INPUT_FILE" "$INPUT_FILE")
        fi
    else
        if [[ "$OPERATION" == "encrypt" ]]; then
            # --config /dev/null: use the chosen recipients instead of .sops.yaml creation rules
            SOPS_CMD=(sops --config /dev/null encrypt --age "$RECIPIENTS" --input-type binary --output-type json "$INPUT_FILE")
        else
            SOPS_CMD=(env SOPS_AGE_KEY_FILE="$KEY_FILE" sops decrypt --input-type json --output-type binary "$INPUT_FILE")
        fi
    fi
}

printSummary()
{
    echo
    echo -e "${BLU}Operation : ${RESET}$OPERATION ($([[ "$IN_PLACE" == true ]] && echo "in place" || echo "file mode, binary"))"
    echo -e "${BLU}Input     : ${RESET}$INPUT_FILE"
    echo -e "${BLU}Output    : ${RESET}$OUTPUT_FILE"
    if [[ "$OPERATION" == "encrypt" ]]; then
        echo -e "${BLU}Recipient : ${RESET}$RECIPIENTS"
    else
        echo -e "${BLU}Key file  : ${RESET}$KEY_FILE"
    fi
    printf "${BLU}Command   :${RESET}"
    printf ' %q' "${SOPS_CMD[@]}"
    printf ' > %q\n' "$OUTPUT_FILE"
    echo
    confirm "Proceed?" || { echo "Aborted."; exit 0; }
}

# Decrypt $1 with the key file and check it matches $INPUT_FILE (byte for byte in file mode)
verifyEncrypted()
{
    local encrypted=$1
    if [[ -z "$KEY_FILE" ]]; then
        warn "No private key file available: skipping the round trip check of $OUTPUT_FILE"
        return 1
    fi
    echo "Checking that the encrypted file decrypts back to the original ..."
    if [[ "$IN_PLACE" == true ]]; then
        # Structured files are re-serialized by sops: only check that decryption succeeds
        SOPS_AGE_KEY_FILE="$KEY_FILE" sops decrypt --filename-override "$INPUT_FILE" "$encrypted" >/dev/null \
            || die "round trip check failed, the encrypted file does not decrypt with $KEY_FILE"
    else
        SOPS_AGE_KEY_FILE="$KEY_FILE" sops decrypt --input-type json --output-type binary "$encrypted" | cmp -s - "$INPUT_FILE" \
            || die "round trip check failed, $encrypted does not decrypt to $INPUT_FILE"
    fi
    return 0
}

# ===== ENCRYPT / DECRYPT FUNCTIONS =====
encryptFile()
{
    local verified=false
    if [[ "$IN_PLACE" == true ]]; then
        # Work on a copy (keeps the original's mode) and replace the original only once it is verified
        TMP_FILE="$(mktemp "${INPUT_FILE}.XXXXXX")"
        cp -p "$INPUT_FILE" "$TMP_FILE"
        "${SOPS_CMD[@]}" > "$TMP_FILE" || die "failed to encrypt $INPUT_FILE"
        verifyEncrypted "$TMP_FILE" && verified=true
        mv -f "$TMP_FILE" "$INPUT_FILE"
        TMP_FILE=""
        echo -e "File ${BLU}$INPUT_FILE${RESET} encrypted in place$([[ "$verified" == true ]] && echo " (round trip check OK)")"
        return 0
    fi

    OUTPUT_IN_PROGRESS=true
    "${SOPS_CMD[@]}" > "$OUTPUT_FILE" || die "failed to encrypt $INPUT_FILE"
    verifyEncrypted "$OUTPUT_FILE" && verified=true
    OUTPUT_IN_PROGRESS=false
    echo -e "File encrypted to ${BLU}$OUTPUT_FILE${RESET}$([[ "$verified" == true ]] && echo " (round trip check OK)")"
    echo
    deletePlainFile "$verified"
}

decryptFile()
{
    # Decrypted content may be secret (e.g. a private key): readable by the owner only
    if [[ "$IN_PLACE" == true ]]; then
        TMP_FILE="$(mktemp "${INPUT_FILE}.XXXXXX")"
        ( umask 077 && "${SOPS_CMD[@]}" > "$TMP_FILE" ) \
            || die "failed to decrypt $INPUT_FILE (is it encrypted for the age key in $KEY_FILE?)"
        chmod 600 "$TMP_FILE"
        mv -f "$TMP_FILE" "$INPUT_FILE"
        TMP_FILE=""
        echo -e "File ${BLU}$INPUT_FILE${RESET} decrypted in place (mode 0600)"
        warn "$INPUT_FILE now contains plaintext secrets - re-encrypt it before committing:"
        echo "    $(basename "$0") -e -i -f \"$INPUT_FILE\""
        return 0
    fi

    OUTPUT_IN_PROGRESS=true
    ( umask 077 && "${SOPS_CMD[@]}" > "$OUTPUT_FILE" ) \
        || die "failed to decrypt $INPUT_FILE (is it encrypted for the age key in $KEY_FILE?)"
    chmod 600 "$OUTPUT_FILE"
    OUTPUT_IN_PROGRESS=false
    echo -e "File decrypted to ${BLU}$OUTPUT_FILE${RESET} (mode 0600)"
    echo
    warn "Reminder: if $OUTPUT_FILE holds a secret, delete it as soon as you no longer need it:"
    echo "    rm -f \"$OUTPUT_FILE\""
}

deletePlainFile()
{
    local verified=$1 answer=""
    if [[ "$verified" != true ]]; then
        warn "Plain file $INPUT_FILE kept: the encryption could not be verified"
        return 0
    fi
    if [[ "$REMOVE_PLAIN" != true && "$ASSUME_YES" != true ]]; then
        read -r -p "Delete the plain file $INPUT_FILE now? [y/N]: " answer || answer=""
        [[ "$answer" =~ ^[yY]$ ]] && REMOVE_PLAIN=true
    fi
    if [[ "$REMOVE_PLAIN" == true ]]; then
        rm -f "$INPUT_FILE" || die "failed to delete $INPUT_FILE"
        echo -e "Plain file ${BLU}$INPUT_FILE${RESET} deleted"
    else
        warn "Plain file $INPUT_FILE kept: if it holds a secret, delete it once $OUTPUT_FILE is stored safely:"
        echo "    rm -f \"$INPUT_FILE\""
    fi
}

# ===== MAIN FUNCTION =====
main()
{
    trap cleanup EXIT
    parseArguments "$@"
    checkPreRequisites
    chooseOperation
    getAgeKey
    getInputFile
    getOutputFile
    buildSopsCommand
    printSummary
    if [[ "$OPERATION" == "encrypt" ]]; then
        encryptFile
    else
        decryptFile
    fi
}

# ##############################################
# #################### MAIN ####################
# ##############################################
main "$@"
