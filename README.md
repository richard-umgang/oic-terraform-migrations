# OIC Terraform Migration Solution

Automated Oracle Integration Cloud (OIC) migration solution using Terraform, enabling consistent and repeatable deployments across DEV, TEST, and PROD environments with JWT authentication.

---

## 🎯 Overview

This solution automates the migration of OIC integrations (with connections) across environments by:

- **Exporting** integrations from DEV as `.iar` files
- **Storing** artifacts in OCI Object Storage with versioning
- **Importing** to TEST/PROD with environment-specific configurations
- **Testing** connections and integrations automatically
- **Tracking** all changes via Terraform state

### Key Features

✅ **Automated Migrations** - No manual export/import  
✅ **Environment-Specific Config** - Different URLs/credentials per environment  
✅ **Version Control** - All artifacts tracked in Git  
✅ **Rollback Capability** - Restore previous versions easily  
✅ **CI/CD Ready** - GitLab pipeline included  
✅ **Secure JWT Auth** - Certificate-based authentication  
✅ **Comprehensive Testing** - Automated test suite

---

## 📋 Prerequisites

### Required Tools

- **Terraform** >= 1.0
- **OCI CLI** configured with API keys
- **jq** for JSON processing
- **OpenSSL** for certificate operations
- **Java keytool** for certificate generation
- **Python 3** or **Node.js** (for JWT generation)

### Required Access

- OCI tenancy with OIC instances
- IDCS admin access for OAuth app creation
- Object Storage bucket for artifacts
- Network access to OIC and IDCS

---

## 🚀 Quick Start

### 1. Install Dependencies

```bash
# Install Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Install OCI CLI
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

# Verify
terraform version
oci --version
```

### 2. Clone and Setup

```bash
git clone <your-repo-url>
cd oic-terraform-migrations

# Initialize
make init
```

### 3. Configure Authentication

Follow the Implementation Guide to:
1. Generate JWT certificates using `keytool` (Oracle's official method)
2. Create IDCS confidential applications (one per environment)
3. Upload certificates and configure OAuth
4. Set environment variables with credentials

See: [`docs/Implementation-Guide.md`](./docs/Implementation-Guide.md) - Section: Authentication Setup

### 4. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# Configure:
# - OIC instance URLs
# - Object Storage bucket
# - Integrations to migrate
```

### 5. Test Authentication

```bash
./scripts/test-jwt-auth.sh dev
./scripts/test-jwt-auth.sh test
./scripts/test-jwt-auth.sh prod
```

### 6. Discover Integrations

```bash
make list-integrations ENV=dev
# Opens HTML report with all integrations and Terraform snippets
```

### 7. Your First Migration

```bash
# Export from DEV
make export-dev

# Import to TEST
make import-test

# Test
make test ENV=test

# Promote to PROD (requires confirmation)
make import-prod
```

---

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [Implementation Guide](./docs/Implementation-Guide.md) | Complete setup and usage guide |
| [Deployment Checklist](./docs/Deployment-Checklist.md) | Pre/post deployment checklist |
| [Setup Summary](./docs/Setup-Summary.md) | Quick reference |

---

## 🏗️ Architecture

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
│  Integrations    │  │  Integrations    │  │  Integrations    │
│  + Connections   │  │  + Connections   │  │  + Connections   │
└──────────────────┘  └──────────────────┘  └──────────────────┘
         │                     ▲                     ▲
         │ Export              │ Import              │ Import
         │ (.iar)              │ (.iar)              │ (.iar)
         ▼                     │                     │
┌──────────────────────────────┴─────────────────────┘
│           OCI Object Storage                       │
│    integrations/dev/INTEGRATION-VERSION.iar        │
│    integrations/dev/INTEGRATION-latest.iar         │
└────────────────────────────────────────────────────┘
```

---

## 💻 Common Commands

### Discovery & Planning

```bash
make list-integrations ENV=dev    # Discover integrations
make status ENV=test               # Show current status
make plan ENV=test                 # Show Terraform plan
```

### Export & Import

```bash
make export-dev                    # Export from DEV
make import-test                   # Import to TEST
make import-prod                   # Import to PROD (with confirmation)
```

### Full Workflows

```bash
make promote-to-test               # DEV → TEST (export + import + test)
make promote-to-prod               # TEST → PROD (verify + import + test)
```

### Testing

```bash
make test ENV=test                 # Run all tests
make test-connections ENV=test     # Test connections only
make smoke-test ENV=prod           # Quick smoke test
make test-auth ENV=dev             # Test JWT authentication
```

### Utilities

```bash
make validate                      # Validate Terraform
make format                        # Format Terraform files
make clean                         # Clean temporary files
make doctor                        # Check dependencies
make help                          # Show all commands
```

---

## 📁 Project Structure

```
oic-terraform-migrations/
├── terraform/                      # Terraform modules
│   ├── modules/
│   │   ├── oic-integration-export/    # Export module
│   │   └── oic-integration-import/    # Import module
│   ├── main.tf                     # Main workflow
│   ├── terraform.tfvars            # Your configuration
│   └── terraform.tfvars.example    # Configuration template
├── scripts/                        # Helper scripts
│   ├── generate-jwt.sh            # JWT token generator
│   ├── manage-credentials.sh      # Credential management
│   ├── list-integrations.sh       # Discovery script
│   ├── test-integrations.sh       # Testing script
│   └── test-jwt-auth.sh           # Auth verification
├── docs/                           # Documentation
│   ├── Implementation-Guide.md    # Complete guide
│   ├── Deployment-Checklist.md    # Deployment checklist
│   └── Setup-Summary.md           # Quick reference
├── .gitlab-ci.yml                  # CI/CD pipeline
├── Makefile                        # Common operations
└── README.md                       # This file
```

---

## 🔐 Security

### JWT Authentication

This solution uses **JWT User Assertion** for authentication:

1. Generate JWT token using your private key
2. Exchange JWT for OAuth access token from IDCS
3. Use access token to call OIC REST APIs

**Requirements:**
- Certificate alias must match JWT `kid` field
- IDCS application must be type **Trusted** (not Confidential)
- Certificate must be uploaded to both OAuth config and Trusted Partners
- Username must have **ServiceInvoker** role in IDCS

### Credentials Management

**Never commit credentials to Git!**

- Store in environment variables
- Or use OCI Vault (see Advanced Topics in Implementation Guide)
- Mark all credentials as "Protected" and "Masked" in GitLab CI/CD

---

## 🔧 Configuration

### terraform.tfvars Example

```hcl
environment = "dev"

oic_instances = {
  dev  = { url = "https://dev-oic...", ... }
  test = { url = "https://test-oic...", ... }
  prod = { url = "https://prod-oic...", ... }
}

integrations_to_migrate = [
  {
    id      = "CUSTOMER_API|01.00.0000"
    code    = "CUSTOMER_API"
    version = "01.00.0000"
    
    connections = {
      rest_conn = {
        id = "CUSTOMER_REST"
        
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

## 🧪 Testing

### Automated Testing

```bash
# Full test suite
make test ENV=test

# Connection tests only
make test-connections ENV=test

# Quick smoke test
make smoke-test ENV=prod
```

### Test Reports

All tests generate HTML reports: `test_report_<env>.html`

---

## 🚀 CI/CD Pipeline

Included GitLab CI/CD pipeline provides:

- **Automatic validation** on all branches
- **Auto-export from DEV** on main branch
- **Auto-import to TEST** after export
- **Automated testing** after imports
- **Manual approval** for PROD deployments
- **Slack notifications** (optional)

### Setup

1. Copy `.gitlab-ci.yml` to your repository
2. Configure CI/CD variables in GitLab:
   - `OAUTH_CLIENT_ID_*`
   - `OAUTH_CLIENT_SECRET_*`
   - `OAUTH_USERNAME_*`
   - `OAUTH_PRIVATE_KEY_*`
   - `SLACK_WEBHOOK_URL` (optional)

---

## 🐛 Troubleshooting

### Authentication Issues

**"invalid_client" error:**
- Verify application is Active in IDCS
- Check Client type = Trusted (NOT Confidential)
- Verify certificate uploaded to OAuth config
- Verify certificate added to Trusted Partner Certificates
- Check credentials have no extra spaces: `echo "$CLIENT_ID" | od -c`

**JWT generation fails:**
- Check private key: `openssl rsa -in private-key.pem -check`
- Verify permissions: `ls -la private-key.pem` (should be 600)
- Verify key alias matches certificate alias

### Export/Import Issues

```bash
# Enable debug mode
export TF_LOG=DEBUG
make plan ENV=test

# Check Object Storage
oci os object list --bucket-name oic-migration-artifacts

# Verify integration exists
./scripts/list-integrations.sh dev
```

### Connection Issues

```bash
# Test connections
make test-connections ENV=test

# Check logs in OIC console
# Verify network connectivity
# Verify credentials for target environment
```

---

## 📚 Additional Resources

- **OIC Documentation:** https://docs.oracle.com/en/cloud/paas/application-integration/
- **OIC REST API:** https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/
- **Oracle JWT Auth:** https://docs.oracle.com/en/cloud/paas/application-integration/rest-adapter/authenticate-requests-invoking-oic-integration-flows.html
- **Terraform OCI Provider:** https://registry.terraform.io/providers/oracle/oci/latest/docs

---

## 🤝 Contributing

1. Create a feature branch
2. Make your changes
3. Run `make validate` and `make format`
4. Submit a pull request

---

## 📝 License

[Your License Here]

---

## 👥 Support

For issues and questions:
1. Check the [Implementation Guide](./docs/Implementation-Guide.md)
2. Review [Troubleshooting](#-troubleshooting) section
3. Check OIC documentation
4. Contact your team lead

---

**Version:** 1.0 (JWT-Only)  
**Last Updated:** 2024

---

## ⚡ Quick Commands Reference

```bash
# Setup
make init                         # Initialize Terraform
./scripts/test-jwt-auth.sh dev   # Test authentication

# Discovery
make list-integrations ENV=dev   # Discover integrations

# Export/Import
make export-dev                   # Export from DEV
make import-test                  # Import to TEST
make import-prod                  # Import to PROD

# Testing
make test ENV=test                # Run tests

# Full workflow
make promote-to-test              # DEV → TEST
make promote-to-prod              # TEST → PROD

# Utilities
make help                         # Show all commands
make doctor                       # Check dependencies
```

---

**Ready to get started?** See the [Implementation Guide](./docs/Implementation-Guide.md) for detailed setup instructions.
