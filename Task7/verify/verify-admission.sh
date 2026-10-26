#!/usr/bin/env bash
#
# verify-admission.sh — функциональная проверка admission-контроля.
#
#   Этап 1. PodSecurity restricted в audit-zone:
#            insecure-манифесты ОТКЛОНЯЮТСЯ, secure — ПРИНИМАЮТСЯ.
#   Этап 2. Gatekeeper (запускается, только если Gatekeeper установлен):
#            те же правила работают независимо от PodSecurity — в namespace
#            без restricted-метки (gate-test) insecure тоже отклоняется.
#
# Запуск из корня Task7:  bash verify/verify-admission.sh

set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0; FAIL=0

expect_reject() { # $1=манифест, $2=что проверяем
    local out
    if out=$(kubectl apply -f "$1" 2>&1); then
        echo "❌ $2: ОЖИДАЛСЯ ОТКАЗ, но под принят: $out"
        FAIL=$((FAIL+1))
    else
        echo "✅ $2: отклонён ($(echo "$out" | grep -o 'admission webhook.*denied\|Forbidden\|violates.*policy\|denied by.*' | head -1 | cut -c1-80))"
        PASS=$((PASS+1))
    fi
}

expect_accept() { # $1=манифест, $2=описание
    local out
    if out=$(kubectl apply -f "$1" 2>&1); then
        echo "✅ $2: принят"
        PASS=$((PASS+1))
    else
        echo "❌ $2: ОЖИДАЛСЯ УСПЕХ, получен отказ: $out"
        FAIL=$((FAIL+1))
    fi
}

echo "=== Этап 0. Namespace audit-zone (PodSecurity restricted) ==="
kubectl apply -f 01-create-namespace.yaml
echo

echo "=== Этап 1. PodSecurity Admission (namespace audit-zone) ==="
expect_reject insecure-manifests/01-privileged-pod.yaml "privileged:true     "
expect_reject insecure-manifests/02-hostpath-pod.yaml    "hostPath            "
expect_reject insecure-manifests/03-root-user-pod.yaml   "root (UID 0)        "
expect_accept secure-manifests/01-secure.yaml            "secure-аналог privileged"
expect_accept secure-manifests/02-secure.yaml            "secure-аналог hostPath  "
expect_accept secure-manifests/03-secure.yaml            "secure-аналог root      "
echo

if kubectl get crd constrainttemplates.templates.gatekeeper.sh >/dev/null 2>&1; then
    echo "=== Этап 2. Gatekeeper (независимо от PodSecurity, ns gate-test без restricted) ==="
    kubectl create ns gate-test >/dev/null 2>&1 || true
    for m in insecure-manifests/01-privileged-pod.yaml insecure-manifests/02-hostpath-pod.yaml insecure-manifests/03-root-user-pod.yaml; do
        # подменяем namespace на неограниченный, чтобы отказ гарантированно дал Gatekeeper
        if out=$(sed 's/namespace: audit-zone/namespace: gate-test/' "$m" | kubectl apply -f - 2>&1); then
            echo "❌ Gatekeeper: $m принят в gate-test (правило не сработало)"
            FAIL=$((FAIL+1))
        else
            echo "✅ Gatekeeper отклонил $m ($(echo "$out" | grep -oE 'denied the request.*' | head -1 | cut -c1-70))"
            PASS=$((PASS+1))
        fi
    done
    kubectl delete ns gate-test --wait=false >/dev/null 2>&1 || true
else
    echo "=== Этап 2 пропущен: Gatekeeper не установлен (см. README_FOR_REVIEWER.md) ==="
fi

echo
echo "================================"
echo "Итог: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] && echo "ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ ✅" || echo "ЕСТЬ ПРОВАЛЫ ❌"
exit $((FAIL > 0))
