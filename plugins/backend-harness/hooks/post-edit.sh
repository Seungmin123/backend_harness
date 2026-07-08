#!/usr/bin/env bash
# PostToolUse hook — matcher: Edit|Write (등록: backend-harness 플러그인 hooks/hooks.json)
#
# .java 파일 편집 후 대응하는 테스트를 자동 실행한다. CLAUDE.md에 명시된 대로
# .java 파일 변경만 감지하며, 테스트 실패 시에도 작업을 차단하지 않고 경고만 출력한다(exit 0 고정).
#
# 체이닝 실행 중(api-developer → qa-engineer) 경고: 이 스크립트는 체이닝 여부를 알 수 없으므로
# 항상 경고를 출력한다 — 체이닝 중이면 CLAUDE.md 지시에 따라 오케스트레이터(모델)가 이 경고를
# 무시하고 계속 진행한다. 이는 이 스크립트가 아니라 CLAUDE.md 레벨의 규칙이다.
set -uo pipefail

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "[post-edit] jq가 설치되어 있지 않아 훅을 건너뜁니다 (brew install jq 등으로 설치)." >&2
  exit 0
fi

file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"

# .java 파일 변경만 감지. application.yml 등 비-.java 설정 변경은 CLAUDE.md에 따라 수동 검증 필요.
if [[ -z "$file_path" || "$file_path" != *.java ]]; then
  exit 0
fi

project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$project_root" || exit 0

if [[ -x ./mvnw ]]; then
  build_tool="maven"
elif [[ -x ./gradlew ]]; then
  build_tool="gradle"
else
  exit 0
fi

if [[ "$file_path" == *"/src/test/"* ]]; then
  test_file="$file_path"
else
  test_file="${file_path/\/src\/main\//\/src\/test\/}"
  test_file="${test_file%.java}Test.java"
fi

if [[ ! -f "$test_file" ]]; then
  echo "[post-edit] 경고: $file_path 에 대응하는 테스트 파일이 없습니다 ($test_file)." >&2
  echo "[post-edit] qa-engineer 에이전트 호출을 검토하세요." >&2
  exit 0
fi

# "src/test/java/" 가 경로 어디에 있든(단일 모듈 루트든, 멀티모듈 서브모듈 하위든) 그 뒤를
# 패키지 경로로 취급한다. 단순 프리픽스 제거(${test_file#src/test/java/})는 멀티모듈 레이아웃
# (예: service-a/src/test/java/...)에서 매치되지 않아 잘못된 FQCN을 만드는 문제가 있었다.
if [[ "$test_file" == *"src/test/java/"* ]]; then
  rel_test_path="${test_file##*src/test/java/}"
  module_dir="${test_file%%src/test/java/*}"
  module_dir="${module_dir%/}"
else
  rel_test_path="$test_file"
  module_dir=""
fi
test_class="$(basename "$rel_test_path" .java)"
package_path="$(dirname "$rel_test_path")"
if [[ "$package_path" == "." ]]; then
  test_fqcn="$test_class"
else
  test_fqcn="$(echo "$package_path" | tr '/' '.').${test_class}"
fi

if [[ "$build_tool" == "maven" ]]; then
  run_cmd=(./mvnw -q -Dtest="$test_fqcn" test)
  if [[ -n "$module_dir" ]]; then
    # 서브모듈에 있는 테스트면 루트 mvnw에 -pl 로 해당 모듈만 지정한다.
    run_cmd=(./mvnw -q -pl "$module_dir" -Dtest="$test_fqcn" test)
  fi
else
  gradle_task="test"
  if [[ -n "$module_dir" ]]; then
    # 멀티프로젝트면 디렉터리 경로를 Gradle 프로젝트 경로(:a:b:test)로 변환해 해당 모듈만 실행한다.
    gradle_task=":$(echo "$module_dir" | tr '/' ':'):test"
  fi
  run_cmd=(./gradlew -q "$gradle_task" --tests "$test_fqcn")
fi

log_file="$(mktemp -t post-edit-test.XXXXXX)"
echo "[post-edit] $test_fqcn 실행 중..." >&2

if "${run_cmd[@]}" > "$log_file" 2>&1; then
  echo "[post-edit] PASS: $test_fqcn" >&2
else
  echo "[post-edit] 경고: $test_fqcn 실패 (작업은 차단하지 않음)." >&2
  tail -n 20 "$log_file" >&2
fi
rm -f "$log_file"

exit 0
