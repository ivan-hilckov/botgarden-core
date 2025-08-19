Мне надо изменить архитектуру bot-template

проанализируй следующее файлы:

```
bot-template/Dockerfile
bot-template/env.example
bot-template/deploy-bot.sh
bot-template/requirements.txt
bot-template/docker-compose.bot.yml
bot-template/docker-compose.yml
bot-template/app/__main__.py
```

исследуй их на предмет следующих моментов

- сейчас для установки зависимостей используется pip, я бы хотел что бы это был uv, причем в Dockerfile зависимости тоже должны ставиться из uv
- сейчас есть два компоуза docker-compose.bot.yml и docker-compose.yml. по логике один лишний, надо почистить
- сейчас в Dockerfile вижу python:3.11-slim нужно убедиться что это версия оптимальная если нет то обновить на последнюю LTS

составь пошаговый план для рефакторинга bot-template
реализуй его шаг за шагом