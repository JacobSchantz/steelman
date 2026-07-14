#!/bin/bash
# Walk up from SRCROOT to find the git repo root
REPO_ROOT="${SRCROOT}"
while [ ! -d "${REPO_ROOT}/.git" ] && [ "${REPO_ROOT}" != "/" ]; do
  REPO_ROOT="$(dirname "${REPO_ROOT}")"
done

if [ "${REPO_ROOT}" = "/" ]; then
  REPO_ROOT="$(dirname "${SRCROOT}")"
fi

COMMIT=$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
FULL_COMMIT=$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo "unknown")
BRANCH=$(git -C "${REPO_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
COMMIT_MSG=$(git -C "${REPO_ROOT}" log -1 --format="%s" 2>/dev/null || echo "unknown")
COMMIT_COUNT=$(git -C "${REPO_ROOT}" rev-list --count HEAD 2>/dev/null || echo "0")

escape_swift() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
COMMIT_MSG=$(escape_swift "${COMMIT_MSG}")
BRANCH=$(escape_swift "${BRANCH}")

mkdir -p "${SRCROOT}/Generated"
cat > "${SRCROOT}/Generated/GitInfo.swift" << EOF
// Auto-generated — do not edit
enum GitInfo {
    static let shortHash = "${COMMIT}"
    static let fullHash = "${FULL_COMMIT}"
    static let branch = "${BRANCH}"
    static let lastCommitMessage = "${COMMIT_MSG}"
    static let commitCount = "${COMMIT_COUNT}"
}
EOF
