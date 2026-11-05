#!/bin/bash
# deal-coach — v2.6.1
# B2B Sales Intelligence Agent for Claude Code
# https://github.com/PratikKadam254/deal-coach

set -e

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
DIM='\033[2m'
WHITE='\033[1;37m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
type_out() {
  local text="$1"
  local delay="${2:-0.02}"
  local i=0
  while [ $i -lt ${#text} ]; do
    printf '%s' "${text:$i:1}"
    sleep "$delay"
    i=$((i + 1))
  done
  printf '\n'
}

# Waits on a background step, prints ✓ on success — ✗ and aborts on failure.
spinner() {
  local pid=$1
  local label="$2"
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${GREEN}${frames[$((i % 10))]}${RESET}  ${DIM}%s${RESET}" "$label"
    sleep 0.08
    i=$((i + 1))
  done
  local rc=0
  wait "$pid" || rc=$?
  if [ $rc -eq 0 ]; then
    printf "\r  ${GREEN}✓${RESET}  %s\n" "$label"
  else
    printf "\r  ${RED}✗${RESET}  %s\n" "$label"
    echo ""
    printf "  ${RED}Install failed.${RESET} Check your network connection and re-run:\n"
    printf "  ${DIM}curl -fsSL https://raw.githubusercontent.com/PratikKadam254/deal-coach/main/install.sh | bash${RESET}\n"
    echo ""
    exit 1
  fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear

printf "${GREEN}"
cat << 'BANNER'

   ██████╗  █████╗ ██████╗ ███████╗██╗
  ██╔════╝ ██╔══██╗██╔══██╗██╔════╝██║
  ██║  ███╗███████║██████╔╝███████╗██║
  ██║   ██║██╔══██║██╔═══╝ ╚════██║██║
  ╚██████╔╝██║  ██║██║     ███████║██║
   ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚══════╝╚═╝

BANNER
printf "${RESET}"

printf "  ${DIM}B2B Sales Coach${RESET}\n"
printf "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}\n\n"

type_out "  Installing Deal Coach..." 0.02
echo ""

# ── Variables ─────────────────────────────────────────────────────────────────
SKILL_DIR="$HOME/.claude/skills"
PROJECT_DIR="$(pwd)"
BASE_URL="https://raw.githubusercontent.com/PratikKadam254/deal-coach/main"
HOOK_PATH="$PROJECT_DIR/.claude/hooks/deal-coach-active.sh"
SETTINGS_FILE="$PROJECT_DIR/.claude/settings.json"
# $CLAUDE_PROJECT_DIR is expanded by Claude Code at runtime — survives moving/renaming the project
HOOK_CMD='bash "$CLAUDE_PROJECT_DIR/.claude/hooks/deal-coach-active.sh"'

# ── Step 1: Install Skill File ─────────────────────────────────────────────────
mkdir -p "$SKILL_DIR/deal-coach"
(
  curl -fsSL "$BASE_URL/deal-coach.md" -o "$SKILL_DIR/deal-coach/SKILL.md"
  [ -s "$SKILL_DIR/deal-coach/SKILL.md" ]
) &
spinner $! "/deal-coach  — B2B sales coach skill installed to ~/.claude/skills/"

# ── Step 2: Install Hook ───────────────────────────────────────────────────────
mkdir -p "$PROJECT_DIR/.claude/hooks"
(
  curl -fsSL "$BASE_URL/.claude/hooks/deal-coach-active.sh" -o "$HOOK_PATH"
  [ -s "$HOOK_PATH" ]
  chmod +x "$HOOK_PATH"
) &
spinner $! ".claude/hooks  — memory context hook installed and activated"

# ── Step 3: Create Memory Directory (never overwrites existing memory) ────────
mkdir -p "$PROJECT_DIR/memory/deals"
(
if [ ! -f "$PROJECT_DIR/memory/MEMORY.md" ]; then
cat > "$PROJECT_DIR/memory/MEMORY.md" << 'MEMINDEX'
---
last-updated: —
---

# Deal Coach Memory Index

## User Profile
- File: memory/user-profile.md
- Status: pending

## Offers
[No offers yet — complete onboarding to add offers]

## Active Deals
[No deals yet — start a deal to track a prospect]

## Session Log
- File: memory/session-log.md
- Sessions logged: 0
- Last session: —
MEMINDEX
fi
# Keep deal data out of version control if this project is a git repo
if [ -d "$PROJECT_DIR/.git" ]; then
  if [ ! -f "$PROJECT_DIR/.gitignore" ] || ! grep -qx "memory/" "$PROJECT_DIR/.gitignore"; then
    if [ -f "$PROJECT_DIR/.gitignore" ] && [ -n "$(tail -c1 "$PROJECT_DIR/.gitignore")" ]; then
      echo "" >> "$PROJECT_DIR/.gitignore"
    fi
    echo "memory/" >> "$PROJECT_DIR/.gitignore"
  fi
fi
) &
spinner $! "memory/        — persistent memory + deals directory ready (existing memory preserved)"

# ── Step 4: Wire settings.json (merges into existing config, never clobbers) ──
mkdir -p "$PROJECT_DIR/.claude"
SETTINGS_STATUS="registered for this project"

write_fresh_settings() {
cat > "$SETTINGS_FILE" << 'SETTINGS'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/deal-coach-active.sh\""
          }
        ]
      }
    ]
  }
}
SETTINGS
}

if [ ! -f "$SETTINGS_FILE" ]; then
  write_fresh_settings
elif grep -q "deal-coach-active.sh" "$SETTINGS_FILE"; then
  SETTINGS_STATUS="already wired — left untouched"
else
  MERGED=0
  if command -v node >/dev/null 2>&1; then
    if SETTINGS_FILE="$SETTINGS_FILE" HOOK_CMD="$HOOK_CMD" node << 'NODE'
const fs = require("fs");
const file = process.env.SETTINGS_FILE;
let settings;
try {
  settings = JSON.parse(fs.readFileSync(file, "utf8"));
} catch (e) { process.exit(1); }
if (typeof settings !== "object" || settings === null || Array.isArray(settings)) process.exit(1);
settings.hooks = settings.hooks || {};
settings.hooks.UserPromptSubmit = settings.hooks.UserPromptSubmit || [];
settings.hooks.UserPromptSubmit.push({
  matcher: "",
  hooks: [{ type: "command", command: process.env.HOOK_CMD }]
});
fs.writeFileSync(file, JSON.stringify(settings, null, 2) + "\n");
NODE
    then MERGED=1; fi
  elif command -v python3 >/dev/null 2>&1; then
    if SETTINGS_FILE="$SETTINGS_FILE" HOOK_CMD="$HOOK_CMD" python3 << 'PY'
import json, os, sys
file = os.environ["SETTINGS_FILE"]
try:
    with open(file) as f:
        settings = json.load(f)
except Exception:
    sys.exit(1)
if not isinstance(settings, dict):
    sys.exit(1)
settings.setdefault("hooks", {}).setdefault("UserPromptSubmit", []).append({
    "matcher": "",
    "hooks": [{"type": "command", "command": os.environ["HOOK_CMD"]}]
})
with open(file, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PY
    then MERGED=1; fi
  fi
  if [ $MERGED -eq 1 ]; then
    SETTINGS_STATUS="merged into existing settings"
  else
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"
    write_fresh_settings
    SETTINGS_STATUS="rewritten — previous config saved to settings.json.bak"
    printf "  ${YELLOW}!${RESET}  ${DIM}Existing settings.json could not be merged automatically.${RESET}\n"
    printf "     ${DIM}Your previous config was backed up to .claude/settings.json.bak —${RESET}\n"
    printf "     ${DIM}re-add any custom hooks or permissions from it manually.${RESET}\n"
  fi
fi
printf "  ${GREEN}✓${RESET}  .claude/settings.json  — %s\n" "$SETTINGS_STATUS"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
printf "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}\n"
echo ""
type_out "  Done. Open Claude Code in this directory." 0.02
echo ""
printf "  ${WHITE}/deal-coach${RESET}${DIM}  →  first run starts onboarding${RESET}\n"
printf "  ${DIM}subsequent runs load your offers and session history automatically${RESET}\n"
echo ""
