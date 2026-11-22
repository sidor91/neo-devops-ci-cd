# Домашнє завдання 4 · Docker

Django працює за Nginx і використовує PostgreSQL. Compose запускає PostgreSQL, чекає на готовність бази, застосовує міграції Django й запускає Nginx, коли застосунок відповідає на HTTP-запити.

## Запуск

Потрібні запущений Docker, Docker Compose та вільний локальний порт 80. Запустіть сервіси з кореня репозиторію.

```sh
cp .env.example .env
docker compose config --quiet
docker compose up -d --build
```

Відкрийте [http://localhost](http://localhost). На сторінці з’явиться `Django is running.`. Команда `docker-compose up -d --build` також працює, якщо Compose доступний під цим іменем.

## Перевірка

```sh
docker compose ps
curl -fsS http://localhost/
docker compose exec web python manage.py migrate --check
docker compose exec web python manage.py shell -c '
from django.db import connection

with connection.cursor() as cursor:
    cursor.execute("SELECT current_database()")
    print(cursor.fetchone()[0])
'
```

Очікувана назва бази з `.env.example` — `lesson4`. Щоб зупинити сервіси, виконайте `docker compose down`. Наступний `docker compose up -d` використає дані з іменованого тому `postgres_data`.
