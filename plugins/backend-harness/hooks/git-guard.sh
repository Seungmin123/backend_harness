#!/usr/bin/env bash
# PreToolUse hook — matcher: Bash (등록: backend-harness 플러그인 hooks/hooks.json)
#
# 모든 Bash 호출을 대상으로 위험한 git / DB 명령을 2단계로 가드한다.
#   🚫 즉시 차단 (permissionDecision: deny) — 되돌릴 수 없거나 데이터 유실 위험이 큰 명령
#   ❓ 확인 후 진행 (permissionDecision: ask) — 정상 사용도 있지만 위험할 수 있는 명령
#
# pre-commit.sh(git commit 시점 검사)와는 별개로, 모든 Bash 커맨드를 대상으로 먼저 개입한다.
set -uo pipefail

input="$(cat)"

deny() {
  local reason="$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(printf '%s' "$reason" | jq -Rs .)"
  exit 0
}

ask() {
  local reason="$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' \
    "$(printf '%s' "$reason" | jq -Rs .)"
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  echo "[git-guard] 경고: jq가 없어 위험 명령 가드가 동작하지 않습니다 (brew install jq). 파괴적 git/DB 명령이 차단되지 않는 상태입니다." >&2
  exit 0
fi

command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"

if [[ -z "$command_str" ]]; then
  exit 0
fi

shopt -s nocasematch

# ── 🚫 즉시 차단 ─────────────────────────────────────────────
if [[ "$command_str" =~ git[[:space:]]+reset[[:space:]]+.*--hard ]]; then
  deny "[git-guard] git reset --hard는 커밋되지 않은 변경을 영구히 삭제합니다. 필요하면 사용자가 직접 실행하세요."
fi

if [[ "$command_str" =~ git[[:space:]]+push.*(--force|[[:space:]]-f([[:space:]]|$)) ]]; then
  deny "[git-guard] 강제 push는 원격 히스토리를 덮어써 팀원의 작업을 유실시킬 수 있습니다. 필요하면 사용자가 직접 실행하세요."
fi

if [[ "$command_str" =~ git[[:space:]]+clean[[:space:]]+.*-[a-z]*f ]]; then
  deny "[git-guard] git clean -f는 추적되지 않는 파일을 영구히 삭제합니다. 필요하면 사용자가 직접 실행하세요."
fi

if [[ "$command_str" =~ git[[:space:]]+stash[[:space:]]+clear ]]; then
  deny "[git-guard] git stash clear는 모든 stash를 영구히 삭제합니다. 필요하면 사용자가 직접 실행하세요."
fi

if [[ "$command_str" =~ git[[:space:]]+filter-branch ]]; then
  deny "[git-guard] git filter-branch는 히스토리를 재작성합니다. 필요하면 사용자가 직접 실행하세요."
fi

if [[ "$command_str" =~ rm[[:space:]]+.*-[a-z]*r[a-z]*f|rm[[:space:]]+.*-[a-z]*f[a-z]*r ]]; then
  deny "[git-guard] rm -rf는 파일을 영구히 삭제합니다. 필요하면 사용자가 직접 실행하세요."
fi

if [[ "$command_str" =~ (drop[[:space:]]+table|drop[[:space:]]+database|truncate[[:space:]]+table) ]]; then
  deny "[git-guard] DROP/TRUNCATE는 되돌릴 수 없는 스키마·데이터 파괴 명령입니다. 필요하면 사용자가 직접 실행하세요."
fi

if [[ "$command_str" =~ flyway[:_[:space:]]*clean ]]; then
  deny "[git-guard] flyway clean은 스키마의 모든 객체를 삭제합니다. 필요하면 사용자가 직접 실행하세요."
fi

if [[ "$command_str" =~ liquibase[:_[:space:]]*dropall ]]; then
  deny "[git-guard] liquibase dropAll은 스키마의 모든 객체를 삭제합니다. 필요하면 사용자가 직접 실행하세요."
fi

# ── ❓ 확인 후 진행 ───────────────────────────────────────────
if [[ "$command_str" =~ git[[:space:]]+commit[[:space:]]+.*--amend ]]; then
  ask "[git-guard] commit --amend는 기존 커밋을 덮어씁니다. 이미 push된 커밋이면 문제가 될 수 있습니다. 진행할까요?"
fi

if [[ "$command_str" =~ git[[:space:]]+rebase ]]; then
  ask "[git-guard] rebase는 히스토리를 재작성합니다. 공유 브랜치라면 주의가 필요합니다. 진행할까요?"
fi

if [[ "$command_str" =~ git[[:space:]]+branch[[:space:]]+.*-D ]]; then
  ask "[git-guard] branch -D는 병합되지 않은 브랜치도 강제 삭제합니다. 진행할까요?"
fi

if [[ "$command_str" =~ git[[:space:]]+checkout[[:space:]]+--([[:space:]]|$) ]] \
   || { [[ "$command_str" =~ git[[:space:]]+restore ]] && [[ ! "$command_str" =~ --staged ]]; }; then
  ask "[git-guard] 이 명령은 로컬 변경사항을 폐기합니다. 진행할까요?"
fi

if [[ "$command_str" =~ git[[:space:]]+push[[:space:]]+.*--delete ]]; then
  ask "[git-guard] 원격 브랜치를 삭제합니다. 진행할까요?"
fi

if [[ "$command_str" =~ git[[:space:]]+stash[[:space:]]+drop ]]; then
  ask "[git-guard] stash 항목을 영구히 삭제합니다. 진행할까요?"
fi

if [[ "$command_str" =~ flyway[:_[:space:]]*migrate ]] || [[ "$command_str" =~ liquibase[:_[:space:]]*update ]]; then
  ask "[git-guard] 실제 DB에 마이그레이션을 적용합니다. 대상 환경(로컬/개발/운영)을 확인했나요? 운영 DB 적용은 개발자가 직접 실행하는 것을 권장합니다."
fi

exit 0
