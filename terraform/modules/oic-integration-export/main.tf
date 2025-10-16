#################################################################
# OIC3 Integration Export Module
# 
# Exports an integration (with connections) from OIC as .iar file
# and stores it in OCI Object Storage
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
  description = "OIC instance URL (e.g., https://your-oic.integration.ocp.oraclecloud.com)"
  type        = string
}

variable "idcs_url" {
  description = "IDCS/IAM domain URL for OAuth (e.g., https://idcs-xxxxx.identity.oraclecloud.com)"
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

variable "integration_id" {
  description = "Integration ID (e.g., 'HELLO_WORLD|01.00.0000')"
  type        = string
}

variable "integration_code" {
  description = "Integration code (e.g., 'HELLO_WORLD')"
  type        = string
}

variable "integration_version" {
  description = "Integration version (e.g., '01.00.0000')"
  type        = string
}

variable "bucket_name" {
  description = "Object Storage bucket name for storing .iar files"
  type        = string
}

variable "bucket_namespace" {
  description = "Object Storage namespace"
  type        = string
}

variable "export_path_prefix" {
  description = "Path prefix in bucket (e.g., 'integrations/dev/')"
  type        = string
  default     = "integrations/"
}

#################################################################
# Export Integration
#################################################################

resource "null_resource" "export_integration" {
  triggers = {
    integration_id = var.integration_id
    timestamp      = timestamp()
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
      
      # Export integration
      echo "Exporting integration: ${var.integration_id}"
      EXPORT_URL="${var.oic_url}/ic/api/integration/v1/integrations/${var.integration_id}/archive"
      
      TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
      EXPORT_FILE="/tmp/${var.integration_code}-${var.integration_version}-$TIMESTAMP.iar"
      
      curl -X GET "$EXPORT_URL" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/octet-stream" \
        -o "$EXPORT_FILE"
      
      if [ ! -f "$EXPORT_FILE" ] || [ ! -s "$EXPORT_FILE" ]; then
        echo "Error: Export file not created or empty"
        exit 1
      fi
      
      echo "Export successful: $EXPORT_FILE"
      
      # Create metadata file
      METADATA_FILE="$EXPORT_FILE.metadata.json"
      cat > "$METADATA_FILE" <<EOF
      {
        "integration_id": "${var.integration_id}",
        "integration_code": "${var.integration_code}",
        "integration_version": "${var.integration_version}",
        "export_timestamp": "$TIMESTAMP",
        "export_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "source_oic_url": "${var.oic_url}",
        "exported_by": "terraform"
      }
      EOF
      
      # Upload to Object Storage
      echo "Uploading to Object Storage..."
      oci os object put \
        --bucket-name "${var.bucket_name}" \
        --namespace "${var.bucket_namespace}" \
        --file "$EXPORT_FILE" \
        --name "${var.export_path_prefix}${var.integration_code}-${var.integration_version}-$TIMESTAMP.iar" \
        --force
      
      # Upload metadata
      oci os object put \
        --bucket-name "${var.bucket_name}" \
        --namespace "${var.bucket_namespace}" \
        --file "$METADATA_FILE" \
        --name "${var.export_path_prefix}${var.integration_code}-${var.integration_version}-$TIMESTAMP.iar.metadata.json" \
        --force
      
      # Create/update "latest" symlink
      oci os object put \
        --bucket-name "${var.bucket_name}" \
        --namespace "${var.bucket_namespace}" \
        --file "$EXPORT_FILE" \
        --name "${var.export_path_prefix}${var.integration_code}-latest.iar" \
        --force
      
      echo "Upload complete!"
      echo "Exported: ${var.export_path_prefix}${var.integration_code}-${var.integration_version}-$TIMESTAMP.iar"
      
      # Cleanup
      rm -f "$EXPORT_FILE" "$METADATA_FILE"
    EOT
  }
}

#################################################################
# Outputs
#################################################################

output "export_timestamp" {
  description = "Timestamp when export was performed"
  value       = timestamp()
}

output "integration_id" {
  description = "Integration ID that was exported"
  value       = var.integration_id
}

output "object_storage_path" {
  description = "Path in Object Storage where .iar file was stored"
  value       = "${var.export_path_prefix}${var.integration_code}-${var.integration_version}"
}

output "bucket_name" {
  description = "Object Storage bucket name"
  value       = var.bucket_name
}
