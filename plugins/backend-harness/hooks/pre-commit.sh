#!/usr/bin/env bash
# PreToolUse hook — matcher: Bash (등록: backend-harness 플러그인 hooks/hooks.json)
#
# Bash 호출 커맨드가 git commit인 경우에만 개입한다. .env 스테이징 감지 → Checkstyle
# (프로젝트 전체 기준) → 하드코딩 시크릿 탐지(스테이징된 변경분 기준) 순서로 실행하고,
# 하나라도 실패하면 커밋을 차단한다.
#
# exit 0 = 허용, exit 2 = 차단 (stderr 메시지가 Claude에게 차단 사유로 전달됨)
set -uo pipefail

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"

if [[ ! "$command_str" =~ git[[:space:]]+commit ]]; then
  exit 0
fi

project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$project_root" || exit 0

fail=0

# 1) .env 스테이징 감지
if git diff --cached --name-only 2>/dev/null | grep -qE '(^|/)\.env(\..*)?$'; then
  echo "[pre-commit] 차단: .env 파일이 스테이징되어 있습니다. git reset으로 언스테이지하세요." >&2
  fail=1
fi

# 2) Checkstyle — 스테이징된 파일만이 아닌 프로젝트 전체 기준 (CLAUDE.md 명시 주의사항)
if [[ -x ./mvnw ]]; then
  checkstyle_log="$(mktemp -t pre-commit-checkstyle.XXXXXX)"
  if ! ./mvnw -q checkstyle:check > "$checkstyle_log" 2>&1; then
    echo "[pre-commit] 차단: Checkstyle 위반이 있습니다 (프로젝트 전체 기준)." >&2
    echo "[pre-commit] 수정하지 않은 파일의 기존 위반도 커밋을 막을 수 있습니다. ./mvnw checkstyle:check 로 전체 현황을 먼저 확인하세요." >&2
    tail -n 30 "$checkstyle_log" >&2
    fail=1
  fi
  rm -f "$checkstyle_log"
fi

# 3) 하드코딩 시크릿 탐지 — 스테이징된 변경분(diff) 기준 (security-checker.md 패턴과 동일)
secret_pattern='password[[:space:]]*=[[:space:]]*["'"'"'][^$\{]|api[._-]?key[[:space:]]*=[[:space:]]*["'"'"'][^$\{]|secret[[:space:]]*=[[:space:]]*["'"'"'][^$\{]|-----BEGIN (RSA |EC )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}'
if git diff --cached 2>/dev/null | grep -qE "$secret_pattern"; then
  echo "[pre-commit] 차단: 스테이징된 변경분에서 하드코딩된 시크릿으로 의심되는 패턴이 발견되었습니다." >&2
  fail=1
fi

if [[ "$fail" -eq 1 ]]; then
  exit 2
fi

exit 0
