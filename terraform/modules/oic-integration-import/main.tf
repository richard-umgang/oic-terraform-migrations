#################################################################
# OIC3 Integration Import Module
# 
# Imports an integration from .iar file in Object Storage
# and configures environment-specific connection properties
#################################################################

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}

#################################################################
# Variables
#################################################################

variable "oic_url" {
  description = "OIC instance URL"
  type        = string
}

variable "idcs_url" {
  description = "IDCS/IAM domain URL for OAuth"
  type        = string
}

variable "oauth_credentials" {
  description = "OAuth JWT credentials (client_id, client_secret, username, private_key_path)"
  type = object({
    client_id        = string
    client_secret    = string
    username         = string
    private_key_path = string
  })
  sensitive = true
}

variable "jwt_generator_script" {
  description = "Path to JWT generator script"
  type        = string
  default     = "${path.root}/../scripts/generate-jwt.sh"
}

variable "oauth_scope" {
  description = "OAuth scope for OIC access"
  type        = string
  default     = "urn:opc:resource:consumer::all"
}

variable "integration_code" {
  description = "Integration code"
  type        = string
}

variable "integration_version" {
  description = "Integration version"
  type        = string
}

variable "bucket_name" {
  description = "Object Storage bucket name"
  type        = string
}

variable "bucket_namespace" {
  description = "Object Storage namespace"
  type        = string
}

variable "import_path_prefix" {
  description = "Path prefix in bucket where .iar files are stored"
  type        = string
  default     = "integrations/"
}

variable "use_latest" {
  description = "Use the 'latest' .iar file instead of specific version"
  type        = bool
  default     = true
}

variable "connection_updates" {
  description = "Map of connection IDs to property updates"
  type = map(object({
    properties = map(object({
      property_group = string
      property_name  = string
      property_type  = string
      property_value = string
    }))
  }))
  default = {}
}

variable "activate_after_import" {
  description = "Activate the integration after import"
  type        = bool
  default     = false
}

variable "test_connections" {
  description = "Test connections after update"
  type        = bool
  default     = true
}

#################################################################
# Download and Import Integration
#################################################################

resource "null_resource" "import_integration" {
  triggers = {
    integration_code = var.integration_code
    timestamp        = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      # Generate JWT token
      JWT_TOKEN=$(${var.jwt_generator_script} \
        "${var.oauth_credentials.username}" \
        "${var.oauth_credentials.client_id}" \
        "${var.oauth_credentials.private_key_path}")
      
      # Get OAuth access token using JWT
      BASIC_AUTH=$(echo -n "${var.oauth_credentials.client_id}:${var.oauth_credentials.client_secret}" | base64)
      TOKEN=$(curl -s -X POST "${var.idcs_url}/oauth2/v1/token" \
        -H "Authorization: Basic $BASIC_AUTH" \
        -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
        -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=$JWT_TOKEN&scope=${var.oauth_scope}" \
        | jq -r '.access_token')
      
      if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
        echo "Error: Failed to obtain OAuth token"
        exit 1
      fi
      
      # Determine which .iar file to download
      if [ "${var.use_latest}" == "true" ]; then
        IAR_OBJECT_NAME="${var.import_path_prefix}${var.integration_code}-latest.iar"
      else
        # Find the most recent timestamped version
        IAR_OBJECT_NAME=$(oci os object list \
          --bucket-name "${var.bucket_name}" \
          --namespace "${var.bucket_namespace}" \
          --prefix "${var.import_path_prefix}${var.integration_code}-${var.integration_version}-" \
          --query 'data[0].name' \
          --raw-output)
      fi
      
      echo "Downloading: $IAR_OBJECT_NAME"
      
      # Download .iar file from Object Storage
      IAR_FILE="/tmp/${var.integration_code}-import.iar"
      oci os object get \
        --bucket-name "${var.bucket_name}" \
        --namespace "${var.bucket_namespace}" \
        --name "$IAR_OBJECT_NAME" \
        --file "$IAR_FILE"
      
      if [ ! -f "$IAR_FILE" ]; then
        echo "Error: Failed to download .iar file"
        exit 1
      fi
      
      # Import to OIC
      echo "Importing integration to OIC..."
      IMPORT_URL="${var.oic_url}/ic/api/integration/v1/integrations/archive"
      
      RESPONSE=$(curl -X POST "$IMPORT_URL" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$IAR_FILE" \
        -w "\n%{http_code}")
      
      HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
      BODY=$(echo "$RESPONSE" | head -n -1)
      
      if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
        echo "Import successful!"
        echo "$BODY" | jq '.'
      else
        echo "Error: Import failed with HTTP $HTTP_CODE"
        echo "$BODY"
        exit 1
      fi
      
      # Cleanup
      rm -f "$IAR_FILE"
    EOT
  }
}

#################################################################
# Update Connection Properties
#################################################################

resource "null_resource" "update_connections" {
  depends_on = [null_resource.import_integration]
  
  for_each = var.connection_updates
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      # Generate JWT token
      JWT_TOKEN=$(${var.jwt_generator_script} \
        "${var.oauth_credentials.username}" \
        "${var.oauth_credentials.client_id}" \
        "${var.oauth_credentials.private_key_path}")
      
      # Get OAuth access token using JWT
      BASIC_AUTH=$(echo -n "${var.oauth_credentials.client_id}:${var.oauth_credentials.client_secret}" | base64)
      TOKEN=$(curl -s -X POST "${var.idcs_url}/oauth2/v1/token" \
        -H "Authorization: Basic $BASIC_AUTH" \
        -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
        -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=$JWT_TOKEN&scope=${var.oauth_scope}" \
        | jq -r '.access_token')
      
      echo "Updating connection: ${each.key}"
      
      # Build properties JSON
      PROPERTIES_JSON='${jsonencode(each.value.properties)}'
      
      # Update each property
      echo "$PROPERTIES_JSON" | jq -r 'to_entries[] | @json' | while read prop; do
        PROP_NAME=$(echo "$prop" | jq -r '.key')
        PROP_GROUP=$(echo "$prop" | jq -r '.value.property_group')
        PROP_KEY=$(echo "$prop" | jq -r '.value.property_name')
        PROP_TYPE=$(echo "$prop" | jq -r '.value.property_type')
        PROP_VALUE=$(echo "$prop" | jq -r '.value.property_value')
        
        echo "  Setting $PROP_KEY = $PROP_VALUE"
        
        PAYLOAD=$(cat <<EOF
      {
        "propertyGroup": "$PROP_GROUP",
        "propertyName": "$PROP_KEY",
        "propertyType": "$PROP_TYPE",
        "propertyValue": "$PROP_VALUE"
      }
      EOF
      )
        
        curl -X PATCH "${var.oic_url}/ic/api/integration/v1/connections/${each.key}" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d "$PAYLOAD"
      done
      
      echo "Connection ${each.key} updated successfully"
    EOT
  }
}

#################################################################
# Test Connections
#################################################################

resource "null_resource" "test_connections" {
  depends_on = [null_resource.update_connections]
  
  for_each = var.test_connections ? var.connection_updates : {}
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      # Generate JWT token
      JWT_TOKEN=$(${var.jwt_generator_script} \
        "${var.oauth_credentials.username}" \
        "${var.oauth_credentials.client_id}" \
        "${var.oauth_credentials.private_key_path}")
      
      # Get OAuth access token using JWT
      BASIC_AUTH=$(echo -n "${var.oauth_credentials.client_id}:${var.oauth_credentials.client_secret}" | base64)
      TOKEN=$(curl -s -X POST "${var.idcs_url}/oauth2/v1/token" \
        -H "Authorization: Basic $BASIC_AUTH" \
        -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
        -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=$JWT_TOKEN&scope=${var.oauth_scope}" \
        | jq -r '.access_token')
      
      echo "Testing connection: ${each.key}"
      
      RESPONSE=$(curl -X POST "${var.oic_url}/ic/api/integration/v1/connections/${each.key}/test" \
        -H "Authorization: Bearer $TOKEN" \
        -w "\n%{http_code}")
      
      HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
      
      if [ "$HTTP_CODE" -eq 200 ]; then
        echo "✓ Connection ${each.key} test passed"
      else
        echo "✗ Connection ${each.key} test failed (HTTP $HTTP_CODE)"
      fi
    EOT
  }
}

#################################################################
# Activate Integration
#################################################################

resource "null_resource" "activate_integration" {
  depends_on = [null_resource.test_connections]
  
  count = var.activate_after_import ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      # Generate JWT token
      JWT_TOKEN=$(${var.jwt_generator_script} \
        "${var.oauth_credentials.username}" \
        "${var.oauth_credentials.client_id}" \
        "${var.oauth_credentials.private_key_path}")
      
      # Get OAuth access token using JWT
      BASIC_AUTH=$(echo -n "${var.oauth_credentials.client_id}:${var.oauth_credentials.client_secret}" | base64)
      TOKEN=$(curl -s -X POST "${var.idcs_url}/oauth2/v1/token" \
        -H "Authorization: Basic $BASIC_AUTH" \
        -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
        -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=$JWT_TOKEN&scope=${var.oauth_scope}" \
        | jq -r '.access_token')
      
      echo "Activating integration: ${var.integration_code}|${var.integration_version}"
      
      curl -X POST "${var.oic_url}/ic/api/integration/v1/integrations/${var.integration_code}|${var.integration_version}/activate" \
        -H "Authorization: Bearer $TOKEN"
      
      echo "Integration activated successfully"
    EOT
  }
}

#################################################################
# Outputs
#################################################################

output "import_timestamp" {
  description = "Timestamp when import was performed"
  value       = timestamp()
}

output "integration_code" {
  description = "Integration code that was imported"
  value       = var.integration_code
}

output "connections_updated" {
  description = "List of connections that were updated"
  value       = keys(var.connection_updates)
}
