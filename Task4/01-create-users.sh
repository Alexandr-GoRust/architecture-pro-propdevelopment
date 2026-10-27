#!/bin/bash
# Скрипт 1. Создание пользователей кластера (клиентские сертификаты + kubeconfig).
# Пользователи: sec-officer (специалист ИБ), devops-sales (DevOps домена «Продажи»).
set -e

CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
USER_DIR=./users
mkdir -p "$USER_DIR"

create_user () {
  local USER=$1
  local GROUP=$2
  openssl genrsa -out "$USER_DIR/$USER.key" 2048 2>/dev/null
  openssl req -new -key "$USER_DIR/$USER.key" \
    -subj "/CN=$USER/O=$GROUP" -out "$USER_DIR/$USER.csr"
  # CSR подписывается ключом кластера через API (подписывать локальным CA корректно только на minikube)
  cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $USER-csr
spec:
  request: $(base64 < "$USER_DIR/$USER.csr" | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  usages: [client auth]
EOF
  kubectl certificate approve "$USER-csr"
  kubectl get csr "$USER-csr" -o jsonpath='{.status.certificate}' | base64 -d > "$USER_DIR/$USER.crt"

  kubectl config set-credentials "$USER" \
    --client-certificate="$USER_DIR/$USER.crt" --client-key="$USER_DIR/$USER.key" --embed-certs=true
  kubectl config set-context "$USER" --cluster="$CLUSTER_NAME" --user="$USER"
  echo "Пользователь $USER (группа $GROUP) создан, контекст: $USER"
}

# Пользователь ИБ — член группы security (привилегированная группа: просмотр секретов)
create_user sec-officer security
# Пользователь DevOps домена «Продажи» — член группы devops-sales (настройка своего неймспейса)
create_user devops-sales devops-sales

echo "Готово. Проверка: kubectl --context sec-officer auth can-i get secrets -n infra"
