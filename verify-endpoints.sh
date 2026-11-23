#!/usr/bin/env bash
# Reads .testkeys.env and calls each provider's real usage endpoint, so the
# Swift decoders can be checked against actual responses rather than docs.
#
# .testkeys.env format (one per line, only the ones you have):
#   OPENROUTER=sk-or-v1-...
#   ANTHROPIC=sk-ant-admin...
#   OPENAI=sk-admin-...
#   DEEPSEEK=sk-...
#   GROQ=gsk_...
set -uo pipefail
cd "$(dirname "$0")"
[ -f .testkeys.env ] || { echo "No .testkeys.env found."; exit 1; }
set -a; . ./.testkeys.env; set +a

MONTH_START_ISO=$(date -u +%Y-%m-01T00:00:00Z)
MONTH_START_EPOCH=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$MONTH_START_ISO" +%s 2>/dev/null)

show() { echo; echo "=== $1 ==="; }

if [ -n "${OPENROUTER:-}" ]; then
  show "OpenRouter /api/v1/key"
  curl -sS -w '\nHTTP %{http_code}\n' https://openrouter.ai/api/v1/key \
    -H "Authorization: Bearer $OPENROUTER"
fi

if [ -n "${ANTHROPIC:-}" ]; then
  show "Anthropic /v1/organizations/cost_report"
  curl -sS -w '\nHTTP %{http_code}\n' -G \
    https://api.anthropic.com/v1/organizations/cost_report \
    --data-urlencode "starting_at=$MONTH_START_ISO" \
    --data-urlencode "bucket_width=1d" --data-urlencode "limit=31" \
    -H "x-api-key: $ANTHROPIC" -H "anthropic-version: 2023-06-01"
fi

if [ -n "${OPENAI:-}" ]; then
  show "OpenAI /v1/organization/costs"
  curl -sS -w '\nHTTP %{http_code}\n' -G \
    https://api.openai.com/v1/organization/costs \
    --data-urlencode "start_time=$MONTH_START_EPOCH" \
    --data-urlencode "bucket_width=1d" --data-urlencode "limit=31" \
    -H "Authorization: Bearer $OPENAI"
fi

if [ -n "${DEEPSEEK:-}" ]; then
  show "DeepSeek /user/balance"
  curl -sS -w '\nHTTP %{http_code}\n' https://api.deepseek.com/user/balance \
    -H "Authorization: Bearer $DEEPSEEK"
fi

if [ -n "${GROQ:-}" ]; then
  show "Groq /openai/v1/models (rate-limit headers)"
  curl -sS -o /dev/null -D - https://api.groq.com/openai/v1/models \
    -H "Authorization: Bearer $GROQ" | grep -iE "^(HTTP|x-ratelimit)"
fi
echo; echo "Done."
