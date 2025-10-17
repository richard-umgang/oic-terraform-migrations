# OIC3 Terraform Migration - Implementation Guide

Complete guide for implementing automated OIC migrations with JWT authentication.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Authentication Setup](#authentication-setup)
4. [Configuration](#configuration)
5. [Daily Workflows](#daily-workflows)
6. [Production Best Practices](#production-best-practices)
7. [Troubleshooting](#troubleshooting)

---

## Overview

### What This Solution Does

- **Exports** integrations (with connections) from DEV as `.iar` files
- **Stores** artifacts in OCI Object Storage with versioning
- **Imports** to TEST/PROD with environment-specific configurations
- **Tests** connections and integrations automatically
- **Tracks** all changes via Terraform state

### Key Benefits

- ✅ **Consistent deployments** across environments
- ✅ **Version control** for integration artifacts
- ✅ **Rollback capability** with artifact versioning
- ✅ **Automated testing** after deployment
- ✅ **Audit trail** via Terraform state and Git
- ✅ **CI/CD ready** with GitLab pipeline

---

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Developer Workstation                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Terraform   │  │   Scripts    │  │   Makefile   │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                              │
            ┌─────────────────┼─────────────────┐
            │                 │                 │
            ▼                 ▼                 ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│   OIC DEV        │  │   OIC TEST       │  │   OIC PROD       │
│                  │  │                  │  │                  │
│  ┌────────────┐  │  │  ┌────────────┐  │  │  ┌────────────┐  │
│  │Integration │  │  │  │Integration │  │  │  │Integration │  │
│  │+ Connections│  │  │  │+ Connections│  │  │  │+ Connections│  │
│  └────────────┘  │  │  └────────────┘  │  │  └────────────┘  │
└──────────────────┘  └──────────────────┘  └──────────────────┘
         │                     ▲                     ▲
         │ Export              │ Import              │ Import
         │ (.iar)              │ (.iar)              │ (.iar)
         ▼                     │                     │
┌──────────────────────────────┴─────────────────────┘
│           OCI Object Storage                       │
│  ┌──────────────────────────────────────────┐     │
│  │  integrations/                           │     │
│  │    dev/                                  │     │
│  │      HELLO_WORLD-01.00.0000-timestamp.iar│     │
│  │      HELLO_WORLD-latest.iar              │     │
│  │      metadata.json                       │     │
│  └──────────────────────────────────────────┘     │
└────────────────────────────────────────────────────┘
```

### Authentication Flow (JWT User Assertion)

```
1. Generate JWT Token
   ┌─────────────────┐
   │  Private Key    │
   │  + Username     │──┐
   │  + Client ID    │  │ Sign JWT
   └─────────────────┘  │
                        ▼
                  ┌──────────┐
                  │   JWT    │
                  │  Token   │
                  └──────────┘
                        │
2. Exchange for Access Token
                        │
                        ▼
   ┌───────────────────────────────────┐
   │  IDCS/IAM OAuth2 Endpoint         │
   │  POST /oauth2/v1/token            │
   │  - grant_type: jwt-bearer         │
   │  - assertion: <JWT>               │
   │  - Authorization: Basic <creds>   │
   └───────────────────────────────────┘
                        │
                        ▼
                  ┌──────────┐
                  │  Access  │
                  │  Token   │
                  └──────────┘
                        │
3. Call OIC APIs
                        │
                        ▼
   ┌───────────────────────────────────┐
   │  OIC REST API                     │
   │  Authorization: Bearer <token>    │
   │  - Export integration             │
   │  - Import integration             │
   │  - Update connections             │
   └───────────────────────────────────┘
```

---

## Authentication Setup

**Reference:** This section follows Oracle's official documentation at:
https://docs.oracle.com/en/cloud/paas/application-integration/rest-adapter/authenticate-requests-invoking-oic-integration-flows.html#GUID-6D75DD1E-1811-4E73-BB0D-10DE56CB83EE

### JWT User Assertion Flow

1. **Generate JWT token** using your private key
2. **Exchange JWT for Access Token** from IDCS
3. **Use Access Token** to call OIC REST APIs
4. **Token expires** after 3600 seconds (refresh as needed)

### Step-by-Step Setup

#### Step 1: Generate Certificates (Oracle's Official Method)

```bash
# Create certificate directories for each environment
mkdir -p ~/.oic-certs/dev
mkdir -p ~/.oic-certs/test
mkdir -p ~/.oic-certs/prod

# For each environment (replace 'dev' with 'test', 'prod'):
ENV=dev

# Generate the self-signed key pair
keytool -genkey -keyalg RSA \
  -alias oic-jwt-$ENV \
  -keystore ~/.oic-certs/$ENV/keystore.jks \
  -storepass changeit \
  -validity 365 \
  -keysize 2048

# ⚠️ IMPORTANT: Remember this alias (oic-jwt-$ENV)
# It must match the "kid" field in your JWT token header

# Follow the interactive prompts:
# What is your first and last name? [Your name or: OIC JWT Auth DEV]
# What is the name of your organizational unit? [Your team]
# What is the name of your organization? [Your company]
# What is the name of your City or Locality? [Your city]
# What is the name of your State or Province? [Your state]
# What is the two-letter country code? [US, GB, etc]
# Is CN=..., OU=..., correct? [yes]

# Export the public key certificate
keytool -exportcert \
  -alias oic-jwt-$ENV \
  -file ~/.oic-certs/$ENV/certificate.cer \
  -keystore ~/.oic-certs/$ENV/keystore.jks \
  -storepass changeit

# Success message: Certificate stored in file <certificate.cer>

# Convert the keystore to PKCS12 format
keytool -importkeystore \
  -srckeystore ~/.oic-certs/$ENV/keystore.jks \
  -srcstorepass changeit \
  -srckeypass changeit \
  -srcalias oic-jwt-$ENV \
  -destalias oic-jwt-$ENV \
  -destkeystore ~/.oic-certs/$ENV/certificate.p12 \
  -deststoretype PKCS12 \
  -deststorepass changeit \
  -destkeypass changeit

# Success message: Importing keystore ... to certificate.p12...

# Export the private key from PKCS12 keystore
openssl pkcs12 \
  -in ~/.oic-certs/$ENV/certificate.p12 \
  -nodes \
  -nocerts \
  -out ~/.oic-certs/$ENV/private-key.pem \
  -passin pass:changeit

# Success message: MAC verified OK

# Set secure permissions
chmod 600 ~/.oic-certs/$ENV/*
```

**Files Created:**
- `keystore.jks` - Java keystore (original, keep secure)
- `certificate.cer` - Public certificate for IDCS (upload this)
- `certificate.p12` - PKCS12 bundle
- `private-key.pem` - Private key for JWT signing (**keep secure!**)

**Important Notes:**
- Use the same password (`changeit` or your chosen password) throughout
- The `.cer` file is what you upload to IDCS
- The `private-key.pem` is used by the JWT generator script
- Keep keystores and private keys secure - never commit to Git

#### Step 2: Create IDCS Confidential Application

For each environment (DEV, TEST, PROD), follow Oracle's documented steps:

**Navigate and Create:**
1. OCI Console → Identity & Security → Domains → [Your Domain]
2. Click **Integrated applications**
3. Click **Add application**
4. Select **Confidential Application**
5. Click **Launch workflow**

**Add Application Details:**
- Name: `oic-terraform-dev` (or `test`, `prod`)
- Description: "Terraform automation for OIC JWT"
- Click **Submit**

**Configure OAuth:**

1. Click **OAuth configuration** tab
2. Click **Edit OAuth configuration** subtab
3. In **Client configuration** panel:
   - ✅ Check **Configure this application as a client now**

4. **Allowed grant types:**
   - ✅ Check **JWT assertion**
   - ✅ Check **Refresh token**

5. Leave **Redirect URL**, **Post-logout redirect URL**, and **Logout URL** blank

6. **In Client type section:**
   - ⚠️ Select **Trusted** (NOT "Confidential")
   - This is critical for self-signed certificate user assertions

7. **Certificate section:**
   - Click **Import certificate**
   - Upload `~/.oic-certs/dev/certificate.cer`

8. **Token issuance policy:**
   - In **Authorized resources**, select **Confidential**
   - Toggle **Add Resources** to ON
   - Click **Add scope**
   - Find your OIC instance
   - Select BOTH scopes:
     - `:443urn:opc:resource:consumer::all`
     - `ic/api/`
   - Click **Add**

9. Click **Submit**

**Activate Application:**
- Click **Activate** button
- Click **Activate application** in the confirmation dialog

**Get Credentials:**
- Go to **General Information** section
- Copy **Client ID**
- Click **Show** next to Client Secret and copy it

#### Step 3: Add Certificate as Trusted Partner

⚠️ Oracle documentation requires this additional step:

1. In the domain menu bar, click **Security**
2. Scroll to **Trusted partner certificates** section
3. Click **Import certificate**
4. Upload the same `certificate.cer` file again
5. Click **Import**

This is separate from the OAuth configuration step and is required for JWT validation.

#### Step 4: Assign Application to OIC Instance

1. In the domain, click **Oracle Cloud Services** in the left menu
2. Find and click your OIC instance application
3. Click **Application roles** tab
4. Expand **ServiceInvoker** role
5. Click **Manage** (or Actions → Assigned applications)
6. Click **Assign applications** (or Show applications)
7. Find your confidential application (`oic-terraform-dev`)
8. Select it and click **Assign**

#### Step 5: Verify Setup

Test the complete JWT authentication flow:

```bash
# Set environment variables
export IDCS_URL="https://idcs-xxxxx.identity.oraclecloud.com"
export CLIENT_ID="your-client-id"
export CLIENT_SECRET="your-client-secret"
export USERNAME="your.email@example.com"  # IDCS user with ServiceInvoker role
export PRIVATE_KEY_PATH="~/.oic-certs/dev/private-key.pem"
export KEY_ALIAS="oic-jwt-dev"  # Must match your keytool alias

# Generate JWT token (with key alias and jti)
JWT_TOKEN=$(./scripts/generate-jwt.sh "$USERNAME" "$CLIENT_ID" "$PRIVATE_KEY_PATH" "$KEY_ALIAS")

echo "JWT Token generated: ${JWT_TOKEN:0:50}..."
```

**Important Parameters:**
- **USERNAME**: IDCS username that will invoke integrations. This user MUST have the **ServiceInvoker** role assigned in IDCS. Can be:
  - Your personal IDCS account (e.g., `john.doe@example.com`)
  - A service account created specifically for automation (recommended for production)
- **CLIENT_ID**: The OAuth client ID from your confidential application
- **CLIENT_SECRET**: The OAuth client secret
- **KEY_ALIAS**: Must match the alias used in `keytool -genkey` (e.g., `oic-jwt-dev`)

**Assigning ServiceInvoker Role:**
1. Go to Identity & Security → Domains → Oracle Cloud Services
2. Find your OIC instance
3. Click Application roles → ServiceInvoker
4. Click Manage users
5. Assign your USERNAME to this role

**Continue with token exchange:**

```bash
# Exchange JWT for Access Token (Oracle's documented method)
BASIC_AUTH=$(echo -n "${CLIENT_ID}:${CLIENT_SECRET}" | base64 | tr -d '\n ')

ACCESS_TOKEN=$(curl -s \
  -H "Authorization: Basic $BASIC_AUTH" \
  -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
  --request POST "${IDCS_URL}/oauth2/v1/token" \
  -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${JWT_TOKEN}&scope=urn:opc:resource:consumer::all" \
  | jq -r '.access_token')

if [ "$ACCESS_TOKEN" != "null" ] && [ -n "$ACCESS_TOKEN" ]; then
  echo "✓ Access token obtained successfully"
  echo "Token preview: ${ACCESS_TOKEN:0:50}..."
else
  echo "✗ Failed to get access token"
  # Show error details
  curl -i \
    -H "Authorization: Basic $BASIC_AUTH" \
    -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
    --request POST "${IDCS_URL}/oauth2/v1/token" \
    -d "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${JWT_TOKEN}&scope=urn:opc:resource:consumer::all"
fi

# Test OIC API access
OIC_URL="https://your-oic.integration.ocp.oraclecloud.com"

curl -s \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "${OIC_URL}/ic/api/integration/v1/integrations?limit=1" | jq '.'
```

**Expected Results:**
- JWT token: Long string starting with `eyJ...`
- Access token: Long string from IDCS
- OIC API response: JSON with integration data

**Use the automated test script:**
```bash
./scripts/test-jwt-auth.sh dev
```

This script performs all verification steps automatically.

---

## Configuration

### terraform.tfvars Structure

```hcl
# Target environment
environment = "dev"

# OIC Instances
oic_instances = {
  dev = {
    url           = "https://dev-oic.integration.region.ocp.oraclecloud.com"
    instance_name = "DEV_INSTANCE"
    idcs_url      = "https://idcs-xxx.identity.oraclecloud.com"
  }
  test = {
    url           = "https://test-oic.integration.region.ocp.oraclecloud.com"
    instance_name = "TEST_INSTANCE"
    idcs_url      = "https://idcs-xxx.identity.oraclecloud.com"
  }
  prod = {
    url           = "https://prod-oic.integration.region.ocp.oraclecloud.com"
    instance_name = "PROD_INSTANCE"
    idcs_url      = "https://idcs-xxx.identity.oraclecloud.com"
  }
}

# JWT Credentials (loaded from environment variables via Makefile)
oauth_credentials = {
  dev = {
    client_id        = ""  # From OAUTH_CLIENT_ID_DEV env var
    client_secret    = ""  # From OAUTH_CLIENT_SECRET_DEV env var
    username         = ""  # From OAUTH_USERNAME_DEV env var
    private_key_path = ""  # From OAUTH_PRIVATE_KEY_DEV env var
  }
  test = {
    client_id        = ""
    client_secret    = ""
    username         = ""
    private_key_path = ""
  }
  prod = {
    client_id        = ""
    client_secret    = ""
    username         = ""
    private_key_path = ""
  }
}

# Object Storage
bucket_config = {
  name           = "oic-migration-artifacts"
  namespace      = "your-tenancy-namespace"
  compartment_id = "ocid1.compartment.oc1..."
}

# Integrations to Migrate
integrations_to_migrate = [
  {
    id      = "INTEGRATION_CODE|VERSION"
    code    = "INTEGRATION_CODE"
    version = "VERSION"
    
    connections = {
      conn_name = {
        id = "CONNECTION_ID"
        
        test_properties = {
          "url" = {
            property_group = "CONNECTION_PROPS"
            property_name  = "connectionUrl"
            property_type  = "URL"
            property_value = "https://test.example.com"
          }
        }
        
        prod_properties = {
          "url" = {
            property_group = "CONNECTION_PROPS"
            property_name  = "connectionUrl"
            property_type  = "URL"
            property_value = "https://prod.example.com"
          }
        }
      }
    }
  }
]
```

### Connection Property Types

| Type | Description | Example |
|------|-------------|---------|
| `STRING` | Text values | `"myValue"` |
| `INTEGER` | Numbers | `"30"` |
| `URL` | Web URLs | `"https://api.example.com"` |
| `BOOLEAN` | true/false | `"true"` |
| `EMAIL` | Email addresses | `"admin@example.com"` |
| `PASSWORD` | Sensitive (masked) | `"password123"` |

### Common Property Groups

- `CONNECTION_PROPS` - General connection properties
- `ADAPTER_PROPS` - Adapter-specific settings
- `SECURITY_PROPS` - Authentication/security
- `AGENT_GROUP_PROPS` - Agent group configuration

---

## Daily Workflows

### Development Workflow

```bash
# 1. Develop integration in DEV OIC console
# 2. Test the integration
# 3. Export to version control

# Discovery
make list-integrations ENV=dev

# Export from DEV
make export-dev

# Verify export
oci os object list \
  --bucket-name oic-migration-artifacts \
  --prefix "integrations/dev/"
```

### Promotion to TEST

```bash
# Full workflow: Export + Import + Test
make promote-to-test

# Or step by step:
make export-dev
make import-test
make test ENV=test
```

### Promotion to PROD

```bash
# Requires manual approval
make import-prod

# This will:
# 1. Show plan
# 2. Ask for confirmation ("PROD")
# 3. Import to PROD
# 4. Run smoke tests
```

### Testing Workflow

```bash
# Test authentication
make test-auth ENV=test

# Test integrations
make test ENV=test

# Test connections only
make test-connections ENV=test

# Quick smoke test
make smoke-test ENV=prod
```

---

## Production Best Practices

### Pre-Deployment Checklist

- [ ] All tests pass in TEST environment
- [ ] Integration tested end-to-end in TEST
- [ ] Connection properties verified for PROD
- [ ] Credentials updated and secured
- [ ] Change request approved
- [ ] Rollback plan documented
- [ ] Stakeholders notified

### Deployment Process

1. **Schedule maintenance window**
2. **Backup current PROD state**
   ```bash
   make backup ENV=prod
   ```

3. **Run deployment**
   ```bash
   make import-prod
   ```

4. **Verify deployment**
   ```bash
   make smoke-test ENV=prod
   ```

5. **Manual activation** (if required)
   - Log into OIC console
   - Activate integration
   - Verify activation

6. **Post-deployment verification**
   - Test critical flows
   - Monitor for errors
   - Check logs

### Rollback Procedure

```bash
# List available backups
make list-backups

# Restore from backup
make restore ENV=prod DATE=20240315-120000

# Or manually revert
cd terraform
terraform apply -var="environment=prod" # with previous config
```

### Security Best Practices

1. **Credentials Management:**
   - Store in OCI Vault (recommended)
   - Or use environment variables (development only)
   - Never commit to Git

2. **Certificate Rotation:**
   - Rotate certificates annually
   - Update IDCS applications
   - Update Terraform configuration

3. **Access Control:**
   - Limit who can deploy to PROD
   - Use GitLab approval gates
   - Audit all deployments

4. **Network Security:**
   - Use private endpoints where possible
   - Restrict API access by IP
   - Enable OCI WAF for OIC instances

---

## Troubleshooting

### Authentication Issues

#### "invalid_client" Error

If you get `"error":"invalid_client","error_description":"Client authentication failed"`, follow these steps:

**Step 1: Verify Client Credentials**
```bash
# Test basic auth encoding
CLIENT_ID="your-client-id"
CLIENT_SECRET="your-client-secret"

# Trim any whitespace (common copy-paste issue)
CLIENT_ID=$(echo "$CLIENT_ID" | xargs)
CLIENT_SECRET=$(echo "$CLIENT_SECRET" | xargs)

# Check what you're sending
BASIC_AUTH=$(echo -n "${CLIENT_ID}:${CLIENT_SECRET}" | base64 | tr -d '\n ')
echo "Basic Auth Header: $BASIC_AUTH"

# Verify no spaces in the base64 string
if [[ "$BASIC_AUTH" =~ [[:space:]] ]]; then
    echo "ERROR: Basic Auth contains spaces!"
else
    echo "✓ Basic Auth looks good"
fi

# Decode to verify
echo "$BASIC_AUTH" | base64 -d
# Should show: client-id:client-secret
```

**Step 2: Verify Application Configuration in IDCS**

1. Go to your confidential application in IDCS
2. Check **General Information**:
   - Is the application **Active**? (green checkmark)
   - Copy the Client ID - does it match exactly?
   - Click **Show** on Client Secret - does it match exactly?
   - Watch for extra spaces or hidden characters

3. Check **OAuth Configuration**:
   - Client type = **Trusted** ✓
   - Allowed grant types include **JWT assertion** ✓
   - Certificate is uploaded under **Certificate** section ✓

**Step 3: Verify Certificate Upload**

In your confidential application:
1. Go to **OAuth configuration** → **Edit OAuth configuration**
2. Scroll to **Certificate** section
3. Is your certificate listed?
4. Does the certificate alias match your `kid` in the JWT?

**Step 4: Verify Trusted Partner Certificate**

1. Go to domain → **Security** → **Trusted partner certificates**
2. Is your certificate listed here?
3. If not, upload it again

**Step 5: Test JWT Generation**

```bash
# Generate JWT and decode it to verify
JWT_TOKEN=$(./scripts/generate-jwt.sh "$USERNAME" "$CLIENT_ID" "$PRIVATE_KEY_PATH" "$KEY_ALIAS")

# Decode JWT header (first part before first dot)
echo "$JWT_TOKEN" | cut -d. -f1 | base64 -d 2>/dev/null | jq '.'

# Should show:
# {
#   "alg": "RS256",
#   "typ": "JWT",
#   "kid": "oic-jwt-dev"  // Must match your certificate alias
# }

# Decode JWT payload (second part)
echo "$JWT_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq '.'

# Should show:
# {
#   "sub": "your-username",
#   "jti": "uuid",
#   "iat": 1234567890,
#   "exp": 1234568190,
#   "iss": "your-client-id",  // Must match CLIENT_ID
#   "aud": "https://identity.oraclecloud.com/"
# }
```

**Common Issues Checklist**

- [ ] Client ID has no spaces or hidden characters
- [ ] Client secret has no spaces or hidden characters
- [ ] Application is **Active** (not deactivated)
- [ ] Application client type is **Trusted** (not Confidential)
- [ ] Certificate uploaded to OAuth configuration
- [ ] Certificate added to Trusted Partner Certificates
- [ ] Certificate `kid` matches JWT header `kid`
- [ ] JWT `iss` field matches Client ID exactly
- [ ] IDCS URL is correct (check domain URL in IDCS console)
- [ ] No firewall blocking IDCS URL

#### JWT Token Generation Fails

**Symptom:** `generate-jwt.sh` returns empty or errors

**Solutions:**
```bash
# Check Python/Node.js
python3 --version  # or
node --version

# Verify private key
openssl rsa -in ~/.oic-certs/dev/private-key.pem -check

# Check key permissions
ls -la ~/.oic-certs/dev/private-key.pem
# Should be: -rw------- (600)
```

#### OAuth Token Exchange Fails

**Symptom:** "Failed to get access token" error

**Solutions:**
1. **Verify certificate uploaded:**
   - Check IDCS app configuration
   - Re-upload `.cer` if needed

2. **Check app assignment:**
   - Verify app assigned to OIC with ServiceInvoker role
   - Check in IDCS → Oracle Cloud Services → [OIC] → Application roles

3. **Verify scopes:**
   - App should have both scopes selected
   - Check in IDCS app → OAuth configuration

4. **Test manually:**
   ```bash
   ./scripts/test-jwt-auth.sh dev
   ```

### Export/Import Issues

#### Export Fails

**Symptom:** "Integration not found" or export fails

**Solutions:**
```bash
# List integrations
./scripts/list-integrations.sh dev

# Verify integration ID format
# Should be: CODE|VERSION (e.g., "HELLO_WORLD|01.00.0000")

# Check OIC API access
TOKEN=$(./scripts/manage-credentials.sh get-oauth-token dev)
curl -H "Authorization: Bearer $TOKEN" \
  "${OIC_URL}/ic/api/integration/v1/integrations"
```

#### Import Fails

**Symptom:** Import to TEST/PROD fails

**Solutions:**
1. **Check .iar file exists:**
   ```bash
   oci os object list \
     --bucket-name oic-migration-artifacts \
     --prefix "integrations/dev/"
   ```

2. **Verify connection properties:**
   - Check `terraform.tfvars` for correct property names
   - Verify property groups and types

3. **Check Terraform logs:**
   ```bash
   export TF_LOG=DEBUG
   make plan ENV=test
   ```

### Connection Issues

#### Connection Test Fails

**Symptom:** Connection tests fail after import

**Solutions:**
1. **Verify properties updated:**
   - Check OIC console → Connections → [Connection]
   - Verify URL, credentials updated correctly

2. **Check network connectivity:**
   - Ensure OIC can reach target system
   - Verify firewall rules
   - Check security lists/NSGs

3. **Test connection manually:**
   - In OIC console, click Test on connection
   - Review error messages

4. **Check credentials:**
   - Verify credentials for target environment
   - Update if needed in Terraform config

---

## Advanced Topics

### Using OCI Vault for Credentials

```bash
# Store JWT credentials in Vault
export OCI_VAULT_ID="ocid1.vault.oc1..."
export OCI_KEY_ID="ocid1.key.oc1..."
export OCI_COMPARTMENT_ID="ocid1.compartment.oc1..."

./scripts/manage-credentials.sh store-oauth dev \
  "client-id" \
  "client-secret" \
  "username@example.com" \
  "~/.oic-certs/dev/private-key.pem"

# Retrieve from Vault
./scripts/manage-credentials.sh get-oauth dev
```

### CI/CD Integration

See `.gitlab-ci.yml` for complete pipeline configuration.

**Key features:**
- Automated export from DEV on merge to main
- Automatic import to TEST
- Manual approval for PROD
- Automated testing
- Slack notifications (optional)

### Custom Scripts

Create custom scripts in `scripts/` directory:

```bash
# Example: Custom validation script
scripts/validate-connections.sh

# Example: Custom deployment script
scripts/deploy-to-region.sh
```

---

## Support & Resources

### Documentation
- [Implementation Guide](./Implementation-Guide.md) (this document)
- [Deployment Checklist](./Deployment-Checklist.md)
- [OIC REST API Reference](https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/)

### Troubleshooting
- Enable debug logging: `export TF_LOG=DEBUG`
- Check Terraform logs: `cat terraform-debug.log`
- Test auth: `./scripts/test-jwt-auth.sh <env>`

### Getting Help
1. Check troubleshooting section above
2. Review logs and error messages
3. Test components individually
4. Consult OIC documentation

---

**Version:** 1.0 (JWT-Only)  
**Last Updated:** 2024
