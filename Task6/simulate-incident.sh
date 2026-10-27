#!/bin/bash

# Скрипт симуляции инцидента — дословно из ТЗ задания 6.
# Запускать после того, как кластер minikube поднят с подключённым audit-policy
# (см. README.md) и лог аудит доступен на хосте.

kubectl create ns secure-ops
kubectl config set-context --current --namespace=secure-ops

kubectl create sa monitoring
kubectl run attacker-pod --image=alpine --command -- sleep 3600
kubectl auth can-i get secrets --as=system:serviceaccount:secure-ops:monitoring

kubectl get secret -n kube-system $(kubectl get secrets -n kube-system | grep default-token | head -n1 | awk '{print $1}') --as=system:serviceaccount:secure-ops:monitoring

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: privileged-pod
spec:
  containers:
  - name: pwn
    image: alpine
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
  restartPolicy: Never
EOF

kubectl exec -n kube-system $(kubectl get pods -n kube-system | grep coredns | awk '{print $1}' | head -n1) -- cat /etc/resolv.conf

kubectl delete -f /etc/kubernetes/audit-policy.yaml --as=admin

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: escalate-binding
subjects:
- kind: ServiceAccount
  name: monitoring
  namespace: secure-ops
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

# --- Дополнение (см. analysis.md, раздел 5) ---
# Строка ТЗ `kubectl delete -f /etc/kubernetes/audit-policy.yaml --as=admin`
# завершается ошибкой НА КЛИЕНТЕ (файла /etc/kubernetes/audit-policy.yaml на
# хосте нет), поэтому запрос до apiserver не доходит и в audit.log не попадает.
# Чтобы событие «попытка удаления audit-policy» было зафиксировано в логе,
# имитируем её через ConfigMap с политикой (как политика хранится в реальных
# кластерах): создание + несанкционированная попытка удаления от имени admin.
kubectl create configmap audit-policy --from-file=/tmp/k8s-audit/audit-policy.yaml -n secure-ops
kubectl delete configmap audit-policy -n secure-ops --as=admin
