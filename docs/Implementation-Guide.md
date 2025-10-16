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
│                      Developer Workstation                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │  Terraform   │  │   Scripts    │  │   Makefile   │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
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
│  │+ Connctions│  │  │  │+ Connctions│  │  │  │+ Connctions│  │
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

### JWT User Assertion Flow

1. **Generate JWT token** using your private key
2. **Exchange JWT for Access Token** from IDCS
3. **Use Access Token** to call OIC REST APIs
4. **Token expires** after 3600 seconds (refresh as needed)

### Step-by-Step Setup

#### 1. Generate Certificates (Oracle's Official Method)

```bash
# Create certificate directories for each environment
mkdir -p ~/.oic-certs/dev
mkdir -p ~/.oic-certs/test
mkdir -p ~/.oic-certs/prod

# For each environment (replace 'dev' with 'test', 'prod'):
ENV=dev

# Step 1: Generate the self-signed key pair
keytool -genkey -keyalg RSA \
  -alias oic-jwt-$ENV \
  -keystore ~/.oic-certs/$ENV/keystore.jks \
  -storepass changeit \
  -validity 365 \
  -keysize 2048

# Follow the interactive prompts:
# What is your first and last name? [Your name or: OIC JWT Auth DEV]
# What is the name of your organizational unit? [Your team]
# What is the name of your organization? [Your company]
# What is the name of your City or Locality? [Your city]
# What is the name of your State or Province? [Your state]
# What is the two-letter country code? [US, GB, etc]
# Is CN=..., OU=..., correct? [yes]

# Step 2: Export the public key certificate
keytool -exportcert \
  -alias oic-jwt-$ENV \
  -file ~/.oic-certs/$ENV/certificate.cer \
  -keystore ~/.oic-certs/$ENV/keystore.jks \
  -storepass changeit

# Success message: Certificate stored in file <certificate.cer>

# Step 3: Convert the keystore to PKCS12 format
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

# Step 4: Export the private key from PKCS12 keystore
openssl pkcs12 \
  -in ~/.oic-certs/$ENV/certificate.p12 \
  -nodes \
  -nocerts \
  -out ~/.oic-certs/$ENV/private-key.pem \
  -passin pass:changeit

# Success message: MAC verified OK

# Step 5: Set secure permissions
chmod 600 ~/.oic-certs/$ENV/*
```

**Files Created:**
- `keystore.jks` - Java keystore (original, keep secure)
- `certificate.cer` - Public certificate for IDCS (upload this)
- `certificate.p12` - PKCS12 bundle (upload this if needed)
- `private-key.pem` - Private key for JWT signing (**keep secure!**)

**Important Notes:**
- Use the same password (`changeit` or your chosen password) throughout
- The `.cer` file is what you upload to IDCS
- The `private-key.pem` is used by the JWT generator script
- Keep keystores and private keys secure - never commit to Git

#### 2. Create IDCS Confidential Application

For each environment (DEV, TEST, PROD), follow Oracle's documented steps:

**Step 1: Navigate and Create**
1. OCI Console → Identity & Security → Domains → [Your Domain]
2. Click **Integrated applications**
3. Click **Add application**
4. Select **Confidential Application**
5. Click **Launch workflow**

**Step 2: Add Application Details**
- Name: `oic-terraform-dev` (or `test`, `prod`)
- Description: "Terraform automation for OIC JWT"
- Click **Submit**

**Step 3: Configure OAuth**

- Click **OAuth configuration** tab, then **Edit OAuth configuration** subtab
- In **Client configuration** panel:
  - ✅ **Configure this application as a client now**
- **Allowed grant types**: 
  - ✅ **JWT assertion**
  - ✅ **Refresh token**
- Leave **Redirect URL**, **Post-logout redirect URL**, and **Logout URL** blank
- **Client type**: 
  - ⚠️ Select **Trusted** (NOT "Confidential")
- **Certificate section**:
  - Click **Import certificate**
  - Upload `~/.oic-certs/dev/certificate.cer`
- **Token issuance policy**:
  - Select **Confidential** in **Authorized resources**
  - Toggle **Add Resources** ON
  - Click **Add scope**
  - Find your OIC instance and select BOTH scopes
  - Click **Add**
- Click **Submit**

**Step 4: Activate**
- Click **Activate**, then **Activate application**

**Step 5: Get Credentials**
- Copy **Client ID** from General Information
- Copy **Client Secret** (click Show)

**Step 6: Add Certificate as Trusted Partner**

⚠️ Oracle documentation requires this additional step:

1. In the domain menu bar, click **Security**
2. Scroll to **Trusted partner certificates** section
3. Click **Import certificate**
4. Upload the same `certificate.cer` file again
5. Click **Import**

6. **Get Credentials:**
   - Copy **Client ID** from General Information
   - Copy **Client Secret** (click Show to reveal)

7. **Assign to OIC:**
   - Go to Identity & Security → Domains → Oracle Cloud Services
   - Find your OIC instance
   - Click on it → **Application roles**
   - Find **ServiceAdministrator** role
   - Click **Manage**
   - Click **Show applications**
   - Select your app → **Assign**

#### 3. Verify Setup

Test the complete JWT authentication flow:

```bash
# Step 1: Set environment variables
export IDCS_URL=https://idcs-xxxxx.identity.oraclecloud.com
export CLIENT_ID=your-client-id
export CLIENT_SECRET=your-client-secret
export USERNAME=your.email@example.com
export PRIVATE_KEY_PATH=~/.oic-certs/private-key.pem

# Step 2: Generate JWT token
JWT_TOKEN=$(./scripts/generate-jwt.sh "$USERNAME" "$CLIENT_ID" "$PRIVATE_KEY_PATH")

echo "JWT Token generated: ${JWT_TOKEN:0:50}..."

# Step 3: Exchange JWT for Access Token (Oracle's documented method)
BASIC_AUTH=$(echo -n "${CLIENT_ID}:${CLIENT_SECRET}" | base64)

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

# Step 4: Test OIC API access
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
  # ... test, prod
}

# JWT Credentials
oauth_credentials = {
  dev = {
    client_id        = ""  # From OAUTH_CLIENT_ID_DEV env var
    client_secret    = ""  # From OAUTH_CLIENT_SECRET_DEV env var
    username         = ""  # From OAUTH_USERNAME_DEV env var
    private_key_path = ""  # From OAUTH_PRIVATE_KEY_DEV env var
  }
  # ... test, prod
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
   - Re-upload `.p12` if needed

2. **Check app assignment:**
   - Verify app assigned to OIC with ServiceAdministrator role
   - Check in IDCS → Oracle Cloud Services → [OIC] → Application roles

3. **Verify scopes:**
   - App should have scope: `{OIC_URL}:443urn:opc:resource:consumer::all`
   - Check in IDCS app → Configuration → Client configuration

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
- [Quick Start Guide](./Quick-Start-Guide.md)
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
