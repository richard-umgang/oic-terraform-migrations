# OIC3 Terraform Migration - Quick Start Guide

## 🚀 Get Started in 30 Minutes

This guide will get you up and running with automated OIC migrations using JWT authentication.

---

## Step 1: Prerequisites (5 minutes)

### Install Required Tools

```bash
# Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# OCI CLI
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

# Verify installations
terraform version
oci --version
jq --version  # Should be pre-installed
```

### Clone Repository

```bash
git clone <your-repo-url>
cd oic-terraform-migrations
```

---

## Step 2: Configure OCI (3 minutes)

### Set Up OCI CLI

```bash
oci setup config
# Follow prompts to create ~/.oci/config
```

### Create Object Storage Buckets

```bash
# Set your compartment ID
export COMPARTMENT_ID="ocid1.compartment.oc1..."

# Create bucket for artifacts
oci os bucket create \
  --name oic-migration-artifacts \
  --compartment-id $COMPARTMENT_ID

# Create bucket for Terraform state (optional)
oci os bucket create \
  --name oic-terraform-state \
  --compartment-id $COMPARTMENT_ID
```

---

## Step 3: Configure OAuth2 with JWT (10 minutes)

OIC3 uses JWT User Assertion for secure authentication with certificates.

**📘 Note:** These steps follow Oracle's official documentation:  
[Authenticate Requests for Invoking Oracle Integration Flows - JWT User Assertion](https://docs.oracle.com/en/cloud/paas/application-integration/rest-adapter/authenticate-requests-invoking-oic-integration-flows.html#GUID-6D75DD1E-1811-4E73-BB0D-10DE56CB83EE__BBBB)

### Generate Certificates (Using Oracle's Method)

Follow Oracle's official method using Java's `keytool`:

```bash
# Create certificate directory
mkdir -p ~/.oic-certs

# 1. Generate the self-signed key pair
keytool -genkey -keyalg RSA \
  -alias oic-jwt \
  -keystore ~/.oic-certs/keystore.jks \
  -storepass changeit \
  -validity 365 \
  -keysize 2048

# Follow prompts:
# - What is your first and last name? [Enter your name or: OIC JWT Auth]
# - What is the name of your organizational unit? [Your team]
# - What is the name of your organization? [Your company]
# - What is the name of your City or Locality? [Your city]
# - What is the name of your State or Province? [Your state]
# - What is the two-letter country code? [US/GB/etc]
# - Is CN=..., correct? [yes]

# 2. Export the public key certificate
keytool -exportcert \
  -alias oic-jwt \
  -file ~/.oic-certs/certificate.cer \
  -keystore ~/.oic-certs/keystore.jks \
  -storepass changeit

# Should show: Certificate stored in file <certificate.cer>

# 3. Convert the keystore to P12 format
keytool -importkeystore \
  -srckeystore ~/.oic-certs/keystore.jks \
  -srcstorepass changeit \
  -srckeypass changeit \
  -srcalias oic-jwt \
  -destalias oic-jwt \
  -destkeystore ~/.oic-certs/certificate.p12 \
  -deststoretype PKCS12 \
  -deststorepass changeit \
  -destkeypass changeit

# Should show: Importing keystore ... to certificate.p12...

# 4. Export the private key from P12 keystore
openssl pkcs12 \
  -in ~/.oic-certs/certificate.p12 \
  -nodes \
  -nocerts \
  -out ~/.oic-certs/private-key.pem \
  -passin pass:changeit

# Should show: MAC verified OK

# 5. Set permissions
chmod 600 ~/.oic-certs/*
```

**Important Files Created:**
- `keystore.jks` - Java keystore (keep secure)
- `certificate.cer` - Public certificate (upload to IDCS)
- `certificate.p12` - PKCS12 bundle (upload to IDCS)
- `private-key.pem` - Private key for JWT signing (keep secure!)

### Create Confidential Application in IDCS

1. Go to OCI Console → **Identity & Security** → **Domains** → [Your Domain]
2. Click **Integrated applications**
3. Click **Add application**
4. Choose **Confidential Application**
5. Click **Launch workflow**

### Configure the Application

**Step 1: Add application details**
- Name: `oic-terraform-dev` (or `test`, `prod`)
- Description: "Terraform automation for OIC JWT"
- Click **Submit**

**Step 2: Configure OAuth**

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
  - Upload `~/.oic-certs/certificate.cer`
- **Token issuance policy**:
  - Select **Confidential** in **Authorized resources**
  - Toggle **Add Resources** ON
  - Click **Add scope**
  - Find your OIC instance and select BOTH scopes
  - Click **Add**
- Click **Submit**

**Step 3: Activate**
- Click **Activate**, then **Activate application**

**Step 4: Get Credentials**
- Copy **Client ID** from General Information
- Copy **Client Secret** (click Show)

### Upload Certificate

After creating the application:

1. Open the application you just created
2. Go to **Configuration** tab
3. Scroll to **Client configuration**
4. Under **Token issuance policy**, click **Edit**
5. Scroll to **Client credentials**
6. Click **Upload client certificate**
7. Upload the `.p12` file you created
8. Enter the password you set when creating the PKCS12 file
9. Click **Upload**
10. Click **Save changes**

### Assign to OIC Instance

1. In OCI Console, go to **Identity & Security** → **Domains** → [Your Domain]
2. Click **Oracle Cloud Services**
3. Find your OIC instance in the list
4. Click on the instance name
5. Click **Application roles** tab
6. Find **ServiceAdministrator** role
7. Click the role name
8. Click **Manage** (or **Assigned users/groups**)
9. Click **Show applications**
10. Find your confidential application (`oic-terraform-dev`)
11. Select it and click **Assign**

### Get Client ID and Secret

1. Go back to your confidential application
2. Under **General Information**, copy the **Client ID**
3. Under **Client configuration**, click **Show** next to **Client secret**
4. Copy the **Client secret**

### Test Your Setup

```bash
# Set variables
export IDCS_URL="https://idcs-xxxxx.identity.oraclecloud.com"
export CLIENT_ID="your-client-id"
export CLIENT_SECRET="your-client-secret"
export USERNAME="your.email@example.com"
export PRIVATE_KEY_PATH="~/.oic-certs/private-key.pem"

# Test JWT token generation
./scripts/generate-jwt.sh "$USERNAME" "$CLIENT_ID" "$PRIVATE_KEY_PATH"

# If successful, you'll see a long JWT token string starting with eyJ...
```

### Repeat for TEST and PROD

Create separate applications and certificates for each environment:

**For DEV:**
- Application: `oic-terraform-dev`
- Certificates in: `~/.oic-certs/dev/`

**For TEST:**
- Application: `oic-terraform-test`  
- Certificates in: `~/.oic-certs/test/`

**For PROD:**
- Application: `oic-terraform-prod`
- Certificates in: `~/.oic-certs/prod/`

For each environment, repeat all steps above with environment-specific directories.

### Store Credentials in Environment

```bash
# DEV
export OAUTH_CLIENT_ID_DEV="your-dev-client-id"
export OAUTH_CLIENT_SECRET_DEV="your-dev-client-secret"
export OAUTH_USERNAME_DEV="your-idcs-username"
export OAUTH_PRIVATE_KEY_DEV="~/.oic-certs/dev/private-key.pem"

# TEST
export OAUTH_CLIENT_ID_TEST="your-test-client-id"
export OAUTH_CLIENT_SECRET_TEST="your-test-client-secret"
export OAUTH_USERNAME_TEST="your-idcs-username"
export OAUTH_PRIVATE_KEY_TEST="~/.oic-certs/test/private-key.pem"

# PROD
export OAUTH_CLIENT_ID_PROD="your-prod-client-id"
export OAUTH_CLIENT_SECRET_PROD="your-prod-client-secret"
export OAUTH_USERNAME_PROD="your-idcs-username"
export OAUTH_PRIVATE_KEY_PROD="~/.oic-certs/prod/private-key.pem"
```

---

## Step 4: Configure Terraform (2 minutes)

### Create terraform.tfvars

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

### Edit terraform.tfvars

```hcl
environment = "dev"

oic_instances = {
  dev = {
    url           = "https://your-dev.integration.us-phoenix-1.ocp.oraclecloud.com"
    instance_name = "YOURDEVINSTANCE"
    idcs_url      = "https://idcs-xxxxx.identity.oraclecloud.com"
  }
  test = {
    url           = "https://your-test.integration.us-phoenix-1.ocp.oraclecloud.com"
    instance_name = "YOURTESTINSTANCE"
    idcs_url      = "https://idcs-xxxxx.identity.oraclecloud.com"
  }
  prod = {
    url           = "https://your-prod.integration.us-ashburn-1.ocp.oraclecloud.com"
    instance_name = "YOURPRODINSTANCE"
    idcs_url      = "https://idcs-xxxxx.identity.oraclecloud.com"
  }
}

# Credentials (loaded from environment in Makefile)
oauth_credentials = {
  dev  = { client_id = "", client_secret = "", username = "", private_key_path = "" }
  test = { client_id = "", client_secret = "", username = "", private_key_path = "" }
  prod = { client_id = "", client_secret = "", username = "", private_key_path = "" }
}

bucket_config = {
  name           = "oic-migration-artifacts"
  namespace      = "your-tenancy"
  compartment_id = "ocid1.compartment.oc1..."
}

# Start with one integration
integrations_to_migrate = [
  {
    id      = "HELLO_WORLD|01.00.0000"  # Change to your integration
    code    = "HELLO_WORLD"
    version = "01.00.0000"
    
    connections = {
      rest_conn = {
        id = "REST_CONNECTION"
        
        test_properties = {
          "url" = {
            property_group = "CONNECTION_PROPS"
            property_name  = "connectionUrl"
            property_type  = "URL"
            property_value = "https://test-api.example.com"
          }
        }
        
        prod_properties = {
          "url" = {
            property_group = "CONNECTION_PROPS"
            property_name  = "connectionUrl"
            property_type  = "URL"
            property_value = "https://api.example.com"
          }
        }
      }
    }
  }
]
```

---

## Step 5: Your First Export (Quick Test)

### Initialize Terraform

```bash
make init
```

### Test JWT Authentication

```bash
./scripts/test-jwt-auth.sh dev
```

You should see:
```
✓ All Tests Passed!
Your JWT authentication is configured correctly for dev environment.
```

### Discover Available Integrations

```bash
./scripts/list-integrations.sh dev
```

This creates an HTML report showing all integrations and connections. Use this to find integration IDs for your terraform.tfvars.

### Export from DEV

```bash
# Plan the export
make plan ENV=dev

# Review the plan, then apply
make apply ENV=dev

# Check what was exported
make outputs ENV=dev
```

### Verify Export

```bash
# List exported files in Object Storage
oci os object list \
  --bucket-name oic-migration-artifacts \
  --prefix "integrations/dev/"
```

You should see:
- `HELLO_WORLD-01.00.0000-YYYY-MM-DD-HHMMSS.iar`
- `HELLO_WORLD-latest.iar`
- `HELLO_WORLD-01.00.0000-YYYY-MM-DD-HHMMSS.iar.metadata.json`

---

## Step 6: Import to TEST

### Update Credentials for TEST

```bash
export OAUTH_CLIENT_ID=$OAUTH_CLIENT_ID_TEST
export OAUTH_CLIENT_SECRET=$OAUTH_CLIENT_SECRET_TEST
export OAUTH_USERNAME=$OAUTH_USERNAME_TEST
export OAUTH_PRIVATE_KEY=$OAUTH_PRIVATE_KEY_TEST
```

### Import

```bash
# Plan import to TEST
make plan ENV=test

# Review the plan carefully
# It will show:
# - .iar file to be imported
# - Connection properties to be updated

# Apply
make apply ENV=test
```

### Test

```bash
# Run automated tests
make test ENV=test

# View test report
open test_report_test.html
```

---

## 🎉 Success!

You've successfully:
- ✅ Set up JWT OAuth2 authentication with certificates
- ✅ Configured Terraform for OIC migrations
- ✅ Exported an integration from DEV as .iar file
- ✅ Imported to TEST with environment-specific configs
- ✅ Tested the deployment

---

## Next Steps

### 1. Add More Integrations

Edit `terraform.tfvars` and add more integrations to the `integrations_to_migrate` list.

### 2. Set Up CI/CD

```bash
# Copy GitLab CI pipeline
cp .gitlab-ci.yml.example .gitlab-ci.yml

# Configure CI/CD variables in GitLab
# See: Settings → CI/CD → Variables
```

### 3. Production Deployment

```bash
# When ready for PROD
make import-prod

# This will:
# - Show plan
# - Ask for confirmation (safety check!)
# - Deploy to PROD
# - Run tests
```

---

## Common Commands Reference

```bash
# Discovery
make list-integrations ENV=dev          # List all integrations
make status ENV=test                     # Show current status
make test-auth ENV=dev                   # Test JWT authentication

# Deployment
make export-dev                          # Export from DEV
make import-test                         # Import to TEST
make import-prod                         # Import to PROD (with confirmation)

# Full workflow
make promote-to-test                     # DEV → TEST
make promote-to-prod                     # TEST → PROD

# Testing
make test ENV=test                       # Run all tests
make test-connections ENV=test           # Test only connections
make smoke-test ENV=prod                 # Quick smoke test

# Backup & Recovery
make backup ENV=prod                     # Backup PROD integrations
make list-backups                        # Show available backups

# Utilities
make validate                            # Validate Terraform
make format                              # Format Terraform files
make clean                               # Clean temporary files
make help                                # Show all commands
```

---

## Troubleshooting

### Can't generate JWT token?

```bash
# Test JWT generation manually
./scripts/generate-jwt.sh "user@example.com" "client-id" "~/.oic-certs/private-key.pem"

# Should return a long JWT token
```

**If it fails:**
- Check Python 3 or Node.js is installed
- Verify private key exists and is readable
- Check private key format (should be PEM)

### Can't get OAuth access token?

```bash
# Test full authentication flow
./scripts/test-jwt-auth.sh dev
```

**If it fails:**
- Check client ID and secret
- Verify certificate is uploaded to IDCS app
- Verify app is assigned to OIC instance with ServiceAdministrator role
- Check app has correct scopes (should include your OIC URL)

### Export fails?

```bash
# Check integration exists
./scripts/list-integrations.sh dev

# Look for your integration in the HTML report
```

### Import fails?

```bash
# Check .iar file exists in bucket
oci os object list \
  --bucket-name oic-migration-artifacts \
  --prefix "integrations/dev/"

# Check Terraform logs
export TF_LOG=DEBUG
make plan ENV=test
```

### Connection test fails?

- Verify connection properties are correct for the environment
- Check network connectivity from OIC to target system
- Verify credentials are correct
- Check firewall rules

---

## Getting Help

1. **Check logs:**
   ```bash
   # Terraform logs
   cat terraform-debug.log
   
   # Import/export logs
   ls -la /tmp/oic-imports/
   ls -la /tmp/oic-exports/
   ```

2. **Enable debug mode:**
   ```bash
   export TF_LOG=DEBUG
   export TF_LOG_PATH=terraform-debug.log
   ```

3. **Review documentation:**
   - [Full Implementation Guide](./docs/Implementation-Guide.md)
   - [Terraform Module README](./terraform/README.md)
   - [OIC REST API Docs](https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/)

4. **Test components individually:**
   ```bash
   # Test JWT generation
   ./scripts/generate-jwt.sh "$USERNAME" "$CLIENT_ID" "$PRIVATE_KEY"
   
   # Test OAuth flow
   ./scripts/test-jwt-auth.sh dev
   
   # Test OIC API
   TOKEN=$(./scripts/manage-credentials.sh get-oauth-token dev)
   curl -H "Authorization: Bearer $TOKEN" "$OIC_URL/ic/api/integration/v1/integrations"
   ```

---

## Resources

- **OIC Documentation:** https://docs.oracle.com/en/cloud/paas/application-integration/
- **Terraform OCI Provider:** https://registry.terraform.io/providers/oracle/oci/latest/docs
- **OIC REST API:** https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/
- **JWT User Assertion:** https://docs.oracle.com/en/cloud/paas/application-integration/rest-adapter/authenticate-requests-invoking-oic-integration-flows.html

---

**Ready to go!** Start with `make help` to see all available commands.
