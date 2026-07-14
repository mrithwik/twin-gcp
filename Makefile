.PHONY: setup run run-frontend test lint build-frontend deploy-backend plan apply clean help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Install backend + frontend dependencies
	cd backend && uv venv .venv --python 3.12 && uv pip install -e ".[dev]" --python .venv/bin/python
	cd frontend && npm install
	@if [ ! -f backend/.env ]; then cp backend/.env.example backend/.env; echo "Created backend/.env — edit it with your GEMINI_API_KEY"; fi

run: ## Run the backend locally
	cd backend && .venv/bin/uvicorn app.main:app --reload --port 8000

run-frontend: ## Run the frontend dev server
	cd frontend && npm run dev

test: ## Run backend tests
	cd backend && .venv/bin/pytest -v

lint: ## Run ruff on the backend
	cd backend && .venv/bin/ruff check app tests

build-frontend: ## Production build of the frontend
	cd frontend && npm run build

plan: ## terraform plan
	cd infra/terraform && terraform plan

apply: ## terraform apply
	cd infra/terraform && terraform apply

clean: ## Remove caches and build artifacts
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
	rm -rf frontend/.next frontend/out
