# Single entry point. `make help` lists targets.
SHELL := /bin/bash
.DEFAULT_GOAL := help

ROOT   := $(shell pwd)
TF_DIR := infra/snowflake/terraform
PY     := .venv/bin/python
OPA_IMAGE      := openpolicyagent/opa:1.10.1
CONFTEST_IMAGE := openpolicyagent/conftest:v0.63.0

# load .env (key passphrases etc.) into every recipe
ifneq (,$(wildcard .env))
include .env
export
endif
export TF_VAR_terraform_private_key_passphrase = $(SNOWFLAKE_TERRAFORM_KEY_PASSPHRASE)

.PHONY: help
help: ## list targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' Makefile | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

# --- setup -------------------------------------------------------------------
.PHONY: venv keys bootstrap-sql
venv: ## create .venv and install locked dev requirements
	uv venv --python 3.11 .venv && uv pip install -r requirements.txt --python $(PY)

keys: ## generate service-user RSA key pairs into secrets/ (idempotent)
	scripts/generate_keys.sh

bootstrap-sql: keys ## render the one-time ACCOUNTADMIN bootstrap SQL
	scripts/render_bootstrap.sh

# --- terraform (Snowflake as code) ----------------------------------------------
.PHONY: tf-init tf-plan tf-apply policy policy-test
tf-init: ## terraform init
	terraform -chdir=$(TF_DIR) init -input=false

tf-plan: ## fmt + validate + plan (writes tfplan) + policy check
	terraform -chdir=$(TF_DIR) fmt -check -recursive
	terraform -chdir=$(TF_DIR) validate
	terraform -chdir=$(TF_DIR) plan -input=false -out=tfplan
	$(MAKE) policy

policy: ## evaluate the saved plan against infra/policies (conftest)
	terraform -chdir=$(TF_DIR) show -json tfplan > $(TF_DIR)/tfplan.json
	docker run --rm -v $(ROOT):/w -w /w $(CONFTEST_IMAGE) test --all-namespaces \
	  -p infra/policies $(TF_DIR)/tfplan.json
	@rm -f $(TF_DIR)/tfplan.json

policy-test: ## unit-test the Rego policies
	docker run --rm -v $(ROOT)/infra/policies:/p -w /p $(OPA_IMAGE) test -v .

tf-apply: ## apply the reviewed tfplan (run tf-plan first)
	terraform -chdir=$(TF_DIR) apply -input=false tfplan

# --- docker stack (Airflow 3.3 + BI) ------------------------------------------------
COMPOSE := docker compose -f docker/docker-compose.yml --env-file .env
.PHONY: env up down ps logs airflow
env: ## generate .env runtime secrets (idempotent)
	scripts/init_env.sh

up: ## build + start the stack (Airflow UI on :$(AIRFLOW_PORT))
	mkdir -p logs
	$(COMPOSE) up -d --build

down: ## stop the stack (keeps volumes)
	$(COMPOSE) down

ps: ## container status
	$(COMPOSE) ps

logs: ## tail logs, e.g. make logs s=airflow-scheduler
	$(COMPOSE) logs -f --tail=100 $(s)

airflow: ## run an airflow CLI command, e.g. make airflow c="dags list"
	$(COMPOSE) exec airflow-scheduler airflow $(c)

# --- quality gates ------------------------------------------------------------------
DBT_ENV := DBT_PROFILES_DIR=$(ROOT)/dbt DBT_PRIVATE_KEY_PATH=$(ROOT)/secrets/snowflake/svc_dbt/rsa_key.p8
.PHONY: lint test test-dags dbt-build dbt-docs check
lint: ## ruff + terraform fmt + dbt parse
	.venv/bin/ruff check dags config scripts tests docker/superset
	.venv/bin/ruff format --check dags config scripts tests docker/superset
	terraform -chdir=$(TF_DIR) fmt -check -recursive
	cd dbt && $(DBT_ENV) ../.venv/bin/dbt parse --quiet

test: ## unit tests (no Airflow/Snowflake needed)
	.venv/bin/python -m pytest -q tests/test_open_meteo.py

test-dags: ## DAG integrity tests inside the Airflow image
	$(COMPOSE) run --rm --no-deps -e HOME=/tmp -v $(ROOT)/tests:/opt/airflow/tests --entrypoint bash airflow-scheduler \
	  -c "python -m pytest -q -p no:cacheprovider /opt/airflow/tests/test_dag_integrity.py"

dbt-build: ## dbt build (seed/run/test/snapshot) as SVC_DBT from the host
	cd dbt && $(DBT_ENV) ../.venv/bin/dbt build

check: lint test policy-test ## every local gate (run before opening a PR)

# --- report ---------------------------------------------------------------------------
.PHONY: report
report: ## regenerate table appendix from Snowflake, build + compress the LaTeX report
	.venv/bin/python report/build_tables.py
	cd report && latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex >/dev/null
	gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -dCompatibilityLevel=1.6 -dPDFSETTINGS=/ebook \
	  -dColorImageResolution=130 -sOutputFile=report/weather_prediction_analytics_report.pdf report/main.pdf
	@ls -la report/weather_prediction_analytics_report.pdf
