#!/usr/bin/env bash

set -euo pipefail

CONTRACT_FILE="${CONTRACT_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gestion-compte-contrat.yml}"
SERVER_PATH="${SERVER_PATH:-$(ruby -e 'require "yaml"; puts YAML.load_file(ARGV[0]).dig("servers", 0, "url") || "/api/comptes/v1"' "${CONTRACT_FILE}")}"
BASE_HOST="${BASE_HOST:-http://localhost:8081}"
TOKEN="${TOKEN:-stub-access-token}"
MAPPINGS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mappings"

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

json_extract() {
  printf '%s\n' "$1" | jq -r --arg path "$2" '
    def dig($p):
      reduce ($p | split("."))[] as $k (.;
        if type == "object" and has($k) then .[$k] else empty end
      );
    dig($path)
  '
}

json_has_key() {
  printf '%s\n' "$1" | jq -e --arg path "$2" '
    def dig($p):
      reduce ($p | split("."))[] as $k (.;
        if type == "object" and has($k) then .[$k] else empty end
      );
    dig($path) != null
  ' >/dev/null
}

build_body_from_request() {
  local request_json="$1"
  printf '%s\n' "$request_json" | jq -c '
    (.bodyPatterns // [])
    | map(select(.matchesJsonPath? and (.matchesJsonPath | test("@\\.|\\$."))))
    | map(
        .matchesJsonPath
        | if test("@\\.") then
            capture("@\\.(?<key>[^\\)]+)") | .key
          else
            capture("\\$\\.(?<key>.+)") | .key
          end
      )
    | reduce .[] as $key ({}; . + {($key): "value"})
  '
}

run_from_mapping_file() {
  local mapping_file="$1"
  local request_name
  request_name="$(basename "${mapping_file}" .json)"

  local request_json response_json method path status content_type body
  request_json="$(jq -c '.request' "${mapping_file}")"
  response_json="$(jq -c '.response' "${mapping_file}")"

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

for mapping_file in "${MAPPINGS_DIR}"/*.json; do
  if [[ ! -f "${mapping_file}" ]]; then
    continue
  fi
  run_from_mapping_file "${mapping_file}"
done

if [[ "${FAILED_TESTS}" -eq 0 ]]; then
  echo "✅ BILAN: ${PASSED_TESTS}/${TOTAL_TESTS} tests des stubs passés avec succès (0 échec)."
else
  echo "❌ BILAN: ${PASSED_TESTS}/${TOTAL_TESTS} tests des stubs passés, ${FAILED_TESTS} échec(s)."
  exit 1
fi
