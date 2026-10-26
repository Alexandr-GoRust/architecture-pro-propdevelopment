# Спринт 5. Подготовка к аудиту ИБ — PropDevelopment

Проектная работа курса «System Design Pro» (Яндекс Практикум), спринт 5.
Кейс: компания **PropDevelopment** — платформа управления жилой недвижимостью
(витрина собственников, CRM, мобильное приложение, интеграция с платформой
«Умный дом» партнёра).

## Состав решения

| Задание | Что сделано | Ключевые файлы |
|---|---|---|
| **Task1** | Mindmap классификации данных по ISO/IEC 27001–27002: 4 класса (публичные / внутренние / конфиденциальные / секретные), типы данных PropDevelopment, риски с оценкой и обоснованиями | `Task1/Data_Security_Mindmap.drawio` |
| **Task2** | Проверочный лист аудита ИБ бизнес-систем (5 разделов, ~50 вопросов) с оценкой «да/нет/частично» по кейсу и главными выводами | `Task2/Checklist.md` |
| **Task3** | C4-диаграмма контекста (интеграция с «Умным домом»), доработка исходной диаграммы контейнеров (smart-home-gateway + платформа партнёра), требования к внешним интеграциям (TLS/mTLS, OAuth 2.0, минимизация ПДн, 152-ФЗ) | `Task3/` |
| **Task4** | Ролевая модель RBAC Kubernetes (4 роли × 4 доменных namespace) + скрипты создания пользователей, ролей и биндингов с проверками `kubectl auth can-i` | `Task4/` |
| **Task5** | NetworkPolicy для пар фронтенд↔бэкенд (4 политики, ingress+egress, явное правило DNS к kube-dns) — проверено живьём: разрешённые пары соединяются, неразрешённые — deny | `Task5/non-admin-api-allow.yaml` |
| **Task6** | Аудит apiserver (audit-policy подключён в minikube «снаружи»), симуляция инцидента, скрипт фильтрации audit.log (Bash+jq, 5 категорий), выжимка и отчёт с атрибуцией и разбором ошибок RBAC | `Task6/` |
| **Task7** | PodSecurity restricted (audit-zone), insecure/secure-манифесты, OPA Gatekeeper (4 правила: privileged / hostPath / runAsNonRoot / readOnlyRootFilesystem), verify-скрипты — проверено живьём | `Task7/` |

## Окружение

- minikube v1.37.0 (docker driver), Kubernetes v1.37.0
- Проверено на живом кластере: NetworkPolicy (Task5), аудит (Task6),
  admission-контроль (Task7)

## Навигация по Kubernetes-заданиям

```bash
# Task4: ролевая модель RBAC
cd Task4 && bash 01-create-users.sh && bash 02-create-roles.sh && bash 03-create-bindings.sh

# Task5: сетевые политики
kubectl apply -f Task5/non-admin-api-allow.yaml

# Task6: аудит и симуляция инцидента (порядок — в Task6/README.md)
cd Task6 && bash simulate-incident.sh && ./filter-audit.sh audit/full-audit.log

# Task7: admission-контроль (PodSecurity + Gatekeeper)
kubectl apply -f Task7/01-create-namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.17.1/deploy/gatekeeper.yaml
kubectl apply -f Task7/gatekeeper/constraint-templates/
kubectl apply -f Task7/gatekeeper/constraints/
bash Task7/verify/verify-admission.sh && bash Task7/verify/validate-security.sh
```
