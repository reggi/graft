#!/usr/bin/env bash
# Integration tests for graft
set -euo pipefail

GRAFT="$(cd "$(dirname "$0")/.." && pwd)/graft"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_contains() {
  local label="$1" path="$2" pattern="$3"
  if grep -qF "$pattern" "$path" 2>/dev/null; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label (pattern '$pattern' not found in $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_contains() {
  local label="$1" path="$2" pattern="$3"
  if ! grep -qF "$pattern" "$path" 2>/dev/null; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label (pattern '$pattern' found in $path but should not be)"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_code() {
  local label="$1" expected="$2"
  shift 2
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  assert_eq "$label" "$expected" "$actual"
}

# --- Setup source repo ---

SOURCE_DIR="$TEST_DIR/source"
mkdir -p "$SOURCE_DIR"
cd "$SOURCE_DIR"
git init -q
echo '{"strict": true}' > tsconfig.json
echo 'module.exports = {}' > eslintrc.js
mkdir -p src
echo 'console.log("hello")' > src/index.js
git add -A && git commit -q -m "initial"
SOURCE_SHA=$(git rev-parse HEAD)

# --- Test: init ---

echo "=== graft init ==="
CONSUMER="$TEST_DIR/consumer1"
mkdir -p "$CONSUMER" && cd "$CONSUMER" && git init -q

$GRAFT init >/dev/null 2>&1
assert_file_exists "creates .graft" ".graft"
assert_eq ".graft has empty grafts array" "0" "$(jq '.grafts | length' .graft)"

# init fails if .graft exists
assert_exit_code "init fails if .graft exists" 1 $GRAFT init

# --- Test: add (GitHub blob URL parsing) ---

echo "=== graft add ==="
CONSUMER="$TEST_DIR/consumer2"
mkdir -p "$CONSUMER" && cd "$CONSUMER" && git init -q

$GRAFT add https://github.com/github/choosealicense.com/blob/gh-pages/_licenses/artistic-2.0.txt >/dev/null 2>&1
assert_file_exists "add creates .graft" ".graft"
assert_eq "add sets source" "https://github.com/github/choosealicense.com.git" \
  "$(jq -r '.grafts[0].source' .graft)"
assert_eq "add sets ref" "gh-pages" "$(jq -r '.grafts[0].ref' .graft)"
assert_eq "add sets src" "_licenses/artistic-2.0.txt" "$(jq -r '.grafts[0].files[0].src' .graft)"
assert_eq "add sets name" "choosealicense.com" "$(jq -r '.grafts[0].name' .graft)"

# Add another file to same source
$GRAFT add https://github.com/github/choosealicense.com/blob/gh-pages/_licenses/mit.txt >/dev/null 2>&1
assert_eq "add groups files under same source" "1" "$(jq '.grafts | length' .graft)"
assert_eq "second file added" "2" "$(jq '.grafts[0].files | length' .graft)"

# Add with --vendor
$GRAFT add --vendor https://github.com/github/choosealicense.com/blob/gh-pages/_licenses/isc.txt >/dev/null 2>&1
assert_eq "vendor flag set" "true" "$(jq '.grafts[0].files[2].vendor' .graft)"

# Add with custom dest
$GRAFT add https://github.com/github/choosealicense.com/blob/gh-pages/_licenses/apache-2.0.txt licenses/apache.txt >/dev/null 2>&1
assert_eq "custom dest set" "licenses/apache.txt" \
  "$(jq -r '.grafts[0].files[3].dest' .graft)"

# --- Test: update + install with local source ---

echo "=== graft update (local source) ==="
CONSUMER="$TEST_DIR/consumer3"
mkdir -p "$CONSUMER" && cd "$CONSUMER" && git init -q

cat > .graft <<EOF
{
  "grafts": [
    {
      "name": "shared",
      "source": "file://${SOURCE_DIR}",
      "ref": "HEAD",
      "files": [
        { "src": "tsconfig.json", "vendor": true },
        { "src": "eslintrc.js", "dest": "config/eslintrc.js" },
        { "src": "src/index.js", "dest": "lib/index.js" }
      ]
    }
  ]
}
EOF

$GRAFT update >/dev/null 2>&1
assert_file_exists "lockfile created" ".graft.lock"
assert_file_exists "tsconfig.json synced" "tsconfig.json"
assert_file_exists "eslintrc.js synced to dest" "config/eslintrc.js"
assert_file_exists "nested file synced" "lib/index.js"
assert_eq "lockfile has resolved SHA" "$SOURCE_SHA" \
  "$(jq -r '.grafts[0].resolved_sha' .graft.lock)"

# --- Test: gitignore management ---

echo "=== gitignore management ==="
assert_file_exists ".gitignore created" ".gitignore"
assert_file_contains "non-vendor file is gitignored" ".gitignore" "config/eslintrc.js"
assert_file_contains "non-vendor nested file is gitignored" ".gitignore" "lib/index.js"
assert_file_not_contains "vendor file is NOT gitignored" ".gitignore" "tsconfig.json"
assert_file_contains "gitignore has marker" ".gitignore" "# managed by graft"

# --- Test: status ---

echo "=== graft status ==="
assert_exit_code "status exits 0 when in sync" 0 $GRAFT status

echo "changed" > tsconfig.json
assert_exit_code "status exits 1 when modified" 1 $GRAFT status

# --- Test: install restores files ---

echo "=== graft install ==="
rm -f tsconfig.json config/eslintrc.js lib/index.js
$GRAFT install >/dev/null 2>&1
assert_file_exists "install restores tsconfig.json" "tsconfig.json"
assert_file_exists "install restores eslintrc.js" "config/eslintrc.js"
assert_file_exists "install restores lib/index.js" "lib/index.js"
assert_exit_code "status ok after install" 0 $GRAFT status

# --- Test: local modification protection ---

echo "=== local modification protection ==="
echo "local change" > tsconfig.json
$GRAFT update >/dev/null 2>&1
# File should NOT be overwritten (warning printed)
assert_eq "locally modified file preserved" "local change" "$(cat tsconfig.json)"

# Force overwrite
$GRAFT update --force >/dev/null 2>&1
assert_eq "force overwrites local changes" '{"strict": true}' "$(cat tsconfig.json)"

# --- Test: check (CI mode) ---

echo "=== graft check ==="
assert_exit_code "check passes when in sync" 0 $GRAFT check
echo "drift" > tsconfig.json
assert_exit_code "check fails when out of sync" 1 $GRAFT check

# --- Test: diff ---

echo "=== graft diff ==="
echo "different content" > tsconfig.json
DIFF_OUTPUT=$($GRAFT diff 2>&1)
assert_file_contains "diff shows source label" <(echo "$DIFF_OUTPUT") "source:tsconfig.json"
assert_file_contains "diff shows changes" <(echo "$DIFF_OUTPUT") "different content"

# --- Test: update single graft by name ---

echo "=== graft update <name> ==="
$GRAFT update --force >/dev/null 2>&1  # restore first
echo "modified" > tsconfig.json
$GRAFT update shared --force >/dev/null 2>&1
assert_eq "named update restores file" '{"strict": true}' "$(cat tsconfig.json)"

# --- Test: path validation ---

echo "=== path validation ==="
CONSUMER="$TEST_DIR/consumer4"
mkdir -p "$CONSUMER" && cd "$CONSUMER" && git init -q

cat > .graft <<EOF
{
  "grafts": [
    {
      "name": "bad",
      "source": "file://${SOURCE_DIR}",
      "ref": "HEAD",
      "files": [
        { "src": "tsconfig.json", "dest": "../escape.json" }
      ]
    }
  ]
}
EOF
assert_exit_code "rejects path traversal" 1 $GRAFT update

# --- Test: duplicate destination detection ---

echo "=== duplicate destination detection ==="
CONSUMER="$TEST_DIR/consumer5"
mkdir -p "$CONSUMER" && cd "$CONSUMER" && git init -q

cat > .graft <<EOF
{
  "grafts": [
    {
      "name": "a",
      "source": "file://${SOURCE_DIR}",
      "ref": "HEAD",
      "files": [
        { "src": "tsconfig.json", "dest": "same.json" }
      ]
    },
    {
      "name": "b",
      "source": "file://${SOURCE_DIR}",
      "ref": "HEAD",
      "files": [
        { "src": "eslintrc.js", "dest": "same.json" }
      ]
    }
  ]
}
EOF
assert_exit_code "rejects duplicate destinations" 1 $GRAFT update

# --- Test: version and help ---

echo "=== version and help ==="
VERSION=$($GRAFT version 2>&1)
assert_eq "version output" "graft 0.1.0" "$VERSION"
assert_exit_code "help exits 0" 0 $GRAFT help
assert_exit_code "unknown command exits 1" 1 $GRAFT notacommand

# --- Summary ---

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
echo "================================"

[[ "$FAIL" -eq 0 ]] || exit 1
