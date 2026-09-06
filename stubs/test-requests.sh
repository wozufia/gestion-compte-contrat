#!/usr/bin/env bash

set -euo pipefail

CONTRACT_FILE="${CONTRACT_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gestion-compte-contrat.yml}"
SERVER_PATH="${SERVER_PATH:-$(ruby -e 'require "yaml"; puts YAML.load_file(ARGV[0]).dig("servers", 0, "url") || "/api/comptes/v1"' "${CONTRACT_FILE}")}"
BASE_HOST="${BASE_HOST:-http://localhost:8081}"
TOKEN="${TOKEN:-stub-access-token}"
REQUESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/requests"
RESPONSES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/responses"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_expect() {
  local name="$1"
  local expected="$2"
  shift 2
  TOTAL_TESTS=$((TOTAL_TESTS + 1))

  local body_file
  body_file="$(mktemp)"
  local status_code
  if ! status_code=$("$@" -sS -o "${body_file}" -w "%{http_code}"); then
    echo "[FAIL] ${name}: request execution failed"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    rm -f "${body_file}"
    return
  fi

  if [[ "${status_code}" != "${expected}" ]]; then
    echo "[FAIL] ${name}: got ${status_code}, expected ${expected}"
    cat "${body_file}"
    echo
    FAILED_TESTS=$((FAILED_TESTS + 1))
    rm -f "${body_file}"
    return
  fi

  echo "[PASS] ${name}: ${status_code}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
  if [[ -s "${body_file}" ]]; then
    cat "${body_file}"
    echo
  fi
  rm -f "${body_file}"
}

request_file() {
  local method="$1"
  local path="$2"
  echo "${REQUESTS_DIR}/${method}-${path}.json"
}

response_file() {
  local method="$1"
  local path="$2"
  echo "${RESPONSES_DIR}/${method}-${path}.json"
}

json_extract() {
  jq -r --arg path "$2" '
    def dig($p):
      reduce ($p | split("."))[] as $k (.;
        if type == "object" and has($k) then .[$k] else empty end
      );
    dig($path)
  ' "$1"
}

json_has_key() {
  jq -e --arg path "$2" '
    def dig($p):
      reduce ($p | split("."))[] as $k (.;
        if type == "object" and has($k) then .[$k] else empty end
      );
    dig($path) != null
  ' "$1" >/dev/null
}

build_body_from_request() {
  local request_json="$1"
  jq -c '
    (.bodyPatterns // [])
    | map(select(.matchesJsonPath? and (.matchesJsonPath | test("@\\."))))
    | map(.matchesJsonPath | capture("@\\.(?<key>[^\\)]+)") | .key)
    | reduce .[] as $key ({}; . + {($key): "value"})
  ' "$request_json"
}

run_from_request_file() {
  local request_json="$1"
  local response_json="$2"
  local request_name
  request_name="$(basename "${request_json}" .json)"

  local method path status content_type body auth_required
  method="$(json_extract "${request_json}" method)"
  if json_has_key "${request_json}" urlPath; then
    path="$(json_extract "${request_json}" urlPath)"
  else
    path="$(json_extract "${request_json}" urlPathPattern)"
  fi

  status="$(json_extract "${response_json}" status)"

  local actual_path="${path}"
  actual_path="${actual_path//\\//}"
  actual_path="${actual_path//\[0-9\]\+/1}"
  actual_path="${actual_path//\[0-9\]/1}"

  local curl_args=(-X "${method}" "${BASE_HOST}${actual_path}")

  if json_has_key "${request_json}" headers.Content-Type.contains; then
    content_type="$(json_extract "${request_json}" headers.Content-Type.contains)"
    curl_args+=(-H "Content-Type: ${content_type}")
  fi

  if json_has_key "${request_json}" headers.Authorization.matches; then
    curl_args+=(-H "Authorization: Bearer ${TOKEN}")
  fi

  if json_has_key "${request_json}" bodyPatterns; then
    body="$(build_body_from_request "${request_json}")"
    if [[ "${body}" != "{}" ]]; then
      curl_args+=(-d "${body}")
    fi
  fi

  run_expect "${request_name}" "${status}" curl "${curl_args[@]}"
}

echo "== Public endpoints =="
run_from_request_file "${REQUESTS_DIR}/auth-register-usager.json" "${RESPONSES_DIR}/auth-register-usager.json"
run_from_request_file "${REQUESTS_DIR}/auth-register-compte.json" "${RESPONSES_DIR}/auth-register-compte.json"
run_from_request_file "${REQUESTS_DIR}/auth-login.json" "${RESPONSES_DIR}/auth-login.json"
run_from_request_file "${REQUESTS_DIR}/auth-login-unauthorized.json" "${RESPONSES_DIR}/auth-login-unauthorized.json"

echo "== Protected endpoints =="
run_from_request_file "${REQUESTS_DIR}/comptes-get.json" "${RESPONSES_DIR}/comptes-get.json"
run_from_request_file "${REQUESTS_DIR}/comptes-patch.json" "${RESPONSES_DIR}/comptes-patch.json"
run_from_request_file "${REQUESTS_DIR}/comptes-delete.json" "${RESPONSES_DIR}/comptes-delete.json"
run_from_request_file "${REQUESTS_DIR}/usagers-get.json" "${RESPONSES_DIR}/usagers-get.json"
run_from_request_file "${REQUESTS_DIR}/usagers-patch.json" "${RESPONSES_DIR}/usagers-patch.json"
run_from_request_file "${REQUESTS_DIR}/usagers-delete.json" "${RESPONSES_DIR}/usagers-delete.json"
run_from_request_file "${REQUESTS_DIR}/roles-get.json" "${RESPONSES_DIR}/roles-get.json"
run_from_request_file "${REQUESTS_DIR}/roles-post.json" "${RESPONSES_DIR}/roles-post.json"

if [[ "${FAILED_TESTS}" -eq 0 ]]; then
  echo "✅ BILAN: ${PASSED_TESTS}/${TOTAL_TESTS} tests des stubs passés avec succès (0 échec)."
else
  echo "❌ BILAN: ${PASSED_TESTS}/${TOTAL_TESTS} tests des stubs passés, ${FAILED_TESTS} échec(s)."
  exit 1
fi
