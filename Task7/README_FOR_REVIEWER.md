# Task7 — аудит и соответствие политике безопасности контейнеров

**PodSecurity Admission (restricted) + OPA Gatekeeper**, живая проверка на кластере
minikube v1.37.0 / Kubernetes v1.37.0 / Gatekeeper v3.17.1.

## Структура

```
Task7/
├── 01-create-namespace.yaml        # audit-zone с enforce/audit/warn=restricted
├── insecure-manifests/             # ДОЛЖНЫ отклоняться
│   ├── 01-privileged-pod.yaml      #   privileged: true
│   ├── 02-hostpath-pod.yaml        #   hostPath /
│   └── 03-root-user-pod.yaml       #   runAsUser: 0
├── secure-manifests/               # ДОЛЖНЫ проходить
│   ├── 01-secure.yaml              #   без privileged, restricted-профиль
│   ├── 02-secure.yaml              #   emptyDir вместо hostPath
│   └── 03-secure.yaml              #   runAsNonRoot, UID 10001
├── gatekeeper/
│   ├── constraint-templates/       # 4 правила ТЗ (4-е — readOnlyRootFilesystem —
│   │                               # сверх структуры ТЗ отдельным шаблоном)
│   └── constraints/                # enforcementAction: deny
├── verify/
│   ├── verify-admission.sh         # функциональный тест admission (apply-манифесты)
│   └── validate-security.sh        # валидация конфигурации (labels/deploy/констрейнты)
├── audit-policy.yaml               # как в Task6 + фикс группы rbac.authorization.k8s.io
└── README_FOR_REVIEWER.md
```

## Быстрое воспроизведение

```bash
kubectl apply -f 01-create-namespace.yaml

# небезопасные — отклоняются, безопасные — проходят
bash verify/verify-admission.sh            # этап 1: PodSecurity

# Gatekeeper (нужен ~1 мин на readiness)
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.17.1/deploy/gatekeeper.yaml
kubectl -n gatekeeper-system wait --for=condition=available deploy --all --timeout=300s
kubectl apply -f gatekeeper/constraint-templates/
kubectl apply -f gatekeeper/constraints/

bash verify/verify-admission.sh            # этапы 1+2: PodSecurity + Gatekeeper
bash verify/validate-security.sh           # конфигурация кластера
```

## Правила Gatekeeper

| Правило | Констрейнт | Сообщение |
|---|---|---|
| `privileged: true` запрещён | `no-privileged` | контейнер <name>: privileged: true запрещён |
| `hostPath` запрещён | `no-hostpath` | том <name>: hostPath запрещён (используйте emptyDir/PVC) |
| только `runAsNonRoot: true` | `require-runasnonroot` | контейнер <name>: требуется runAsNonRoot: true |
| `readOnlyRootFilesystem: true` обязателен | `require-readonlyrootfs` | контейнер <name>: требуется readOnlyRootFilesystem: true |

Констрейнты матчат поды во всех namespace, кроме `kube-system` и
`gatekeeper-system` (системные компоненты). Правило про `readOnlyRootFilesystem`
оформлено отдельной парой шаблон+констрейнт (файл `readonlyrootfs.yaml` сверх
структуры из ТЗ), чтобы каждое из четырёх правил имело свой идентификатор
в сообщении отказа.

## Фактические результаты живой проверки

`verify-admission.sh` (PASS=9 FAIL=0):

```
=== Этап 1. PodSecurity Admission (namespace audit-zone) ===
✅ privileged:true     : отклонён (Forbidden)
✅ hostPath            : отклонён (Forbidden)
✅ root (UID 0)        : отклонён (Forbidden)
✅ secure-аналог privileged: принят
✅ secure-аналог hostPath  : принят
✅ secure-аналог root      : принят

=== Этап 2. Gatekeeper (независимо от PodSecurity, ns gate-test без restricted) ===
✅ Gatekeeper отклонил 01-privileged-pod.yaml (denied: [no-privileged] контейнер <nginx>: privileged: true запрещён)
✅ Gatekeeper отклонил 02-hostpath-pod.yaml    (denied: [require-runasnonroot] ...)
✅ Gatekeeper отклонил 03-root-user-pod.yaml   (denied: [require-runasnonroot] ...)
```

Этап 2 доказывает, что Gatekeeper блокирует нарушения **сам по себе**:
манифесты применялись в namespace `gate-test` без restricted-метки.

`validate-security.sh` (PASS=10 FAIL=0): namespace enforce=restricted; оба
Deployment Gatekeeper готовы (1/1 и 3/3); 4 шаблона синхронизированы подами
Gatekeeper (status.byPod); 4 констрейнта с enforcementAction=deny; работающие
поды audit-zone соответствуют политике (runAsNonRoot=true, readOnlyRootFS=true,
без privileged).

## Замечания по ходу проверки

- Имя ConstraintTemplate обязано быть точным lowercase его Kind
  (`k8spodreadonlyrootfilesystem`), иначе validating-webhook Gatekeeper
  отклоняет шаблон с ошибкой `invalid ConstraintTemplate`.
- В Gatekeeper v3.17.1 статус шаблона экспонируется через `status.byPod`
  (перечень синхронизировавших его подов), а не через `status.status.state`,
  как в старых версиях — `validate-security.sh` проверяет именно `byPod`.
