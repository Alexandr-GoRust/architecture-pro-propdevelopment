#!/bin/bash
# Скрипт 2. Создание ролей ролевой модели (см. RBAC_Roles_Table.md).
set -e

# Неймспейсы доменов PropDevelopment (разграничение по оргструктуре)
for NS in sales hku finance data infra; do
  kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
done

# --- Role: security-secret-reader (привилегированная группа ИБ, ns infra) ---
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: security-secret-reader
  namespace: infra
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
EOF

# --- ClusterRole: cluster-readonly-viewer (только просмотр ресурсов кластера) ---
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-readonly-viewer
rules:
- apiGroups: [""]
  resources: ["pods", "services", "nodes", "events", "namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
EOF

# --- Role: namespace-operator (настройка неймспейса домена) в каждом доменном ns ---
for NS in sales hku finance data; do
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: namespace-operator
  namespace: $NS
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["create", "update", "patch", "delete", "get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["create", "update", "patch", "delete", "get", "list", "watch"]
EOF
done

# --- Role: domain-viewer (просмотр своего неймспейса функциональными командами) ---
for NS in sales hku finance data; do
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: domain-viewer
  namespace: $NS
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
EOF
done

echo "Роли созданы: security-secret-reader (infra), cluster-readonly-viewer, namespace-operator x4, domain-viewer x4"
