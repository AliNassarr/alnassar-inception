NAME           := inception
SRC_DIR        := srcs
COMPOSE_FILE   := $(SRC_DIR)/docker-compose.yml
ENV_FILE       := $(SRC_DIR)/.env
SECRETS_DIR    := secrets

COMPOSE_CMD    := $(shell command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && echo "docker compose" || echo "docker-compose")

PROJECT_NAME   := $(shell sed -n 's/^COMPOSE_PROJECT_NAME=\(.*\)/\1/p' $(ENV_FILE) 2>/dev/null | tr -d '\r"')
HOST_DB_PATH   := $(shell sed -n 's/^HOST_DB_PATH=\(.*\)/\1/p'            $(ENV_FILE) 2>/dev/null | tr -d '\r"')
HOST_WP_PATH   := $(shell sed -n 's/^HOST_WP_PATH=\(.*\)/\1/p'            $(ENV_FILE) 2>/dev/null | tr -d '\r"')

ifeq ($(PROJECT_NAME),)
	PROJECT_NAME := inception
endif
ifeq ($(HOST_DB_PATH),)
	HOST_DB_PATH := /home/alnassar/data/db
endif
ifeq ($(HOST_WP_PATH),)
	HOST_WP_PATH := /home/alnassar/data/wp
endif

define ensure_env
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "[ERROR] Missing $(ENV_FILE) file."; \
		exit 1; \
	fi
endef

define ensure_dirs
	@mkdir -p "$(HOST_DB_PATH)" "$(HOST_WP_PATH)" 2>/dev/null || true
endef

define ensure_secrets
	@for f in db_password.txt db_root_password.txt wp_admin_password.txt wp_user_password.txt ; do \
		if [ ! -f "$(SECRETS_DIR)/$$f" ]; then \
			echo "[ERROR] Missing secret file: $(SECRETS_DIR)/$$f"; \
			exit 1; \
		fi; \
	done
endef

.PHONY: all up down start stop restart status logs clean fclean re help

all: up

up: ## Build and start services in background
	$(call ensure_env)
	$(call ensure_dirs)
	$(call ensure_secrets)
	$(COMPOSE_CMD) -f $(COMPOSE_FILE) up -d --build

down: ## Stop and remove containers and networks
	$(COMPOSE_CMD) -f $(COMPOSE_FILE) down

start: ## Start existing stopped containers
	$(COMPOSE_CMD) -f $(COMPOSE_FILE) start

stop: ## Stop running containers without removing them
	$(COMPOSE_CMD) -f $(COMPOSE_FILE) stop

restart: ## Restart all services
	$(COMPOSE_CMD) -f $(COMPOSE_FILE) restart

status: ## Show status of containers
	$(COMPOSE_CMD) -f $(COMPOSE_FILE) ps

logs: ## Follow service logs in real time
	$(COMPOSE_CMD) -f $(COMPOSE_FILE) logs -f

clean: down ## Stop containers and remove networks

fclean: clean ## Full cleanup: remove containers, images, volumes, and host data
	@echo "[INFO] Removing host data directories..."
	@rm -rf "$(HOST_DB_PATH)" "$(HOST_WP_PATH)" 2>/dev/null || sudo rm -rf "$(HOST_DB_PATH)" "$(HOST_WP_PATH)" 2>/dev/null || true
	@echo "[INFO] Removing project volumes..."
	@docker volume rm -f $(PROJECT_NAME)_db_data $(PROJECT_NAME)_wp_data db_data wp_data 2>/dev/null || true
	@echo "[INFO] Removing project images..."
	@docker rmi -f mariadb wordpress nginx 2>/dev/null || true
	@echo "[INFO] Cleanup complete."

re: fclean all ## Full rebuild and start from scratch

help: ## Display available Makefile targets
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
