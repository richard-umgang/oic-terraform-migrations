#!/bin/bash

#################################################################
# OIC3 Integration Discovery Script
#
# Lists all integrations and their connections
# Generates reports in HTML and CSV format
#################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

#################################################################
# Configuration
#################################################################

ENV="${1:-dev}"
OUTPUT_DIR="./integration-discovery-${ENV}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Get credentials
if [ -z "$OAUTH_CLIENT_ID" ] || [ -z "$OAUTH_CLIENT_SECRET" ] || [ -z "$OAUTH_USERNAME" ] || [ -z "$OAUTH_PRIVATE_KEY" ]; then
    echo -e "${YELLOW}Using credentials from credential manager...${NC}"
    eval $("$SCRIPT_DIR/manage-credentials.sh" get-oauth "$ENV")
    
    # Get private key for JWT
    temp_key=$(mktemp)
    "$SCRIPT_DIR/manage-credentials.sh" get-oauth "$ENV" | grep "private-key" > "$temp_key"
    export OAUTH_PRIVATE_KEY="$temp_key"
fi

# Get OIC and IDCS URLs from terraform.tfvars
if [ -z "$OIC_URL" ]; then
    OIC_URL=$(grep -A 10 "^  ${ENV} = {" ../terraform/terraform.tfvars | grep "url" | head -1 | sed 's/.*= "\(.*\)"/\1/')
fi

if [ -z "$IDCS_URL" ]; then
    IDCS_URL=$(grep -A 10 "^  ${ENV} = {" ../terraform/terraform.tfvars | grep "idcs_url" | head -1 | sed 's/.*= "\(.*\)"/\1/')
fi

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}OIC3 Integration Discovery${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo "Environment: $ENV"
echo "OIC URL: $OIC_URL"
echo ""

#################################################################
# Get OAuth Token
#################################################################

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
    echo "Error: Failed to obtain OAuth token"
    exit 1
fi

echo -e "${GREEN}✓ Authentication successful${NC}"
echo ""

#################################################################
# Fetch Integrations
#################################################################

echo "Fetching integrations..."

mkdir -p "$OUTPUT_DIR"

curl -s -X GET "${OIC_URL}/ic/api/integration/v1/integrations?limit=1000" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/json" \
    > "$OUTPUT_DIR/integrations-raw.json"

# Parse integrations
INTEGRATIONS=$(cat "$OUTPUT_DIR/integrations-raw.json" | jq -r '.items[]')
COUNT=$(cat "$OUTPUT_DIR/integrations-raw.json" | jq '.items | length')

echo -e "${GREEN}✓ Found $COUNT integrations${NC}"
echo ""

#################################################################
# Fetch Connections
#################################################################

echo "Fetching connections..."

curl -s -X GET "${OIC_URL}/ic/api/integration/v1/connections?limit=1000" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/json" \
    > "$OUTPUT_DIR/connections-raw.json"

CONN_COUNT=$(cat "$OUTPUT_DIR/connections-raw.json" | jq '.items | length')

echo -e "${GREEN}✓ Found $CONN_COUNT connections${NC}"
echo ""

#################################################################
# Generate CSV Report
#################################################################

echo "Generating CSV report..."

cat > "$OUTPUT_DIR/integrations-${TIMESTAMP}.csv" <<EOF
Integration Code,Version,ID,Status,Created,Updated,Connections
EOF

cat "$OUTPUT_DIR/integrations-raw.json" | jq -r '.items[] | 
    [.code, .version, .id, .status, .createdTime, .lastUpdatedTime, (.dependencies.connections // [] | join(";"))] | 
    @csv' >> "$OUTPUT_DIR/integrations-${TIMESTAMP}.csv"

echo -e "${GREEN}✓ CSV report: $OUTPUT_DIR/integrations-${TIMESTAMP}.csv${NC}"

#################################################################
# Generate HTML Report
#################################################################

echo "Generating HTML report..."

cat > "$OUTPUT_DIR/integrations-${TIMESTAMP}.html" <<'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <title>OIC Integration Discovery Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: #1976d2; color: white; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .stats { display: flex; gap: 20px; margin-bottom: 20px; }
        .stat-box { background: white; padding: 20px; border-radius: 5px; flex: 1; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .stat-number { font-size: 36px; font-weight: bold; color: #1976d2; }
        .stat-label { color: #666; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; background: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); border-radius: 5px; overflow: hidden; }
        th { background: #1976d2; color: white; padding: 12px; text-align: left; }
        td { padding: 12px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f5f5f5; }
        .status-active { color: #4caf50; font-weight: bold; }
        .status-configured { color: #ff9800; font-weight: bold; }
        .badge { display: inline-block; padding: 4px 8px; border-radius: 3px; font-size: 12px; margin: 2px; }
        .connection-badge { background: #e3f2fd; color: #1976d2; }
        .search-box { margin-bottom: 20px; }
        .search-box input { padding: 10px; width: 100%; border: 1px solid #ddd; border-radius: 5px; font-size: 16px; }
    </style>
    <script>
        function filterTable() {
            const input = document.getElementById('searchInput');
            const filter = input.value.toUpperCase();
            const table = document.getElementById('integrationsTable');
            const tr = table.getElementsByTagName('tr');
            
            for (let i = 1; i < tr.length; i++) {
                const td = tr[i].getElementsByTagName('td');
                let found = false;
                for (let j = 0; j < td.length; j++) {
                    if (td[j].textContent.toUpperCase().indexOf(filter) > -1) {
                        found = true;
                        break;
                    }
                }
                tr[i].style.display = found ? '' : 'none';
            }
        }
    </script>
</head>
<body>
    <div class="header">
        <h1>OIC Integration Discovery Report</h1>
        <p>Environment: ENV_PLACEHOLDER | Generated: TIMESTAMP_PLACEHOLDER</p>
    </div>
    
    <div class="stats">
        <div class="stat-box">
            <div class="stat-number">COUNT_INTEGRATIONS</div>
            <div class="stat-label">Integrations</div>
        </div>
        <div class="stat-box">
            <div class="stat-number">COUNT_CONNECTIONS</div>
            <div class="stat-label">Connections</div>
        </div>
        <div class="stat-box">
            <div class="stat-number">COUNT_ACTIVE</div>
            <div class="stat-label">Active Integrations</div>
        </div>
    </div>
    
    <div class="search-box">
        <input type="text" id="searchInput" onkeyup="filterTable()" placeholder="Search integrations...">
    </div>
    
    <table id="integrationsTable">
        <thead>
            <tr>
                <th>Integration Code</th>
                <th>Version</th>
                <th>Status</th>
                <th>Connections</th>
                <th>Created</th>
                <th>Terraform Config</th>
            </tr>
        </thead>
        <tbody>
HTMLEOF

# Add integration rows
cat "$OUTPUT_DIR/integrations-raw.json" | jq -r '.items[] | 
    "<tr>" +
    "<td><strong>" + .code + "</strong></td>" +
    "<td>" + .version + "</td>" +
    "<td class=\"status-" + (.status | ascii_downcase) + "\">" + .status + "</td>" +
    "<td>" + ((.dependencies.connections // []) | map("<span class=\"connection-badge badge\">" + . + "</span>") | join(" ")) + "</td>" +
    "<td>" + .createdTime + "</td>" +
    "<td><code>" + .code + "|" + .version + "</code></td>" +
    "</tr>"' >> "$OUTPUT_DIR/integrations-${TIMESTAMP}.html"

# Complete HTML
cat >> "$OUTPUT_DIR/integrations-${TIMESTAMP}.html" <<'HTMLEOF'
        </tbody>
    </table>
</body>
</html>
HTMLEOF

# Replace placeholders
sed -i "s/ENV_PLACEHOLDER/$ENV/g" "$OUTPUT_DIR/integrations-${TIMESTAMP}.html"
sed -i "s/TIMESTAMP_PLACEHOLDER/$(date)/g" "$OUTPUT_DIR/integrations-${TIMESTAMP}.html"
sed -i "s/COUNT_INTEGRATIONS/$COUNT/g" "$OUTPUT_DIR/integrations-${TIMESTAMP}.html"
sed -i "s/COUNT_CONNECTIONS/$CONN_COUNT/g" "$OUTPUT_DIR/integrations-${TIMESTAMP}.html"

ACTIVE_COUNT=$(cat "$OUTPUT_DIR/integrations-raw.json" | jq '[.items[] | select(.status == "ACTIVATED")] | length')
sed -i "s/COUNT_ACTIVE/$ACTIVE_COUNT/g" "$OUTPUT_DIR/integrations-${TIMESTAMP}.html"

echo -e "${GREEN}✓ HTML report: $OUTPUT_DIR/integrations-${TIMESTAMP}.html${NC}"

#################################################################
# Generate Terraform Template
#################################################################

echo "Generating Terraform configuration template..."

cat > "$OUTPUT_DIR/terraform-template.tf" <<'EOF'
# Generated Terraform configuration template
# Copy integrations to your terraform.tfvars

integrations_to_migrate = [
EOF

cat "$OUTPUT_DIR/integrations-raw.json" | jq -r '.items[] | 
"  {
    id      = \"" + .id + "\"
    code    = \"" + .code + "\"
    version = \"" + .version + "\"
    
    connections = {
" + ((.dependencies.connections // []) | map(
"      " + . + " = {
        id = \"" + . + "\"
        
        test_properties = {
          # Add properties here
        }
        
        prod_properties = {
          # Add properties here
        }
      }"
) | join("\n")) + "
    }
  },"
' >> "$OUTPUT_DIR/terraform-template.tf"

cat >> "$OUTPUT_DIR/terraform-template.tf" <<'EOF'
]
EOF

echo -e "${GREEN}✓ Terraform template: $OUTPUT_DIR/terraform-template.tf${NC}"

#################################################################
# Summary
#################################################################

echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Discovery Complete!${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""
echo "Reports generated in: $OUTPUT_DIR/"
echo ""
echo "  1. integrations-${TIMESTAMP}.html  (Open in browser)"
echo "  2. integrations-${TIMESTAMP}.csv   (Excel/analysis)"
echo "  3. terraform-template.tf           (Terraform config)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Open the HTML report to review integrations"
echo "  2. Choose integrations to migrate"
echo "  3. Copy relevant sections from terraform-template.tf to your terraform.tfvars"
echo "  4. Add environment-specific connection properties"
echo ""
