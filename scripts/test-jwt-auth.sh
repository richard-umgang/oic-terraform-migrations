#!/bin/bash

#################################################################
# JWT Authentication Test Script
#
# Validates JWT setup and OIC API access
#################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENV="${1:-dev}"

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}JWT Authentication Test${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo "Environment: $ENV"
echo ""

#################################################################
# Step 1: Check Prerequisites
#################################################################

echo -e "${BLUE}[1/6] Checking prerequisites...${NC}"

# Check for required tools
MISSING_TOOLS=0

if ! command -v jq &> /dev/null; then
    echo -e "${RED}  ✗ jq not found${NC}"
    MISSING_TOOLS=1
else
    echo -e "${GREEN}  ✓ jq found${NC}"
fi

if ! command -v curl &> /dev/null; then
    echo -e "${RED}  ✗ curl not found${NC}"
    MISSING_TOOLS=1
else
    echo -e "${GREEN}  ✓ curl found${NC}"
fi

if ! command -v python3 &> /dev/null && ! command -v node &> /dev/null; then
    echo -e "${RED}  ✗ Neither Python 3 nor Node.js found${NC}"
    MISSING_TOOLS=1
else
    if command -v python3 &> /dev/null; then
        echo -e "${GREEN}  ✓ Python 3 found${NC}"
    else
        echo -e "${GREEN}  ✓ Node.js found${NC}"
    fi
fi

if [ $MISSING_TOOLS -eq 1 ]; then
    echo -e "${RED}Missing required tools. Please install them first.${NC}"
    exit 1
fi

echo ""

#################################################################
# Step 2: Check Configuration
#################################################################

echo -e "${BLUE}[2/6] Checking configuration...${NC}"

if [ ! -f "$SCRIPT_DIR/../terraform/terraform.tfvars" ]; then
    echo -e "${RED}  ✗ terraform.tfvars not found${NC}"
    echo -e "${YELLOW}  Run: cp terraform/terraform.tfvars.example terraform/terraform.tfvars${NC}"
    exit 1
else
    echo -e "${GREEN}  ✓ terraform.tfvars found${NC}"
fi

# Get OIC and IDCS URLs
OIC_URL=$(grep -A 10 "^  ${ENV} = {" "$SCRIPT_DIR/../terraform/terraform.tfvars" | grep "url" | head -1 | sed 's/.*= "\(.*\)"/\1/')
IDCS_URL=$(grep -A 10 "^  ${ENV} = {" "$SCRIPT_DIR/../terraform/terraform.tfvars" | grep "idcs_url" | head -1 | sed 's/.*= "\(.*\)"/\1/')

if [ -z "$OIC_URL" ]; then
    echo -e "${RED}  ✗ OIC URL not found for environment: $ENV${NC}"
    exit 1
else
    echo -e "${GREEN}  ✓ OIC URL: $OIC_URL${NC}"
fi

if [ -z "$IDCS_URL" ]; then
    echo -e "${RED}  ✗ IDCS URL not found for environment: $ENV${NC}"
    exit 1
else
    echo -e "${GREEN}  ✓ IDCS URL: $IDCS_URL${NC}"
fi

echo ""

#################################################################
# Step 3: Check Credentials
#################################################################

echo -e "${BLUE}[3/6] Checking credentials...${NC}"

if [ -z "$OAUTH_CLIENT_ID" ]; then
    echo -e "${YELLOW}  ℹ OAUTH_CLIENT_ID not set in environment${NC}"
    echo -e "${YELLOW}  Checking credential manager...${NC}"
    
    CLIENT_ID=$("$SCRIPT_DIR/manage-credentials.sh" get-oauth "$ENV" 2>/dev/null | grep "OAUTH_CLIENT_ID" | cut -d= -f2)
    
    if [ -z "$CLIENT_ID" ]; then
        echo -e "${RED}  ✗ Credentials not found${NC}"
        echo -e "${YELLOW}  Run: ./scripts/manage-credentials.sh store-oauth $ENV <client_id> <client_secret> <username> <private_key_path>${NC}"
        exit 1
    else
        export OAUTH_CLIENT_ID="$CLIENT_ID"
        echo -e "${GREEN}  ✓ Client ID found${NC}"
    fi
else
    echo -e "${GREEN}  ✓ OAUTH_CLIENT_ID set${NC}"
fi

if [ -z "$OAUTH_CLIENT_SECRET" ]; then
    CLIENT_SECRET=$("$SCRIPT_DIR/manage-credentials.sh" get-oauth "$ENV" 2>/dev/null | grep "OAUTH_CLIENT_SECRET" | cut -d= -f2)
    export OAUTH_CLIENT_SECRET="$CLIENT_SECRET"
fi

if [ -z "$OAUTH_USERNAME" ]; then
    USERNAME=$("$SCRIPT_DIR/manage-credentials.sh" get-oauth "$ENV" 2>/dev/null | grep "OAUTH_USERNAME" | cut -d= -f2)
    export OAUTH_USERNAME="$USERNAME"
fi

if [ -z "$OAUTH_PRIVATE_KEY" ]; then
    echo -e "${YELLOW}  ℹ OAUTH_PRIVATE_KEY not set${NC}"
    echo -e "${YELLOW}  Please provide path to private key:${NC}"
    read -p "  Private key path: " PRIVATE_KEY_PATH
    
    if [ ! -f "$PRIVATE_KEY_PATH" ]; then
        echo -e "${RED}  ✗ Private key not found: $PRIVATE_KEY_PATH${NC}"
        exit 1
    fi
    
    export OAUTH_PRIVATE_KEY="$PRIVATE_KEY_PATH"
    echo -e "${GREEN}  ✓ Private key loaded${NC}"
else
    if [ -f "$OAUTH_PRIVATE_KEY" ]; then
        echo -e "${GREEN}  ✓ Private key found${NC}"
    else
        echo -e "${RED}  ✗ Private key not found: $OAUTH_PRIVATE_KEY${NC}"
        exit 1
    fi
fi

echo ""

#################################################################
# Step 4: Generate JWT Token
#################################################################

echo -e "${BLUE}[4/6] Generating JWT token...${NC}"

if [ ! -f "$SCRIPT_DIR/generate-jwt.sh" ]; then
    echo -e "${RED}  ✗ generate-jwt.sh not found${NC}"
    exit 1
fi

# Step 2: Generate JWT token (with key alias matching certificate)
JWT_TOKEN=$("$SCRIPT_DIR/generate-jwt.sh" "$OAUTH_USERNAME" "$OAUTH_CLIENT_ID" "$OAUTH_PRIVATE_KEY" "oic-jwt-$ENV" 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}  ✗ JWT generation failed${NC}"
    echo "$JWT_TOKEN"
    exit 1
fi

if [ -z "$JWT_TOKEN" ]; then
    echo -e "${RED}  ✗ JWT token is empty${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ JWT token generated${NC}"
echo -e "${YELLOW}  Token preview: ${JWT_TOKEN:0:50}...${NC}"
echo ""

#################################################################
# Step 5: Exchange JWT for Access Token
#################################################################

echo -e "${BLUE}[5/6] Getting OAuth access token...${NC}"

BASIC_AUTH=$(echo -n "${OAUTH_CLIENT_ID}:${OAUTH_CLIENT_SECRET}" | base64)

TOKEN_RESPONSE=$(curl -s -X POST "${IDCS_URL}/oauth2/v1/token" \
    -H "Authorization: Basic $BASIC_AUTH" \
    -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
    -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${JWT_TOKEN}&scope=urn:opc:resource:consumer::all")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
    echo -e "${RED}  ✗ Failed to get access token${NC}"
    echo -e "${YELLOW}  Response:${NC}"
    echo "$TOKEN_RESPONSE" | jq '.'
    
    ERROR_DESC=$(echo "$TOKEN_RESPONSE" | jq -r '.error_description // empty')
    if [ -n "$ERROR_DESC" ]; then
        echo -e "${RED}  Error: $ERROR_DESC${NC}"
    fi
    exit 1
fi

echo -e "${GREEN}  ✓ Access token obtained${NC}"
echo -e "${YELLOW}  Token preview: ${ACCESS_TOKEN:0:50}...${NC}"

TOKEN_TYPE=$(echo "$TOKEN_RESPONSE" | jq -r '.token_type')
EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')

echo -e "${GREEN}  ✓ Token type: $TOKEN_TYPE${NC}"
echo -e "${GREEN}  ✓ Expires in: $EXPIRES_IN seconds${NC}"
echo ""

#################################################################
# Step 6: Test OIC API Access
#################################################################

echo -e "${BLUE}[6/6] Testing OIC API access...${NC}"

API_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${OIC_URL}/ic/api/integration/v1/integrations?limit=1" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/json")

HTTP_CODE=$(echo "$API_RESPONSE" | tail -n 1)
BODY=$(echo "$API_RESPONSE" | head -n -1)

if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}  ✓ OIC API access successful (HTTP $HTTP_CODE)${NC}"
    
    COUNT=$(echo "$BODY" | jq '.count // 0')
    echo -e "${GREEN}  ✓ Found $COUNT integrations${NC}"
    
    if [ "$COUNT" -gt 0 ]; then
        FIRST_INT=$(echo "$BODY" | jq -r '.items[0].code // "N/A"')
        echo -e "${GREEN}  ✓ Sample integration: $FIRST_INT${NC}"
    fi
else
    echo -e "${RED}  ✗ OIC API access failed (HTTP $HTTP_CODE)${NC}"
    echo -e "${YELLOW}  Response:${NC}"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    exit 1
fi

echo ""

#################################################################
# Success Summary
#################################################################

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}✓ All Tests Passed!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo "Your JWT authentication is configured correctly for $ENV environment."
echo ""
echo -e "${BLUE}Configuration Summary:${NC}"
echo "  Environment: $ENV"
echo "  OIC URL: $OIC_URL"
echo "  IDCS URL: $IDCS_URL"
echo "  Client ID: ${OAUTH_CLIENT_ID:0:20}..."
echo "  Username: $OAUTH_USERNAME"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Run discovery: make list-integrations ENV=$ENV"
echo "  2. Export from DEV: make export-dev"
echo "  3. Import to TEST: make import-test"
echo ""
