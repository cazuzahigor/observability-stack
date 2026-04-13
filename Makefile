.PHONY: render up down restart logs validate ps

render:
	@set -a; . ./.env; set +a; \
	envsubst < alertmanager/alertmanager.tmpl.yml > alertmanager/alertmanager.yml
	@echo "Rendered alertmanager/alertmanager.yml"

validate: render
	@docker run --rm --entrypoint promtool \
		-v $$PWD/prometheus:/etc/prometheus prom/prometheus:v2.55.1 \
		check config /etc/prometheus/prometheus.yml
	@docker run --rm --entrypoint amtool \
		-v $$PWD/alertmanager:/etc/alertmanager prom/alertmanager:v0.27.0 \
		check-config /etc/alertmanager/alertmanager.yml

up: render
	docker compose up -d

down:
	docker compose down

restart: render
	docker compose up -d --force-recreate alertmanager

logs:
	docker compose logs -f --tail=50

ps:
	docker compose ps
