#!/bin/bash

#################################################################
# OIC3 Integration Testing Script
#
# Tests integrations and connections after deployment
#################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#################################################################
# Configuration
#################################################################

ENV="${1:-test}"
OUTPUT_FILE="test_report_${ENV}.html"
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}OIC3 Integration Testing${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo "Environment: $ENV"
echo "Timestamp: $TIMESTAMP"
echo ""

#################################################################
# Get Credentials and Token
#################################################################

if [ -z "$OAUTH_CLIENT_ID" ] || [ -z "$OAUTH_CLIENT_SECRET" ] || [ -z "$OAUTH_USERNAME" ] || [ -z "$OAUTH_PRIVATE_KEY" ]; then
    echo -e "${YELLOW}Getting credentials...${NC}"
    eval $("$SCRIPT_DIR/manage-credentials.sh" get-oauth "$ENV")
fi

# Get OIC and IDCS URLs
if [ -z "$OIC_URL" ]; then
    OIC_URL=$(grep -A 10 "^  ${ENV} = {" ../terraform/terraform.tfvars | grep "url" | head -1 | sed 's/.*= "\(.*\)"/\1/')
fi

if [ -z "$IDCS_URL" ]; then
    IDCS_URL=$(grep -A 10 "^  ${ENV} = {" ../terraform/terraform.tfvars | grep "idcs_url" | head -1 | sed 's/.*= "\(.*\)"/\1/')
fi

echo "Generating JWT token..."
JWT_TOKEN=$("$SCRIPT_DIR/generate-jwt.sh" "$OAUTH_USERNAME" "$OAUTH_CLIENT_ID" "$OAUTH_PRIVATE_KEY")

echo "Getting OAuth access token..."
BASIC_AUTH=$(echo -n "${OAUTH_CLIENT_ID}:${OAUTH_CLIENT_SECRET}" | base64)

TOKEN=$(curl -s -X POST "${IDCS_URL}/oauth2/v1/token" \
    -H "Authorization: Basic $BASIC_AUTH" \
    -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
    -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${JWT_TOKEN}&scope=urn:opc:resource:consumer::all" \
    | jq -r '.access_token')

if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
    echo -e "${RED}Error: Failed to obtain OAuth token${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Authentication successful${NC}"
echo ""

#################################################################
# Get Integrations from terraform.tfvars
#################################################################

echo "Reading integrations from terraform.tfvars..."

# Parse integration codes from terraform.tfvars
INTEGRATION_CODES=$(grep -A 200 "integrations_to_migrate = \[" ../terraform/terraform.tfvars | 
    grep "code.*=" | 
    sed 's/.*= "\(.*\)"/\1/')

if [ -z "$INTEGRATION_CODES" ]; then
    echo -e "${RED}Error: No integrations found in terraform.tfvars${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found integrations to test${NC}"
echo ""

#################################################################
# Test Results Storage
#################################################################

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

declare -a TEST_RESULTS

#################################################################
# Test Each Integration
#################################################################

echo -e "${BLUE}Running Integration Tests...${NC}"
echo ""

while IFS= read -r INT_CODE; do
    echo "Testing: $INT_CODE"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Get integration details
    RESPONSE=$(curl -s -X GET "${OIC_URL}/ic/api/integration/v1/integrations?q=code==${INT_CODE}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/json")
    
    STATUS=$(echo "$RESPONSE" | jq -r '.items[0].status // "NOT_FOUND"')
    VERSION=$(echo "$RESPONSE" | jq -r '.items[0].version // "N/A"')
    CONNECTIONS=$(echo "$RESPONSE" | jq -r '.items[0].dependencies.connections // [] | join(", ")')
    
    if [ "$STATUS" == "NOT_FOUND" ]; then
        echo -e "  ${RED}✗ Integration not found${NC}"
        TEST_RESULTS+=("$INT_CODE|NOT_FOUND|$VERSION|N/A|Integration not found")
        FAILED_TESTS=$((FAILED_TESTS + 1))
    elif [ "$STATUS" == "ACTIVATED" ]; then
        echo -e "  ${GREEN}✓ Status: ACTIVATED${NC}"
        TEST_RESULTS+=("$INT_CODE|PASS|$VERSION|$STATUS|Active and deployed")
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "  ${YELLOW}⚠ Status: $STATUS${NC}"
        TEST_RESULTS+=("$INT_CODE|WARNING|$VERSION|$STATUS|Not activated")
    fi
    
    # Test connections
    if [ -n "$CONNECTIONS" ] && [ "$CONNECTIONS" != "null" ]; then
        echo "  Testing connections: $CONNECTIONS"
        
        IFS=',' read -ra CONN_ARRAY <<< "$CONNECTIONS"
        for CONN_ID in "${CONN_ARRAY[@]}"; do
            CONN_ID=$(echo "$CONN_ID" | xargs)  # Trim whitespace
            
            TEST_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
                "${OIC_URL}/ic/api/integration/v1/connections/${CONN_ID}/test" \
                -H "Authorization: Bearer $TOKEN")
            
            HTTP_CODE=$(echo "$TEST_RESPONSE" | tail -n 1)
            
            if [ "$HTTP_CODE" == "200" ]; then
                echo -e "    ${GREEN}✓ $CONN_ID test passed${NC}"
            else
                echo -e "    ${RED}✗ $CONN_ID test failed (HTTP $HTTP_CODE)${NC}"
            fi
        done
    fi
    
    echo ""
done <<< "$INTEGRATION_CODES"

#################################################################
# Generate HTML Report
#################################################################

echo "Generating test report..."

cat > "$OUTPUT_FILE" <<HTMLEOF
<!DOCTYPE html>
<html>
<head>
    <title>OIC Integration Test Report - $ENV</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: #1976d2; color: white; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .summary { display: flex; gap: 20px; margin-bottom: 20px; }
        .summary-box { background: white; padding: 20px; border-radius: 5px; flex: 1; box-shadow: 0 2px 4px rgba(0,0,0,0.1); text-align: center; }
        .summary-number { font-size: 48px; font-weight: bold; }
        .pass { color: #4caf50; }
        .fail { color: #f44336; }
        .warn { color: #ff9800; }
        table { width: 100%; border-collapse: collapse; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); border-radius: 5px; overflow: hidden; margin-top: 20px; }
        th { background: #1976d2; color: white; padding: 12px; text-align: left; }
        td { padding: 12px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f5f5f5; }
        .status-pass { color: #4caf50; font-weight: bold; }
        .status-fail { color: #f44336; font-weight: bold; }
        .status-warning { color: #ff9800; font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <h1>OIC Integration Test Report</h1>
        <p>Environment: $ENV | Date: $(date) | OIC: $OIC_URL</p>
    </div>
    
    <div class="summary">
        <div class="summary-box">
            <div class="summary-number">$TOTAL_TESTS</div>
            <div>Total Tests</div>
        </div>
        <div class="summary-box">
            <div class="summary-number pass">$PASSED_TESTS</div>
            <div>Passed</div>
        </div>
        <div class="summary-box">
            <div class="summary-number fail">$FAILED_TESTS</div>
            <div>Failed</div>
        </div>
    </div>
    
    <table>
        <thead>
            <tr>
                <th>Integration</th>
                <th>Result</th>
                <th>Version</th>
                <th>Status</th>
                <th>Notes</th>
            </tr>
        </thead>
        <tbody>
HTMLEOF

# Add test results
for result in "${TEST_RESULTS[@]}"; do
    IFS='|' read -r CODE RESULT VERSION STATUS NOTES <<< "$result"
    
    STATUS_CLASS="status-pass"
    if [ "$RESULT" == "FAIL" ] || [ "$RESULT" == "NOT_FOUND" ]; then
        STATUS_CLASS="status-fail"
    elif [ "$RESULT" == "WARNING" ]; then
        STATUS_CLASS="status-warning"
    fi
    
    cat >> "$OUTPUT_FILE" <<HTMLEOF
            <tr>
                <td><strong>$CODE</strong></td>
                <td class="$STATUS_CLASS">$RESULT</td>
                <td>$VERSION</td>
                <td>$STATUS</td>
                <td>$NOTES</td>
            </tr>
HTMLEOF
done

cat >> "$OUTPUT_FILE" <<HTMLEOF
        </tbody>
    </table>
</body>
</html>
HTMLEOF

echo -e "${GREEN}✓ Test report generated: $OUTPUT_FILE${NC}"

#################################################################
# Summary
#################################################################

echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Some tests failed. Review the report for details.${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
fi

echo ""
echo "Report: $OUTPUT_FILE"
echo ""
