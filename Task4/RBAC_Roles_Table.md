# Задание 4. Ролевая модель доступа к Kubernetes-кластеру PropDevelopment

Роли построены по принципу минимальных привилегий и разграничены по оргструктуре компании — четырём доменам соответствуют неймспейсы `sales`, `hku`, `finance`, `data` (общие инфраструктурные операции — в `infra`).

## Таблица ролей

| Роль | Права роли | Группы пользователей |
| --- | --- | --- |
| `security-secret-reader` (Role, ns `infra`) | `get`, `list` для `secrets` — просмотр секретов интеграций (ключи партнёров, creds БД) без права модификации | Специалисты по информационной безопасности (привилегированная группа) |
| `cluster-readonly-viewer` (ClusterRole) | `get`, `list`, `watch` для `pods`, `services`, `deployments`, `nodes`, `events`, `logs` по всему кластеру — только чтение, без изменений | Разработчики доменов и аналитики (группа мониторинга состояния систем) |
| `namespace-operator` (Role, создаётся в `sales`, `hku`, `finance`, `data`) | `create`, `update`, `patch`, `delete`, `get`, `list` для `pods`, `deployments`, `services`, `configmaps` — полный цикл эксплуатации в своём неймспейсе | Операционные команды DevOps/эксплуатации соответствующего домена |
| `domain-viewer` (Role, в каждом доменном неймспейсе) | `get`, `list`, `watch` для `pods`, `services`, `deployments`, `configmaps` своего неймспейса | Функциональные команды домена (разработчики — просмотр своих сред) |

Пояснения:
- **Привилегированная группа** — ИБ-специалисты: доступ к просмотру секретов, но `get/list` без `create/update/delete` — даже защита не может менять секреты мимо процесса ротации.
- **Минимум две непривилегированные группы**: только просмотр (`cluster-readonly-viewer`, `domain-viewer`) и настройка (`namespace-operator`).
- **Разграничение по оргструктуре**: `namespace-operator` привязывается через RoleBinding отдельно в каждом доменном неймспейсе — команда домена `sales` не видит ресурсы `finance`; секреты интеграций — только в `infra` у ИБ.
- Служебная интеграция CI/CD — сервисный аккаунт с `namespace-operator` в целевых неймспейсах (не кластерный админ).

## Скрипты

1. `01-create-users.sh` — создание двух пользователей (`sec-officer`, `devops-sales`) с клиентскими сертификатами и kubeconfig-контекстами.
2. `02-create-roles.sh` — неймспейсы доменов, Role/ClusterRole из таблицы.
3. `03-create-bindings.sh` — RoleBinding/ClusterRoleBinding: связывает пользователей/группы с ролями.

Проверка после выполнения: `kubectl auth can-i --as sec-officer get secrets -n infra` → `yes`; `kubectl auth can-i --as sec-officer create pods -n sales` → `no`; `kubectl auth can-i --as devops-sales create deployments -n sales` → `yes`; `... -n finance` → `no`.
