#!/bin/bash

#################################################################
# OIC3 Credential Manager
#
# Securely manages OAuth JWT credentials using OCI Vault
#################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ID="${OCI_VAULT_ID:-}"
KEY_ID="${OCI_KEY_ID:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

#################################################################
# Functions
#################################################################

show_help() {
    cat <<EOF
OIC3 Credential Manager - JWT Authentication

USAGE:
    $0 <command> [arguments]

COMMANDS:
    store-oauth <env> <client_id> <client_secret> <username> <private_key_path>
                                    Store OAuth JWT credentials in Vault
    get-oauth <env>                 Retrieve OAuth JWT credentials from Vault
    get-oauth-token <env>           Get OAuth access token using JWT
    store-connection <conn_id> <property> <value>
                                    Store connection credential in Vault
    get-connection <conn_id> <property>
                                    Retrieve connection credential from Vault
    list                            List all stored credentials
    delete <secret_name>            Delete a credential from Vault

ENVIRONMENTS:
    dev, test, prod

EXAMPLES:
    # Store OAuth JWT credentials
    $0 store-oauth dev "client-id" "client-secret" "user@example.com" "./private-key.pem"
    
    # Get OAuth token using JWT
    $0 get-oauth-token dev
    
    # Store connection password
    $0 store-connection DB_CONN password "mySecretPassword"
    
    # Retrieve connection password
    $0 get-connection DB_CONN password

CONFIGURATION:
    Set these environment variables for Vault integration:
    - OCI_VAULT_ID: OCID of your OCI Vault
    - OCI_KEY_ID: OCID of your encryption key

    Without Vault, credentials are stored in ~/.oic-credentials (not recommended for production)

EOF
}

#################################################################
# Vault Operations
#################################################################

use_vault() {
    [ -n "$VAULT_ID" ] && [ -n "$KEY_ID" ]
}

store_in_vault() {
    local secret_name="$1"
    local secret_value="$2"
    
    if use_vault; then
        echo "Storing $secret_name in OCI Vault..."
        
        # Check if secret already exists
        existing_secret=$(oci vault secret list \
            --compartment-id "$OCI_COMPARTMENT_ID" \
            --vault-id "$VAULT_ID" \
            --name "$secret_name" \
            --query 'data[0].id' \
            --raw-output 2>/dev/null || echo "")
        
        if [ -n "$existing_secret" ] && [ "$existing_secret" != "null" ]; then
            # Update existing secret
            oci vault secret update-base64 \
                --secret-id "$existing_secret" \
                --secret-content-content "$(echo -n "$secret_value" | base64)" \
                > /dev/null
        else
            # Create new secret
            oci vault secret create-base64 \
                --compartment-id "$OCI_COMPARTMENT_ID" \
                --vault-id "$VAULT_ID" \
                --key-id "$KEY_ID" \
                --secret-name "$secret_name" \
                --secret-content-content "$(echo -n "$secret_value" | base64)" \
                > /dev/null
        fi
        
        echo -e "${GREEN}✓ Stored in Vault${NC}"
    else
        # Fallback to local file
        mkdir -p ~/.oic-credentials
        chmod 700 ~/.oic-credentials
        echo "$secret_value" > ~/.oic-credentials/"$secret_name"
        chmod 600 ~/.oic-credentials/"$secret_name"
        echo -e "${YELLOW}⚠ Stored locally (Vault not configured)${NC}"
    fi
}

get_from_vault() {
    local secret_name="$1"
    
    if use_vault; then
        # Get from Vault
        secret_id=$(oci vault secret list \
            --compartment-id "$OCI_COMPARTMENT_ID" \
            --vault-id "$VAULT_ID" \
            --name "$secret_name" \
            --query 'data[0].id' \
            --raw-output 2>/dev/null || echo "")
        
        if [ -z "$secret_id" ] || [ "$secret_id" == "null" ]; then
            echo ""
            return 1
        fi
        
        oci secrets secret-bundle get \
            --secret-id "$secret_id" \
            --query 'data."secret-bundle-content".content' \
            --raw-output | base64 -d
    else
        # Get from local file
        if [ -f ~/.oic-credentials/"$secret_name" ]; then
            cat ~/.oic-credentials/"$secret_name"
        else
            echo ""
            return 1
        fi
    fi
}

#################################################################
# OAuth JWT Operations
#################################################################

store_oauth() {
    local env="$1"
    local client_id="$2"
    local client_secret="$3"
    local username="$4"
    local private_key_path="$5"
    
    if [ ! -f "$private_key_path" ]; then
        echo -e "${RED}Error: Private key not found: $private_key_path${NC}"
        exit 1
    fi
    
    # Read private key content
    private_key_content=$(cat "$private_key_path")
    
    # Store each component
    store_in_vault "oic-oauth-${env}-client-id" "$client_id"
    store_in_vault "oic-oauth-${env}-client-secret" "$client_secret"
    store_in_vault "oic-oauth-${env}-username" "$username"
    store_in_vault "oic-oauth-${env}-private-key" "$private_key_content"
    
    echo -e "${GREEN}✓ OAuth JWT credentials stored for $env${NC}"
}

get_oauth() {
    local env="$1"
    
    client_id=$(get_from_vault "oic-oauth-${env}-client-id")
    client_secret=$(get_from_vault "oic-oauth-${env}-client-secret")
    username=$(get_from_vault "oic-oauth-${env}-username")
    
    if [ -z "$client_id" ]; then
        echo -e "${RED}Error: OAuth credentials not found for $env${NC}"
        exit 1
    fi
    
    echo "OAUTH_CLIENT_ID=$client_id"
    echo "OAUTH_CLIENT_SECRET=$client_secret"
    echo "OAUTH_USERNAME=$username"
    echo "# Private key stored separately"
}

get_oauth_token() {
    local env="$1"
    
    echo "Getting OAuth token for $env environment..." >&2
    
    # Get credentials from Vault
    client_id=$(get_from_vault "oic-oauth-${env}-client-id")
    client_secret=$(get_from_vault "oic-oauth-${env}-client-secret")
    username=$(get_from_vault "oic-oauth-${env}-username")
    private_key=$(get_from_vault "oic-oauth-${env}-private-key")
    
    if [ -z "$client_id" ] || [ -z "$username" ]; then
        echo -e "${RED}Error: OAuth credentials not found for $env${NC}" >&2
        exit 1
    fi
    
    # Save private key to temp file
    temp_key=$(mktemp)
    echo "$private_key" > "$temp_key"
    chmod 600 "$temp_key"
    
    # Generate JWT token
    jwt_token=$("$SCRIPT_DIR/generate-jwt.sh" "$username" "$client_id" "$temp_key")
    
    # Clean up temp file
    rm -f "$temp_key"
    
    if [ -z "$jwt_token" ]; then
        echo -e "${RED}Error: Failed to generate JWT token${NC}" >&2
        exit 1
    fi
    
    # Get IDCS URL from environment or terraform.tfvars
    idcs_url="${IDCS_URL:-}"
    if [ -z "$idcs_url" ]; then
        echo -e "${RED}Error: IDCS_URL not set${NC}" >&2
        exit 1
    fi
    
    # Exchange JWT for access token
    basic_auth=$(echo -n "${client_id}:${client_secret}" | base64)
    
    access_token=$(curl -s -X POST "${idcs_url}/oauth2/v1/token" \
        -H "Authorization: Basic $basic_auth" \
        -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
        -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt_token}&scope=urn:opc:resource:consumer::all" \
        | jq -r '.access_token')
    
    if [ "$access_token" == "null" ] || [ -z "$access_token" ]; then
        echo -e "${RED}Error: Failed to get access token${NC}" >&2
        exit 1
    fi
    
    echo "$access_token"
}

#################################################################
# Connection Credential Operations
#################################################################

store_connection() {
    local conn_id="$1"
    local property="$2"
    local value="$3"
    
    store_in_vault "oic-connection-${conn_id}-${property}" "$value"
    echo -e "${GREEN}✓ Connection credential stored${NC}"
}

get_connection() {
    local conn_id="$1"
    local property="$2"
    
    get_from_vault "oic-connection-${conn_id}-${property}"
}

#################################################################
# List and Delete Operations
#################################################################

list_credentials() {
    if use_vault; then
        echo "Credentials in OCI Vault:"
        oci vault secret list \
            --compartment-id "$OCI_COMPARTMENT_ID" \
            --vault-id "$VAULT_ID" \
            --query 'data[*].[name, "lifecycle-state"]' \
            --output table
    else
        echo "Local credentials:"
        if [ -d ~/.oic-credentials ]; then
            ls -1 ~/.oic-credentials/
        else
            echo "None"
        fi
    fi
}

delete_credential() {
    local secret_name="$1"
    
    if use_vault; then
        secret_id=$(oci vault secret list \
            --compartment-id "$OCI_COMPARTMENT_ID" \
            --vault-id "$VAULT_ID" \
            --name "$secret_name" \
            --query 'data[0].id' \
            --raw-output)
        
        if [ -n "$secret_id" ] && [ "$secret_id" != "null" ]; then
            oci vault secret schedule-secret-deletion \
                --secret-id "$secret_id" \
                --time-of-deletion "$(date -u -d '+30 days' +%Y-%m-%dT%H:%M:%SZ)"
            echo -e "${GREEN}✓ Scheduled for deletion in 30 days${NC}"
        else
            echo -e "${RED}Error: Secret not found${NC}"
        fi
    else
        if [ -f ~/.oic-credentials/"$secret_name" ]; then
            rm ~/.oic-credentials/"$secret_name"
            echo -e "${GREEN}✓ Deleted${NC}"
        else
            echo -e "${RED}Error: Credential not found${NC}"
        fi
    fi
}

#################################################################
# Main
#################################################################

case "${1:-}" in
    store-oauth)
        if [ $# -ne 6 ]; then
            echo "Usage: $0 store-oauth <env> <client_id> <client_secret> <username> <private_key_path>"
            exit 1
        fi
        store_oauth "$2" "$3" "$4" "$5" "$6"
        ;;
    get-oauth)
        if [ $# -ne 2 ]; then
            echo "Usage: $0 get-oauth <env>"
            exit 1
        fi
        get_oauth "$2"
        ;;
    get-oauth-token)
        if [ $# -ne 2 ]; then
            echo "Usage: $0 get-oauth-token <env>"
            exit 1
        fi
        get_oauth_token "$2"
        ;;
    store-connection)
        if [ $# -ne 4 ]; then
            echo "Usage: $0 store-connection <conn_id> <property> <value>"
            exit 1
        fi
        store_connection "$2" "$3" "$4"
        ;;
    get-connection)
        if [ $# -ne 3 ]; then
            echo "Usage: $0 get-connection <conn_id> <property>"
            exit 1
        fi
        get_connection "$2" "$3"
        ;;
    list)
        list_credentials
        ;;
    delete)
        if [ $# -ne 2 ]; then
            echo "Usage: $0 delete <secret_name>"
            exit 1
        fi
        delete_credential "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
