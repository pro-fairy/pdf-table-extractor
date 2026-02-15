# Серверная инфраструктура

> Последнее обновление: 2026-02-15

## Сервер

| Параметр | Значение |
|----------|----------|
| **Хостинг** | DigitalOcean (droplet) |
| **IP** | 165.227.175.252 |
| **Hostname** | profairy |
| **OS** | Ubuntu 24.04 LTS |
| **CPU** | 1 vCPU (DO-Regular) |
| **RAM** | 1.9 GB |
| **Disk** | 48 GB (использовано ~17 GB) |
| **SSH** | root@165.227.175.252 |

## Docker контейнеры (4 шт.)

| Контейнер | Образ | Порт | Назначение |
|-----------|-------|------|-----------|
| `pdf_table_extractor` | FastAPI app | 8000 | Наш сервис (парсинг PDF) |
| `medical-postgres` | postgres:15 | 5432 | База данных |
| `n8n-n8n-1` | n8nio/n8n:latest | 5678 (internal) | Оркестрация (будущее) |
| `n8n-caddy-1` | caddy:alpine | 80, 443 | Reverse proxy для N8N |

## PostgreSQL

| Параметр | Значение |
|----------|----------|
| **БД** | medical_analysis_mvp |
| **User** | medical_user |
| **Password** | (в Docker env) |
| **Таблиц** | 9 |
| **Данных** | 0 строк (пустая) |
| **Volume** | medical_pg_data |

## Структура файлов на сервере

```
/root/
├── pdf-table-extractor/      # Наш проект (клон из GitHub)
│   ├── .git/
│   ├── .github/workflows/
│   ├── app/
│   │   ├── main.py
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   ├── docker-compose.yml
│   └── .gitignore
├── n8n/                       # N8N конфигурация
│   ├── docker-compose.yml
│   ├── .env
│   └── Caddyfile
└── backups/
    └── medical-postgres_mvp/
        └── medical_2025-12-23.sql   # Старый бэкап
```

## CI/CD

- **Триггер:** Push в main → GitHub Actions
- **Workflow:** .github/workflows/deploy.yml
- **Процесс:** SSH → git pull → docker compose up -d --build
- **Timeout:** 60 минут
- **SSH ключ:** GitHub Secret `GIT_PULL_ACCESS`

⚠️ **ВНИМАНИЕ:** Push в main = автоматический деплой на продакшн!
Всегда тестировать локально перед push.

## N8N

- Установлен и работает
- Доступен через Caddy (HTTPS на портах 80/443)
- Интеграция с проектом планируется (оркестрация pipeline)
- Пока не используется в MVP

## Правила доступа к серверу (для Claude)

- ✅ **Можно:** SSH подключение, просмотр файлов, ls, cat, docker ps, SELECT запросы
- 🚫 **ЗАПРЕЩЕНО:** менять, удалять, создавать, перезапускать что-либо
- Только **READ-ONLY** доступ

## Docker Compose конфигурации

### pdf-table-extractor:
```yaml
services:
  pdf-extractor:
    build: ./app
    container_name: pdf_table_extractor
    ports: ["8000:8000"]
    restart: unless-stopped
```

### n8n:
```yaml
services:
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    env_file: .env
    volumes: [n8n_data:/home/node/.n8n]
  caddy:
    image: caddy:alpine
    ports: ["80:80", "443:443"]
```
