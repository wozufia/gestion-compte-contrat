#!/usr/bin/env bash

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8081/api/comptes/v1}"
TOKEN="${TOKEN:-stub-access-token}"
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

echo "== Public endpoints =="
run_expect "POST /auth/register/usager" "201" \
  curl -X POST "${BASE_URL}/auth/register/usager" \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","firstName":"Jean","lastName":"Dupont","motDePasse":"Str0ng@Pass!"}'

run_expect "POST /auth/register/compte" "201" \
  curl -X POST "${BASE_URL}/auth/register/compte" \
  -H "Content-Type: application/json" \
  -d '{"nom":"Compte Démo","contact":{"telephone":{"indicatif":"+52","numero":"1234567890"},"email":"owner@example.com","adresse":{"rue":"123 Rue Principale","ville":"Paris","codePostal":"75001","pays":"France"}}}'

run_expect "POST /auth/login (ok)" "201" \
  curl -X POST "${BASE_URL}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","motDePasse":"Str0ng@Pass!"}'

run_expect "POST /auth/login (fallback)" "401" \
  curl -X POST "${BASE_URL}/auth/login"

echo "== Protected endpoints =="
run_expect "GET /comptes/1" "200" \
  curl -X GET "${BASE_URL}/comptes/1" \
  -H "Authorization: Bearer ${TOKEN}"

run_expect "PATCH /comptes/1" "200" \
  curl -X PATCH "${BASE_URL}/comptes/1" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"nom":"Compte Mis à Jour","contact":{"email":"owner@example.com"}}'

run_expect "DELETE /comptes/1" "204" \
  curl -X DELETE "${BASE_URL}/comptes/1" \
  -H "Authorization: Bearer ${TOKEN}"

run_expect "GET /usagers/1" "200" \
  curl -X GET "${BASE_URL}/usagers/1" \
  -H "Authorization: Bearer ${TOKEN}"

run_expect "PATCH /usagers/1" "200" \
  curl -X PATCH "${BASE_URL}/usagers/1" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"email":"updated.user@example.com","firstName":"Jean","lastName":"Dupont","motDePasse":"Str0ng@Pass!"}'

run_expect "DELETE /usagers/1" "204" \
  curl -X DELETE "${BASE_URL}/usagers/1" \
  -H "Authorization: Bearer ${TOKEN}"

run_expect "GET /roles" "200" \
  curl -X GET "${BASE_URL}/roles" \
  -H "Authorization: Bearer ${TOKEN}"

run_expect "POST /roles" "201" \
  curl -X POST "${BASE_URL}/roles" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"SUPPORT","description":"Support level access"}'

if [[ "${FAILED_TESTS}" -eq 0 ]]; then
  echo "✅ BILAN: ${PASSED_TESTS}/${TOTAL_TESTS} tests des stubs passés avec succès (0 échec)."
else
  echo "❌ BILAN: ${PASSED_TESTS}/${TOTAL_TESTS} tests des stubs passés, ${FAILED_TESTS} échec(s)."
  exit 1
fi
