#!/bin/bash
# Скрипт 3. Связывание пользователей и групп с ролями (RoleBinding / ClusterRoleBinding).
set -e

# --- ИБ (привилегированная группа): просмотр секретов в infra ---
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: security-secret-reader-binding
  namespace: infra
subjects:
- kind: User
  name: sec-officer
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: security
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: security-secret-reader
  apiGroup: rbac.authorization.k8s.io
EOF

# --- Аналитики/разработчики: просмотр всего кластера без изменений ---
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-readonly-binding
subjects:
- kind: Group
  name: cluster-viewers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-readonly-viewer
  apiGroup: rbac.authorization.k8s.io
EOF

# --- DevOps доменов: настройка СВОЕГО неймспейса (по группам org-структуры) ---
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: namespace-operator-binding
  namespace: sales
subjects:
- kind: User
  name: devops-sales
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: devops-sales
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: namespace-operator
  apiGroup: rbac.authorization.k8s.io
EOF

# Аналогичные привязки для остальных доменов (группы devops-hku / devops-finance / devops-data)
for NS in hku finance data; do
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: namespace-operator-binding
  namespace: $NS
subjects:
- kind: Group
  name: devops-$NS
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: namespace-operator
  apiGroup: rbac.authorization.k8s.io
EOF
done

# --- Функциональные команды: просмотр своего домена ---
for NS in sales hku finance data; do
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: domain-viewer-binding
  namespace: $NS
subjects:
- kind: Group
  name: team-$NS
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: domain-viewer
  apiGroup: rbac.authorization.k8s.io
EOF
done

echo "Привязки созданы. Проверка прав:"
kubectl auth can-i get secrets -n infra --as sec-officer          # yes
kubectl auth can-i create pods -n sales --as sec-officer          # no
kubectl auth can-i create deployments -n sales --as devops-sales  # yes
kubectl auth can-i create deployments -n finance --as devops-sales # no
kubectl auth can-i delete pods -n sales --as devops-hku           # no (чужой домен)
