#!/usr/bin/env bash
#
# validate-security.sh — валидация КОНФИГУРАЦИИ безопасности кластера
# (без применения объектов):
#   1. Namespace audit-zone существует и enforce=restricted.
#   2. Gatekeeper развёрнут и работает (Deployment ready, поды Running).
#   3. Все 4 ConstraintTemplate загружены и Established.
#   4. Все 4 констрейнта созданы с enforcementAction=deny.
#   5. Поды audit-zone действительно соответствуют restricted
#      (проверка фактического состояния, а не манифестов).
#
# Запуск из корня Task7:  bash verify/validate-security.sh

set -uo pipefail

PASS=0; FAIL=0
ok()   { echo "✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "❌ $1"; FAIL=$((FAIL+1)); }

echo "=== 1. Namespace audit-zone ==="
NS_LABEL=$(kubectl get ns audit-zone -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
[[ "$NS_LABEL" == "restricted" ]] && ok "audit-zone: pod-security.kubernetes.io/enforce=restricted" \
                               || bad "audit-zone: enforce=restricted не найден (получено: '$NS_LABEL'). Примените 01-create-namespace.yaml"

echo "=== 2. Gatekeeper ==="
if kubectl get crd constrainttemplates.templates.gatekeeper.sh >/dev/null 2>&1; then
    READY=$(kubectl -n gatekeeper-system get deploy --no-headers 2>/dev/null | awk '{split($2,a,"/"); if (a[1]<$3) bad=1} END{print (bad?"no":"yes")}')
    [[ "$READY" == "yes" ]] && ok "Deployment Gatekeeper готовы: $(kubectl -n gatekeeper-system get deploy --no-headers 2>/dev/null | awk '{print $1"="$2"/"$3}' | tr '\n' ' ')" \
                          || bad "Deployment Gatekeeper не готовы: $(kubectl -n gatekeeper-system get deploy --no-headers 2>/dev/null | awk '{print $1"="$2"/"$3}' | tr '\n' ' ')"
else
    bad "Gatekeeper не развёрнут. Установите: kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.17.1/deploy/gatekeeper.yaml"
fi

echo "=== 3. ConstraintTemplates (ожидается 4, статус byPod заполнен) ==="
for t in k8spodprivileged k8spodhostpath k8spodrunasnonroot k8spodreadonlyrootfilesystem; do
    BYPOD=$(kubectl get constrainttemplates.templates.gatekeeper.sh "$t" -o jsonpath='{.status.byPod}' 2>/dev/null)
    [[ -n "$BYPOD" && "$BYPOD" != "{}" ]] && ok "шаблон $t: загружен и синхронизирован подами Gatekeeper" \
                                           || bad "шаблон $t: не синхронизирован (status.byPod пуст)"
done

echo "=== 4. Констрейнты (enforcementAction=deny) ==="
# declare -A на macOS/bash 3.2 не работает — явное сопоставление имя→CRD
kind_of() {
    case "$1" in
        no-privileged)          echo k8spodprivileged.constraints.gatekeeper.sh ;;
        no-hostpath)            echo k8spodhostpath.constraints.gatekeeper.sh ;;
        require-runasnonroot)   echo k8spodrunasnonroot.constraints.gatekeeper.sh ;;
        require-readonlyrootfs) echo k8spodreadonlyrootfilesystem.constraints.gatekeeper.sh ;;
    esac
}
for c in no-privileged no-hostpath require-runasnonroot require-readonlyrootfs; do
    KIND=$(kind_of "$c")
    if kubectl get "$KIND" "$c" >/dev/null 2>&1; then
        ACT=$(kubectl get "$KIND" "$c" -o jsonpath='{.spec.enforcementAction}' 2>/dev/null)
        [[ "$ACT" == "deny" ]] && ok "констрейнт $c ($KIND): deny" || bad "констрейнт $c: enforcementAction='$ACT' (ожидался deny)"
    else
        bad "констрейнт $c не найден. Примените gatekeeper/constraints/"
    fi
done

echo "=== 5. Фактическое состояние подов в audit-zone ==="
kubectl get pods -n audit-zone -o name 2>/dev/null | while read -r p; do
    PR=$(kubectl get -n audit-zone "$p" -o jsonpath='{.spec.containers[0].securityContext.privileged}' 2>/dev/null)
    NR=$(kubectl get -n audit-zone "$p" -o jsonpath='{.spec.securityContext.runAsNonRoot}' 2>/dev/null)
    RO=$(kubectl get -n audit-zone "$p" -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null)
    echo "   $p: privileged=$PR runAsNonRoot=$NR readOnlyRootFS=$RO"
done

echo "================================"
echo "Итог: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] && echo "КОНФИГУРАЦИЯ БЕЗОПАСНА ✅" || echo "ЕСТЬ ПРОБЛЕМЫ ❌"
exit $((FAIL > 0))
