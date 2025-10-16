#################################################################
# OIC3 Complete Migration Workflow
#
# Orchestrates export from DEV and import to TEST/PROD
# with environment-specific connection configurations
#################################################################

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
  
  # Optional: Configure remote state in Object Storage
  # backend "http" {
  #   address = "https://objectstorage.us-phoenix-1.oraclecloud.com/..."
  # }
}

#################################################################
# Variables
#################################################################

variable "environment" {
  description = "Target environment (dev, test, prod)"
  type        = string
  
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test, or prod"
  }
}

variable "oic_instances" {
  description = "OIC instance configurations for each environment"
  type = map(object({
    url           = string
    instance_name = string
    idcs_url      = string
  }))
}

variable "oauth_credentials" {
  description = "OAuth JWT credentials for each environment"
  type = map(object({
    client_id        = string
    client_secret    = string
    username         = string
    private_key_path = string
  }))
  sensitive = true
}

variable "bucket_config" {
  description = "Object Storage bucket configuration"
  type = object({
    name           = string
    namespace      = string
    compartment_id = string
  })
}

variable "integrations_to_migrate" {
  description = "List of integrations to migrate with their connection configs"
  type = list(object({
    id      = string  # e.g., "HELLO_WORLD|01.00.0000"
    code    = string  # e.g., "HELLO_WORLD"
    version = string  # e.g., "01.00.0000"
    
    connections = map(object({
      id = string
      test_properties = optional(map(object({
        property_group = string
        property_name  = string
        property_type  = string
        property_value = string
      })), {})
      prod_properties = optional(map(object({
        property_group = string
        property_name  = string
        property_type  = string
        property_value = string
      })), {})
    }))
  }))
}

#################################################################
# Local Values
#################################################################

locals {
  is_dev  = var.environment == "dev"
  is_test = var.environment == "test"
  is_prod = var.environment == "prod"
  
  current_oic         = var.oic_instances[var.environment]
  current_credentials = var.oauth_credentials[var.environment]
  
  # Export path includes environment
  export_path = "integrations/${var.environment}/"
}

#################################################################
# DEV: Export Integrations
#################################################################

module "export_integrations" {
  source = "./modules/oic-integration-export"
  
  # Only run exports when environment is DEV
  for_each = local.is_dev ? { for i in var.integrations_to_migrate : i.code => i } : {}
  
  oic_url            = local.current_oic.url
  idcs_url           = local.current_oic.idcs_url
  oauth_credentials  = local.current_credentials
  
  integration_id      = each.value.id
  integration_code    = each.value.code
  integration_version = each.value.version
  
  bucket_name       = var.bucket_config.name
  bucket_namespace  = var.bucket_config.namespace
  export_path_prefix = local.export_path
}

#################################################################
# TEST/PROD: Import Integrations
#################################################################

module "import_integrations" {
  source = "./modules/oic-integration-import"
  
  # Only run imports when environment is TEST or PROD
  for_each = !local.is_dev ? { for i in var.integrations_to_migrate : i.code => i } : {}
  
  oic_url            = local.current_oic.url
  idcs_url           = local.current_oic.idcs_url
  oauth_credentials  = local.current_credentials
  
  integration_code    = each.value.code
  integration_version = each.value.version
  
  bucket_name        = var.bucket_config.name
  bucket_namespace   = var.bucket_config.namespace
  import_path_prefix = "integrations/dev/"  # Always import from DEV exports
  
  use_latest = true
  
  # Environment-specific connection configurations
  connection_updates = {
    for conn_key, conn in each.value.connections : conn.id => {
      properties = local.is_test ? conn.test_properties : conn.prod_properties
    }
  }
  
  test_connections      = true
  activate_after_import = local.is_prod ? false : true  # Manual activation for PROD
}

#################################################################
# Outputs
#################################################################

output "environment" {
  description = "Current environment"
  value       = var.environment
}

output "oic_instance" {
  description = "Current OIC instance"
  value = {
    name = local.current_oic.instance_name
    url  = local.current_oic.url
  }
}

output "operation" {
  description = "Operation performed (export or import)"
  value       = local.is_dev ? "export" : "import"
}

output "integrations_processed" {
  description = "List of integrations processed"
  value = [
    for i in var.integrations_to_migrate : {
      code    = i.code
      version = i.version
      id      = i.id
    }
  ]
}

output "export_results" {
  description = "Export results (DEV only)"
  value = local.is_dev ? {
    for k, v in module.export_integrations : k => {
      integration_id = v.integration_id
      storage_path   = v.object_storage_path
      bucket         = v.bucket_name
    }
  } : null
}

output "import_results" {
  description = "Import results (TEST/PROD only)"
  value = !local.is_dev ? {
    for k, v in module.import_integrations : k => {
      integration_code    = v.integration_code
      connections_updated = v.connections_updated
    }
  } : null
}

output "next_steps" {
  description = "Suggested next steps"
  value = local.is_dev ? [
    "Integrations exported to Object Storage",
    "Review exports: make list-backups",
    "Import to TEST: make import-test",
  ] : local.is_test ? [
    "Integrations imported to TEST",
    "Run tests: make test ENV=test",
    "If tests pass, promote to PROD: make import-prod",
  ] : [
    "Integrations imported to PROD",
    "Manual activation required for PROD",
    "Activate via OIC console or: make activate-prod",
    "Run smoke tests: make smoke-test ENV=prod",
  ]
}
