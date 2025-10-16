#################################################################
# OIC3 Terraform Migration - Makefile
#
# Common operations for OIC integration migrations
#################################################################

.PHONY: help init plan apply destroy validate format clean
.PHONY: export-dev import-test import-prod
.PHONY: promote-to-test promote-to-prod
.PHONY: test test-connections smoke-test
.PHONY: list-integrations status backup list-backups restore

# Default environment
ENV ?= dev

# Terraform directory
TF_DIR = terraform

# Load environment-specific credentials from environment variables
export TF_VAR_environment = $(ENV)

# JWT credentials will be passed via environment variables
# OAUTH_CLIENT_ID_DEV, OAUTH_CLIENT_SECRET_DEV, etc.

#################################################################
# Help
#################################################################

help:
	@echo "OIC3 Terraform Migration - Available Commands"
	@echo ""
	@echo "  Setup & Configuration (JWT Authentication):"
	@echo "    init                      Initialize Terraform"
	@echo "    validate                  Validate Terraform configuration"
	@echo "    format                    Format Terraform files"
	@echo ""
	@echo "  Discovery & Status:"
	@echo "    list-integrations ENV=<env>  List all integrations and generate reports"
	@echo "    status ENV=<env>             Show current deployment status"
	@echo ""
	@echo "  Export Operations (DEV):"
	@echo "    export-dev                Export integrations from DEV"
	@echo "    plan ENV=dev              Show export plan"
	@echo ""
	@echo "  Import Operations (TEST/PROD):"
	@echo "    import-test               Import to TEST environment"
	@echo "    import-prod               Import to PROD (with confirmation)"
	@echo "    plan ENV=<env>            Show import plan"
	@echo ""
	@echo "  Complete Workflows:"
	@echo "    promote-to-test           Export from DEV → Import to TEST"
	@echo "    promote-to-prod           Export from DEV → Import to PROD"
	@echo ""
	@echo "  Testing:"
	@echo "    test ENV=<env>            Run all integration tests"
	@echo "    test-connections ENV=<env> Test connections only"
	@echo "    smoke-test ENV=<env>      Quick smoke test"
	@echo "    test-auth ENV=<env>       Test JWT authentication"
	@echo ""
	@echo "  Backup & Recovery:"
	@echo "    backup ENV=<env>          Backup integrations"
	@echo "    list-backups              List available backups"
	@echo "    restore ENV=<env> DATE=<date> Restore from backup"
	@echo ""
	@echo "  Utilities:"
	@echo "    outputs ENV=<env>         Show Terraform outputs"
	@echo "    clean                     Clean temporary files"
	@echo "    logs                      Show recent logs"
	@echo ""
	@echo "Examples:"
	@echo "  make list-integrations ENV=dev"
	@echo "  make export-dev"
	@echo "  make import-test"
	@echo "  make test ENV=test"
	@echo ""

#################################################################
# Setup & Configuration
#################################################################

init:
	@echo "Initializing Terraform..."
	cd $(TF_DIR) && terraform init

validate:
	@echo "Validating Terraform configuration..."
	cd $(TF_DIR) && terraform validate

format:
	@echo "Formatting Terraform files..."
	cd $(TF_DIR) && terraform fmt -recursive

#################################################################
# Discovery & Status
#################################################################

list-integrations:
	@echo "Discovering integrations in $(ENV)..."
	./scripts/list-integrations.sh $(ENV)

status:
	@echo "Getting status for $(ENV) environment..."
	cd $(TF_DIR) && terraform show

#################################################################
# Terraform Operations
#################################################################

plan:
	@echo "Planning for $(ENV) environment..."
	@if [ "$(ENV)" = "dev" ]; then \
		echo "Operation: EXPORT from DEV"; \
	else \
		echo "Operation: IMPORT to $(ENV)"; \
	fi
	cd $(TF_DIR) && terraform plan \
		-var="environment=$(ENV)" \
		-var="oauth_credentials={ \
			$(ENV) = { \
				client_id = \"$(OAUTH_CLIENT_ID_$(shell echo $(ENV) | tr '[:lower:]' '[:upper:]'))\", \
				client_secret = \"$(OAUTH_CLIENT_SECRET_$(shell echo $(ENV) | tr '[:lower:]' '[:upper:]'))\", \
				username = \"$(OAUTH_USERNAME_$(shell echo $(ENV) | tr '[:lower:]' '[:upper:]'))\", \
				private_key_path = \"$(OAUTH_PRIVATE_KEY_$(shell echo $(ENV) | tr '[:lower:]' '[:upper:]'))\" \
			} \
		}"

apply:
	@echo "Applying changes for $(ENV) environment..."
	cd $(TF_DIR) && terraform apply \
		-var="environment=$(ENV)" \
		-var="oauth_credentials={ \
			$(ENV) = { \
				client_id = \"$(OAUTH_CLIENT_ID_$(shell echo $(ENV) | tr '[:lower:]' '[:upper:]'))\", \
				client_secret = \"$(OAUTH_CLIENT_SECRET_$(shell echo $(ENV) | tr '[:lower:]' '[:upper:]'))\", \
				username = \"$(OAUTH_USERNAME_$(shell echo $(ENV) | tr '[:lower:]' '[:upper:]'))\", \
				private_key_path = \"$(OAUTH_PRIVATE_KEY_$(shell echo $(ENV) | tr '[:lower:]' '[:upper:]'))\" \
			} \
		}" \
		-auto-approve

outputs:
	@echo "Outputs for $(ENV) environment:"
	cd $(TF_DIR) && terraform output

#################################################################
# Export Operations
#################################################################

export-dev:
	@echo "Exporting integrations from DEV..."
	@$(MAKE) plan ENV=dev
	@read -p "Apply export? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(MAKE) apply ENV=dev; \
		echo "Export complete!"; \
		$(MAKE) outputs ENV=dev; \
	fi

#################################################################
# Import Operations
#################################################################

import-test:
	@echo "Importing integrations to TEST..."
	@$(MAKE) plan ENV=test
	@read -p "Apply import to TEST? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(MAKE) apply ENV=test; \
		echo "Import to TEST complete!"; \
		echo "Running tests..."; \
		$(MAKE) test ENV=test; \
	fi

import-prod:
	@echo "⚠️  WARNING: Importing to PRODUCTION ⚠️"
	@echo ""
	@$(MAKE) plan ENV=prod
	@echo ""
	@echo "⚠️  This will import integrations to PRODUCTION"
	@echo "⚠️  Please review the plan carefully"
	@echo ""
	@read -p "Type 'PROD' to confirm: " confirm; \
	if [ "$$confirm" = "PROD" ]; then \
		$(MAKE) apply ENV=prod; \
		echo "Import to PROD complete!"; \
		echo "Note: Manual activation may be required"; \
		$(MAKE) smoke-test ENV=prod; \
	else \
		echo "Import cancelled"; \
		exit 1; \
	fi

#################################################################
# Complete Workflows
#################################################################

promote-to-test:
	@echo "Promoting integrations: DEV → TEST"
	@echo "Step 1: Export from DEV"
	@$(MAKE) export-dev
	@echo ""
	@echo "Step 2: Import to TEST"
	@$(MAKE) import-test

promote-to-prod:
	@echo "Promoting integrations: DEV → PROD"
	@echo "Step 1: Export from DEV"
	@$(MAKE) export-dev
	@echo ""
	@echo "Step 2: Import to PROD"
	@$(MAKE) import-prod

#################################################################
# Testing
#################################################################

test:
	@echo "Running integration tests for $(ENV)..."
	./scripts/test-integrations.sh $(ENV)
	@echo ""
	@echo "Test report: test_report_$(ENV).html"

test-connections:
	@echo "Testing connections for $(ENV)..."
	@# TODO: Create separate connection test script
	@echo "Feature coming soon..."

smoke-test:
	@echo "Running smoke test for $(ENV)..."
	./scripts/test-integrations.sh $(ENV)

test-auth:
	@echo "Testing JWT authentication for $(ENV)..."
	./scripts/test-jwt-auth.sh $(ENV)

#################################################################
# Backup & Recovery
#################################################################

backup:
	@echo "Creating backup of $(ENV) integrations..."
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	mkdir -p backups/$(ENV); \
	cd $(TF_DIR) && terraform state pull > ../backups/$(ENV)/terraform-state-$$TIMESTAMP.json; \
	echo "Backup created: backups/$(ENV)/terraform-state-$$TIMESTAMP.json"

list-backups:
	@echo "Available backups:"
	@find backups -type f -name "*.json" 2>/dev/null | sort -r || echo "No backups found"

restore:
	@if [ -z "$(DATE)" ]; then \
		echo "Error: DATE parameter required"; \
		echo "Usage: make restore ENV=test DATE=20240315-120000"; \
		exit 1; \
	fi
	@echo "Restoring $(ENV) from backup $(DATE)..."
	@if [ -f "backups/$(ENV)/terraform-state-$(DATE).json" ]; then \
		cd $(TF_DIR) && terraform state push ../backups/$(ENV)/terraform-state-$(DATE).json; \
		echo "Restore complete!"; \
	else \
		echo "Error: Backup not found: backups/$(ENV)/terraform-state-$(DATE).json"; \
		exit 1; \
	fi

#################################################################
# Utilities
#################################################################

clean:
	@echo "Cleaning temporary files..."
	rm -rf /tmp/oic-exports/*
	rm -rf /tmp/oic-imports/*
	rm -f test_report_*.html
	rm -f terraform-debug.log
	@echo "Clean complete!"

logs:
	@echo "Recent logs:"
	@if [ -f terraform-debug.log ]; then \
		tail -n 50 terraform-debug.log; \
	else \
		echo "No debug log found. Set TF_LOG=DEBUG to enable."; \
	fi

destroy:
	@echo "⚠️  WARNING: This will destroy Terraform-managed resources"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd $(TF_DIR) && terraform destroy -var="environment=$(ENV)"; \
	fi

#################################################################
# Development Helpers
#################################################################

.PHONY: dev-setup dev-test dev-clean

dev-setup:
	@echo "Setting up development environment..."
	@chmod +x scripts/*.sh
	@$(MAKE) init
	@$(MAKE) validate
	@echo "Development environment ready!"

dev-test:
	@echo "Running development tests..."
	@$(MAKE) test-auth ENV=dev
	@echo "Development tests complete!"

dev-clean:
	@echo "Cleaning development environment..."
	@$(MAKE) clean
	cd $(TF_DIR) && rm -rf .terraform .terraform.lock.hcl
	@echo "Development environment cleaned!"
