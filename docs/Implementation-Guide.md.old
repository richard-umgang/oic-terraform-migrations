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

### JWT User Assertion Flow

1. **Generate JWT token** using your private key
2. **Exchange JWT for Access Token** from IDCS
3. **Use Access Token** to call OIC REST APIs
4. **Token expires** after 3600 seconds (refresh as needed)

### Step-by-Step Setup

#### 1. Generate Certificates

```bash
# Create certificate directory
mkdir -p ~/.oic-certs/dev
mkdir -p ~/.oic-certs/test
mkdir -p ~/.oic-certs/prod

# For each environment (replace 'dev' with 'test', 'prod'):
ENV=dev

# Generate private key (2048-bit RSA)
openssl genrsa -out ~/.oic-certs/$ENV/private-key.pem 2048

# Generate certificate signing request
openssl req -new \
  -key ~/.oic-certs/$ENV/private-key.pem \
  -out ~/.oic-certs/$ENV/cert.csr \
  -subj "/CN=OIC JWT Auth $ENV"

# Generate self-signed certificate (valid 365 days)
openssl x509 -req -days 365 \
  -in ~/.oic-certs/$ENV/cert.csr \
  -signkey ~/.oic-certs/$ENV/private-key.pem \
  -out ~/.oic-certs/$ENV/certificate.pem

# Create PKCS12 bundle (for IDCS upload)
openssl pkcs12 -export \
  -in ~/.oic-certs/$ENV/certificate.pem \
  -inkey ~/.oic-certs/$ENV/private-key.pem \
  -out ~/.oic-certs/$ENV/certificate.p12 \
  -name "OIC JWT $ENV" \
  -passout pass:changeit

# Set secure permissions
chmod 600 ~/.oic-certs/$ENV/*
```

#### 2. Create IDCS Confidential Application

For each environment (DEV, TEST, PROD):

1. **Navigate to IDCS:**
   - OCI Console → Identity & Security → Domains → [Your Domain]
   - Click **Integrated applications**

2. **Create Application:**
   - Click **Add application**
   - Choose **Confidential Application**
   - Click **Launch workflow**

3. **Application Details:**
   - Name: `oic-terraform-{env}` (e.g., `oic-terraform-dev`)
   - Description: "Terraform automation for OIC migrations"
   - Click **Next**

4. **Configure OAuth:**
   - Client configuration:
     - ✅ **Configure this application as a client now**
     - Allowed grant types: ✅ **JWT Assertion**
     - Client type: **Confidential**
   
   - Token issuance policy:
     - Click **Add scope**
     - Search for your OIC instance
     - Select: `{OIC_URL}:443urn:opc:resource:consumer::all`
     - Click **Add**
   
   - Click **Next**

5. **Skip remaining steps**, click **Finish**

6. **Upload Certificate:**
   - Open the created application
   - Go to **Configuration** tab
   - Scroll to **Client configuration**
   - Under **Token issuance policy**, click **Edit**
   - Click **Upload client certificate**
   - Upload the `.p12` file
   - Enter password: `changeit` (or your password)
   - Click **Save changes**

7. **Get Credentials:**
   - Copy **Client ID** from General Information
   - Copy **Client Secret** (click Show to reveal)

8. **Assign to OIC:**
   - Go to Identity & Security → Domains → Oracle Cloud Services
   - Find your OIC instance
   - Click on it → **Application roles**
   - Find **ServiceAdministrator** role
   - Click **Manage**
   - Click **Show applications**
   - Select your app → **Assign**

#### 3. Verify Setup

```bash
# Test JWT generation
./scripts/generate-jwt.sh \
  "your.email@example.com" \
  "your-client-id" \
  "~/.oic-certs/dev/private-key.pem"

# Test complete auth flow
./scripts/test-jwt-auth.sh dev
```

Expected output:
```
✓ All Tests Passed!
Your JWT authentication is configured correctly for dev environment.
```

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
