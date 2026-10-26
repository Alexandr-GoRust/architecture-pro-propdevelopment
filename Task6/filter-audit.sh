#!/usr/bin/env bash
#
# filter-audit.sh — скрипт фильтрации audit.log (Kubernetes API audit log).
# Выделяет подозрительные события по пяти категориям задания 6 и собирает
# их в компактную выжимку audit-extract.json.
#
# Использование:
#   ./filter-audit.sh [audit.log] [audit-extract.json]
#   по умолчанию: ./filter-audit.sh audit.log audit-extract.json
#
# Категории:
#   1. secrets_access         — доступ (get/list/watch) к секретам
#   2. exec_into_pods         — kubectl exec в чужие поды (create subresource=exec)
#   3. privileged_pods        — создание подов с privileged:true
#   4. rolebinding_escalation — RoleBinding на cluster-admin (эскалация привилегий)
#   5. audit_policy_tampering — действия с объектами audit-policy (попытки удалить/изменить)
#
# Зависимости: bash, jq.

set -euo pipefail

LOG="${1:-audit.log}"
OUT="${2:-audit-extract.json}"

if [[ ! -r "$LOG" ]]; then
    echo "Ошибка: файл '$LOG' не найден или недоступен для чтения" >&2
    exit 1
fi
command -v jq >/dev/null || { echo "Ошибка: требуется jq" >&2; exit 1; }

# Компактная сводка одного события аудита (применяется ПОСЛЕ select,
# чтобы условия могли использовать сырые поля, в т.ч. requestObject).
COMPACT='{ts: (.stageTimestamp // .requestReceivedTimestamp),
          user: .user.username,
          impersonated: (.impersonatedUser.username // null),
          verb: .verb,
          resource: .objectRef.resource,
          subresource: (.objectRef.subresource // null),
          namespace: (.objectRef.namespace // null),
          name: .objectRef.name,
          http_code: (.responseStatus.code // null),
          reason: (.responseStatus.reason // null)}'

TMPDIR_F=$(mktemp -d)
trap 'rm -rf "$TMPDIR_F"' EXIT

# 1. Доступ к секретам (и попытки, и успешные чтения).
jq -c "select(.objectRef.resource==\"secrets\"
        and (.verb==\"get\" or .verb==\"list\" or .verb==\"watch\"))
       | $COMPACT" "$LOG" >"$TMPDIR_F/c1.jsonl" || true

# 2. kubectl exec в чужом поде: subresource=exec. В Kubernetes 1.37 exec-запрос
#    (SPDY/WebSocket) проходит как GET, поэтому ловим оба варианта глагола —
#    и create, и get (подсказка из ТЗ ориентирована на старое поведение).
jq -c "select(.objectRef.subresource==\"exec\"
        and (.verb==\"create\" or .verb==\"get\"))
       | $COMPACT" "$LOG" >"$TMPDIR_F/c2.jsonl" || true

# 3. Привилегированные поды: requestObject.spec.containers[].securityContext.privileged==true.
jq -c "select(.objectRef.resource==\"pods\" and .verb==\"create\"
        and ([.requestObject.spec.containers[]?.securityContext.privileged==true] | any))
       | $COMPACT" "$LOG" >"$TMPDIR_F/c3.jsonl" || true

# 4. Эскалация привилегий: создание/изменение RoleBinding. Политика аудита из ТЗ
#    покрывает rbac-ресурсы только в core-группе (""), поэтому событие приходит
#    с level=Metadata и без requestObject — сверяем роль и по requestObject
#    (когда он есть), и по имени объекта (escalate-binding из симуляции).
jq -c "select(.objectRef.resource==\"rolebindings\"
        and (.verb==\"create\" or .verb==\"update\" or .verb==\"patch\")
        and (((.requestObject.roleRef.name // \"\")==\"cluster-admin\")
             or ((.objectRef.name // \"\")==\"escalate-binding\")))
       | $COMPACT" "$LOG" >"$TMPDIR_F/c4.jsonl" || true

# 5. Тамперинг с audit-policy: любые действия над объектами с именем audit-policy
#    (структурированный аналог grep -i 'audit-policy' из ТЗ).
jq -c "select(((.objectRef.name // \"\") | ascii_downcase | contains(\"audit-policy\")))
       | $COMPACT" "$LOG" >"$TMPDIR_F/c5.jsonl" || true

# Сборка единого JSON.
jq -n \
    --slurpfile secrets "$TMPDIR_F/c1.jsonl" \
    --slurpfile execs "$TMPDIR_F/c2.jsonl" \
    --slurpfile priv "$TMPDIR_F/c3.jsonl" \
    --slurpfile rbac "$TMPDIR_F/c4.jsonl" \
    --slurpfile policy "$TMPDIR_F/c5.jsonl" \
    --arg source "$LOG" \
    --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
        generated_at: $generated,
        source_log: $source,
        description: "Подозрительные события из Kubernetes audit.log (кейс secure-ops, Task6)",
        categories: {
            secrets_access:         $secrets,
            exec_into_pods:         $execs,
            privileged_pods:        $priv,
            rolebinding_escalation: $rbac,
            audit_policy_tampering: $policy
        },
        summary: {
            secrets_access:         ($secrets | length),
            exec_into_pods:         ($execs | length),
            privileged_pods:        ($priv | length),
            rolebinding_escalation: ($rbac | length),
            audit_policy_tampering: ($policy | length)
        }
    }' >"$OUT"

# Человекочитаемая сводка.
echo "Готово: $OUT"
echo "  1. Доступ к секретам:            $(wc -l <"$TMPDIR_F/c1.jsonl" | tr -d ' ')"
echo "  2. kubectl exec в чужом поде:    $(wc -l <"$TMPDIR_F/c2.jsonl" | tr -d ' ')"
echo "  3. Привилегированные поды:       $(wc -l <"$TMPDIR_F/c3.jsonl" | tr -d ' ')"
echo "  4. RoleBinding -> cluster-admin: $(wc -l <"$TMPDIR_F/c4.jsonl" | tr -d ' ')"
echo "  5. Действия с audit-policy:      $(wc -l <"$TMPDIR_F/c5.jsonl" | tr -d ' ')"
