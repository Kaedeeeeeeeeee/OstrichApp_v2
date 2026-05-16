#!/usr/bin/env bash
# scripts/check-dto-alignment.sh
# 警告 schema.ts ↔ DTO.swift 字段名漂移。不让 CI fail（exit 0），仅输出 warning。
# 使用方式：./scripts/check-dto-alignment.sh

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA="$ROOT/convex/schema.ts"
DTO="$ROOT/ios/OstrichApp/Networking/DTO.swift"

if [[ ! -f "$SCHEMA" ]]; then
  echo "warning: convex/schema.ts 不存在 ($SCHEMA)"
  exit 0
fi

if [[ ! -f "$DTO" ]]; then
  echo "warning: ios/OstrichApp/Networking/DTO.swift 不存在 ($DTO)"
  exit 0
fi

echo "== check-dto-alignment =="
echo "schema: $SCHEMA"
echo "dto:    $DTO"

# 抽取 schema 字段名：行形如 `    fieldName: v....,`
# 过滤掉 import/export/defineTable 行；只看 ident: 模式。
schema_fields=$(
  grep -E '^[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*v\.' "$SCHEMA" \
    | sed -E 's/^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):.*/\1/' \
    | sort -u
)

# 抽取 DTO 字段名：行形如 `    public let fieldName: Type`
dto_fields=$(
  grep -E '^[[:space:]]+public let [a-zA-Z_][a-zA-Z0-9_]*:' "$DTO" \
    | sed -E 's/^[[:space:]]+public let ([a-zA-Z_][a-zA-Z0-9_]*):.*/\1/' \
    | sort -u
)

# DTO 里出现 + schema 里完全没出现的字段（可能 typo）。
# 忽略一组已知的"DTO 独有但合规"的字段（来自 INTERFACES §3 派生字段，不是 schema 列）。
known_dto_only="
id
roomId
toolName
args
pendingPersonId
fromPersonId
toPersonId
weight
ostrichId
ostrichCount
centerLat
centerLng
expectedDurationSec
startedAt
coords
status
data
error
ok
isNewUser
sessionToken
userId
personId
messageId
ostrichReply
toolCalls
messages
hasMore
people
edges
entries
cells
nearby
route
ostrich
encounteredOstrichOwnerName
lookAroundAvailable
archetype
daysTogether
accepted
refusal
code
message
"

warnings=0
for f in $dto_fields; do
  if ! grep -qx "$f" <<<"$schema_fields"; then
    if ! grep -qx "$f" <<<"$known_dto_only"; then
      echo "warning: DTO 字段 \"$f\" 在 schema.ts 中找不到对应 (可能是 typo 或派生字段；如属预期请加入 known_dto_only 白名单)"
      warnings=$((warnings + 1))
    fi
  fi
done

if [[ $warnings -eq 0 ]]; then
  echo "ok: DTO 字段全部能在 schema.ts 中找到或属于已知派生字段。"
else
  echo "总计 $warnings 条 warning。"
fi

exit 0
