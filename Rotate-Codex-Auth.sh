#!/usr/bin/env bash
# ==============================================================================
# switch-codex-auth.sh
#
# Cycles through Codex accounts by swapping ~/.codex/auth.json.
#
# SETUP:
#   1. Place this script anywhere permanent, e.g. ~/tools/codex-switch/
#   2. Create a subfolder called "accounts/" next to this script.
#   3. Copy your auth.json for each account into that folder, named:
#        accounts/01_Personal.json
#        accounts/02_CompanyA.json
#        accounts/03_CompanyB.json
#      (Files are cycled in alphabetical order, so the prefix controls order.)
#   4. Make executable: chmod +x switch-codex-auth.sh
#   5. Run: ./switch-codex-auth.sh
# ==============================================================================

set -euo pipefail

AUTH_FILE="$HOME/.codex/auth.json"
CONFIG_FILE="$HOME/.codex/config.toml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCOUNTS_DIR="$SCRIPT_DIR/accounts"
STATE_FILE="$SCRIPT_DIR/.auth_state"

# ── COLOURS ────────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

echo ""
echo -e "  ${GRAY}Script dir  : $SCRIPT_DIR${NC}"
echo -e "  ${GRAY}Accounts dir: $ACCOUNTS_DIR${NC}"
echo -e "  ${GRAY}Auth file   : $AUTH_FILE${NC}"
echo ""

# ── ENSURE ~/.codex EXISTS ─────────────────────────────────────────────────────

mkdir -p "$HOME/.codex"

# ── ENSURE config.toml HAS cli_auth_credentials_store = "file" ────────────────

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "  ${YELLOW}[!] config.toml not found — creating it.${NC}"
    touch "$CONFIG_FILE"
fi

if ! grep -qE '^\s*cli_auth_credentials_store\s*=' "$CONFIG_FILE"; then
    echo -e "  ${CYAN}[+] Adding cli_auth_credentials_store = \"file\" to config.toml${NC}"
    echo '' >> "$CONFIG_FILE"
    echo 'cli_auth_credentials_store = "file"' >> "$CONFIG_FILE"
elif ! grep -qE '^\s*cli_auth_credentials_store\s*=\s*"file"' "$CONFIG_FILE"; then
    echo -e "  ${YELLOW}[!] cli_auth_credentials_store is not \"file\" — fixing.${NC}"
    # Use temp file for in-place sed (compatible with both GNU and BSD sed)
    sed -E 's|^(\s*cli_auth_credentials_store\s*=).*|\1 "file"|' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
fi

# ── LOAD ACCOUNT FILES ─────────────────────────────────────────────────────────

if [ ! -d "$ACCOUNTS_DIR" ]; then
    mkdir -p "$ACCOUNTS_DIR"
    echo -e "  ${YELLOW}[!] Created accounts/ folder at: $ACCOUNTS_DIR${NC}"
    echo -e "  ${YELLOW}    Add one .json file per account, e.g. 01_Personal.json${NC}"
    echo ""
    exit 0
fi

# Read account files into an array, sorted alphabetically
mapfile -t ACCOUNTS < <(find "$ACCOUNTS_DIR" -maxdepth 1 -name '*.json' | sort)

if [ ${#ACCOUNTS[@]} -eq 0 ]; then
    echo -e "  ${RED}[!] No .json files found in: $ACCOUNTS_DIR${NC}"
    echo -e "  ${RED}    Run save-codex-account.sh to add accounts.${NC}"
    echo ""
    exit 1
fi

echo -e "  ${GRAY}Found ${#ACCOUNTS[@]} account(s):${NC}"
for a in "${ACCOUNTS[@]}"; do
    echo -e "  ${GRAY}  $(basename "$a")${NC}"
done
echo ""

# ── SAVE CURRENT LIVE AUTH BACK INTO ITS ACCOUNT FILE ─────────────────────────

CURRENT_INDEX=-1
if [ -f "$STATE_FILE" ]; then
    STORED=$(cat "$STATE_FILE" | tr -d '[:space:]')
    if [[ "$STORED" =~ ^[0-9]+$ ]]; then
        CURRENT_INDEX=$STORED
    fi
fi

if [ "$CURRENT_INDEX" -ge 0 ] 2>/dev/null && \
   [ "$CURRENT_INDEX" -lt "${#ACCOUNTS[@]}" ] && \
   [ -f "$AUTH_FILE" ]; then
    CURRENT_ACCOUNT="${ACCOUNTS[$CURRENT_INDEX]}"
    cp "$AUTH_FILE" "$CURRENT_ACCOUNT"
    LABEL=$(basename "$CURRENT_ACCOUNT" .json | sed 's/^[0-9]*_//')
    echo -e "  ${GRAY}[~] Saved refreshed tokens for: $LABEL${NC}"
fi

# ── DETERMINE NEXT ACCOUNT ─────────────────────────────────────────────────────

NEXT_INDEX=$(( (CURRENT_INDEX + 1) % ${#ACCOUNTS[@]} ))
NEXT_ACCOUNT="${ACCOUNTS[$NEXT_INDEX]}"
NEXT_NAME=$(basename "$NEXT_ACCOUNT" .json | sed 's/^[0-9]*_//')

# ── BACK UP AND SWAP auth.json ─────────────────────────────────────────────────

if [ -f "$AUTH_FILE" ]; then
    cp "$AUTH_FILE" "$AUTH_FILE.bak"
fi

cp "$NEXT_ACCOUNT" "$AUTH_FILE"

# ── SAVE STATE ─────────────────────────────────────────────────────────────────

echo "$NEXT_INDEX" > "$STATE_FILE"

# ── DECODE EMAIL FROM JWT ──────────────────────────────────────────────────────

FRIENDLY_ID="$NEXT_NAME"

if command -v python3 &>/dev/null; then
    EMAIL=$(python3 - "$NEXT_ACCOUNT" <<'PYEOF'
import sys, json, base64
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    token = data.get("tokens", {}).get("id_token", "")
    if token:
        payload = token.split(".")[1]
        # pad to multiple of 4
        payload += "=" * (4 - len(payload) % 4)
        decoded = json.loads(base64.urlsafe_b64decode(payload))
        print(decoded.get("email", ""))
except Exception:
    pass
PYEOF
    ) 2>/dev/null || true
    if [ -n "$EMAIL" ]; then
        FRIENDLY_ID="$NEXT_NAME ($EMAIL)"
    fi
fi

# ── REPORT ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "  ${GREEN}OK  Switched to account $((NEXT_INDEX + 1)) of ${#ACCOUNTS[@]}: $FRIENDLY_ID${NC}"
echo -e "  ${GRAY}    File: $(basename "$NEXT_ACCOUNT")${NC}"
echo ""
