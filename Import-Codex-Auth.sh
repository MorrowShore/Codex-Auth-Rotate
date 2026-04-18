#!/usr/bin/env bash
# ==============================================================================
# save-codex-account.sh
#
# Reads the current ~/.codex/auth.json and saves a copy into the accounts/
# folder used by switch-codex-auth.sh.
#
# Run this after logging into a new account in Codex, before switching away.
# ==============================================================================

set -euo pipefail

AUTH_FILE="$HOME/.codex/auth.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNTS_DIR="$SCRIPT_DIR/accounts"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

echo ""
echo -e "  ${GRAY}Auth source : $AUTH_FILE${NC}"
echo -e "  ${GRAY}Accounts dir: $ACCOUNTS_DIR${NC}"
echo ""

# ── CHECK SOURCE FILE ──────────────────────────────────────────────────────────

if [ ! -f "$AUTH_FILE" ]; then
    echo -e "  ${RED}[!] No auth.json found at: $AUTH_FILE${NC}"
    echo -e "  ${RED}    Log into Codex first, then run this script.${NC}"
    echo ""
    exit 1
fi

# ── DECODE EMAIL FROM JWT ──────────────────────────────────────────────────────

DETECTED_EMAIL=""
SUGGESTION=""

if command -v python3 &>/dev/null; then
    DETECTED_EMAIL=$(python3 - "$AUTH_FILE" <<'PYEOF'
import sys, json, base64
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    token = data.get("tokens", {}).get("id_token", "")
    if token:
        payload = token.split(".")[1]
        payload += "=" * (4 - len(payload) % 4)
        decoded = json.loads(base64.urlsafe_b64decode(payload))
        print(decoded.get("email", ""))
except Exception:
    pass
PYEOF
    ) 2>/dev/null || true
fi

echo -e "  ${CYAN}Current auth.json${NC}"
if [ -n "$DETECTED_EMAIL" ]; then
    echo -e "  Detected email: $DETECTED_EMAIL"
    SUGGESTION="${DETECTED_EMAIL%%@*}"
else
    echo -e "  ${GRAY}(Could not decode email from token)${NC}"
fi
echo ""

# ── ENSURE ACCOUNTS FOLDER EXISTS ─────────────────────────────────────────────

mkdir -p "$ACCOUNTS_DIR"

# ── LIST EXISTING ACCOUNTS ─────────────────────────────────────────────────────

mapfile -t EXISTING < <(find "$ACCOUNTS_DIR" -maxdepth 1 -name '*.json' | sort)

if [ ${#EXISTING[@]} -gt 0 ]; then
    echo -e "  ${GRAY}Existing accounts:${NC}"
    for f in "${EXISTING[@]}"; do
        echo -e "  ${GRAY}  $(basename "$f")${NC}"
    done
    echo ""
fi

# ── PROMPT FOR NAME ────────────────────────────────────────────────────────────

echo -e "  ${YELLOW}Enter a short name for this account (e.g. Personal, CompanyA).${NC}"
if [ -n "$SUGGESTION" ]; then
    echo -e "  ${GRAY}Press Enter to use detected name: $SUGGESTION${NC}"
fi
echo ""
printf "  Name: "
read -r INPUT

if [ -z "$INPUT" ]; then
    if [ -n "$SUGGESTION" ]; then
        INPUT="$SUGGESTION"
    else
        echo -e "  ${RED}[!] No name entered. Aborting.${NC}"
        exit 1
    fi
fi

# Strip characters that are problematic in filenames
SAFE_NAME=$(echo "$INPUT" | tr -d '/:*?"<>|\\' | xargs)

# ── DETERMINE NEXT PREFIX NUMBER ───────────────────────────────────────────────

MAX_PREFIX=0
for f in "${EXISTING[@]}"; do
    BASE=$(basename "$f")
    if [[ "$BASE" =~ ^([0-9]+)_ ]]; then
        N="${BASH_REMATCH[1]#0}"  # strip leading zeros for arithmetic
        N="${N:-0}"
        if [ "$N" -gt "$MAX_PREFIX" ]; then
            MAX_PREFIX=$N
        fi
    fi
done
NEXT_PREFIX=$(printf "%02d" $((MAX_PREFIX + 1)))
FILE_NAME="${NEXT_PREFIX}_${SAFE_NAME}.json"
DEST_PATH="$ACCOUNTS_DIR/$FILE_NAME"

# ── CHECK FOR DUPLICATE ────────────────────────────────────────────────────────

for f in "${EXISTING[@]}"; do
    EXISTING_NAME=$(basename "$f" .json | sed 's/^[0-9]*_//')
    if [ "$EXISTING_NAME" = "$SAFE_NAME" ]; then
        echo ""
        echo -e "  ${YELLOW}[!] An account named '$SAFE_NAME' already exists: $(basename "$f")${NC}"
        printf "  Overwrite it? (y/N): "
        read -r CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "  Aborted."
            exit 0
        fi
        DEST_PATH="$f"
        FILE_NAME=$(basename "$f")
        break
    fi
done

# ── COPY ───────────────────────────────────────────────────────────────────────

cp "$AUTH_FILE" "$DEST_PATH"

echo ""
if [ -f "$DEST_PATH" ]; then
    echo -e "  ${GREEN}OK  Saved as: $FILE_NAME${NC}"
    echo -e "  ${GRAY}    Full path: $DEST_PATH${NC}"
else
    echo -e "  ${RED}[!] Something went wrong — file not found after copy.${NC}"
    echo -e "  ${RED}    Tried to write to: $DEST_PATH${NC}"
    exit 1
fi
echo ""
