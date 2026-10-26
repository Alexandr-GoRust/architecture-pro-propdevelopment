# Task6 — Аудит активности пользователей и обнаружение инцидентов

## Состав

| Файл | Назначение |
|---|---|
| `audit/audit-policy.yaml` | Политика аудита (RequestResponse на критичные ресурсы, Metadata на всё остальное) |
| `simulate-incident.sh` | Скрипт симуляции инцидента (дословно из ТЗ + документированное дополнение, см. ниже) |
| `filter-audit.sh` | Скрипт фильтрации `audit.log` на Bash+jq — собирает `audit-extract.json` по 5 категориям |
| `audit-extract.json` | Выжимка подозрительных событий из `audit.log` (результат работы `filter-audit.sh`) |
| `analysis.md` | Отчёт по результатам анализа audit log |
| `audit/full-audit.log` | Полный лог аудита за время симуляции инцидента (исходник для выжимки) |

## Как поднят кластер с аудитом (minikube v1.37.0, k8s v1.37.0, docker driver)

Политика подключается «снаружи»: файл лежит на хостовой машине, каталог
примонтирован в minikube (`--mount`), флаги apiserver заданы через
`--extra-config`:

```bash
mkdir -p /tmp/k8s-audit
cp audit/audit-policy.yaml /tmp/k8s-audit/

minikube start \
  --cpus=2 --memory=4000 --driver=docker \
  --mount --mount-string=/tmp/k8s-audit:/data-audit \
  --extra-config=apiserver.audit-policy-file=/data-audit/audit-policy.yaml \
  --extra-config=apiserver.audit-log-path=/data-audit/audit.log
```

**Важная особенность свежего minikube/Kubernetes 1.37**, обнаруженная при настройке:
kube-apiserver работает как static-pod со своим списком volume-mounts, и каталог
`--mount` в его контейнер **не пробрасывается**. В результате apiserver не видит
`/data-audit/audit-policy.yaml` и падает в crash-loop
(`loading audit policy file: ... no such file or directory`), а старт кластера
обрывается на bootstrap. Рабочее решение — после подъёма здорового кластера
дополнить static-pod манифест volume'ом для `/data-audit`
(kubelet перезапускает apiserver автоматически):

```bash
# 1. Патчим манифест static-pod: добавляем volume и монтирование /data-audit
docker cp minikube:/etc/kubernetes/manifests/kube-apiserver.yaml ./kapi.yaml
#    (дописать в spec.containers[0].volumeMounts: {mountPath: /data-audit, name: audit-data}
#     и в spec.volumes: {name: audit-data, hostPath: {path: /data-audit, type: DirectoryOrCreate}})
docker cp ./kapi.yaml minikube:/etc/kubernetes/manifests/kube-apiserver.yaml

# 2. Заставляем kubelet перечитать манифест и перезапустить apiserver
docker exec minikube systemctl restart kubelet
```

После этого `audit.log` появляется на хосте в `/tmp/k8s-audit/audit.log`.

## Порядок воспроизведения

```bash
# 1. Поднять кластер с аудитом (см. выше) и дождаться Ready
kubectl get nodes

# 2. Запустить симуляцию инцидента
bash simulate-incident.sh

# 3. Отфильтровать подозрительные события (audit.log — построчный JSON/JSONL)
cp /tmp/k8s-audit/audit.log ./audit/full-audit.log
./filter-audit.sh audit/full-audit.log audit-extract.json

# 4. Самопроверка категорий (подсказки из ТЗ)
jq -c 'select(.objectRef.resource=="secrets" and .verb=="get")' audit/full-audit.log
jq -c 'select(.verb=="create" and .objectRef.subresource=="exec")' audit/full-audit.log
jq -c 'select(.objectRef.resource=="pods" and ([.requestObject.spec.containers[]?.securityContext.privileged==true]|any))' audit/full-audit.log
grep -i 'audit-policy' audit/full-audit.log | head
```

## Дополнение к скрипту симуляции

Строка ТЗ `kubectl delete -f /etc/kubernetes/audit-policy.yaml --as=admin`
завершается ошибкой **на клиенте** (файла `/etc/kubernetes/audit-policy.yaml`
на хосте нет), запрос до apiserver не доходит и в audit.log не попадает. Чтобы
событие «попытка удаления audit-policy» было зафиксировано в логе, в конец
скрипта добавлено: политика упакована в ConfigMap `audit-policy`, после чего
выполняется несанкционированная попытка её удаления от имени `admin`
(в реальных кластерах политика аудита как раз разносится через ConfigMap).
Оба дополнительно созданных объекта видны в `audit-extract.json`
(категория `audit_policy_tampering`).
