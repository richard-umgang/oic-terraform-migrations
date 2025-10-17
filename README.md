# OIC3 Terraform Migration

Automated migration of Oracle Integration Cloud (OIC3) integrations between DEV, TEST, and PROD environments using Terraform and JWT authentication.

[![Terraform](https://img.shields.io/badge/Terraform-1.6+-purple)](https://www.terraform.io/)
[![OCI](https://img.shields.io/badge/OCI-Compatible-red)](https://www.oracle.com/cloud/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 🎯 What This Does

- **Exports** integrations (with connections) from DEV as `.iar` files
- **Stores** artifacts in OCI Object Storage with versioning
- **Imports** to TEST/PROD with environment-specific configurations  
- **Tests** connections and integrations automatically
- **Tracks** all changes via Terraform state and Git

## ✨ Key Features

- ✅ **JWT User Assertion** - Enterprise-grade authentication with certificates
- ✅ **Infrastructure as Code** - All migrations defined in Terraform
- ✅ **Version Control** - Track all integration artifacts in Object Storage
- ✅ **Environment-Specific Configs** - Automatically update connection properties per environment
- ✅ **Automated Testing** - Test integrations and connections after deployment
- ✅ **CI/CD Ready** - GitLab pipeline included with approval gates
- ✅ **Rollback Support** - Restore previous versions easily
- ✅ **Discovery Tools** - List all integrations and generate configurations

---

## 🚀 Quick Start

### Prerequisites

- Terraform 1.6+
- OCI CLI configured
- Python 3 or Node.js (for JWT generation)
- jq (JSON processor)
- Java keytool (for certificate generation)
- Access to OIC3 instances in DEV, TEST, and PROD

### Installation

```bash
# Clone repository
git clone <your-repo-url>
cd oic-terraform-migrations

# Make scripts executable
chmod +x scripts/*.sh

# Initialize Terraform
cd terraform && terraform init && cd ..
```

### Setup Guide

Follow the [Implementation Guide](./docs/Implementation-Guide.md) for complete setup instructions including:

1. **JWT Certificate Generation** (using Oracle's keytool method)
2. **IDCS Application Configuration** (with Trusted client type)
3. **Terraform Configuration** (terraform.tfvars setup)
4. **Authentication Testing** (verify JWT flow)
5. **First Migration** (export from DEV, import to TEST)

### Your First Commands

```bash
# Test JWT authentication
# Note: Ensure your IDCS user has the ServiceInvoker role
./scripts/test-jwt-auth.sh dev

# Discover available integrations
make list-integrations ENV=dev

# Export from DEV
make export-dev

# Import to TEST
make import-test

# Run tests
make test ENV=test
```

---

## 📁 Project Structure

```
oic-terraform-migrations/
├── terraform/                          # Terraform modules
│   ├── modules/
│   │   ├── oic-integration-export/    # Export module
│   │   └── oic-integration-import/    # Import module
│   ├── main.tf                         # Main workflow
│   ├── terraform.tfvars                # Your configuration
│   └── terraform.tfvars.example        # Template
├── scripts/                            # Helper scripts
│   ├── generate-jwt.sh                 # JWT token generator
│   ├── manage-credentials.sh           # Credential management
│   ├── list-integrations.sh            # Discovery
│   ├── test-integrations.sh            # Testing
│   └── test-jwt-auth.sh                # Auth validation
├── docs/                               # Documentation
│   ├── Quick-Start-Guide.md            # 30-min setup
│   ├── Implementation-Guide.md         # Complete guide
│   ├── Deployment-Checklist.md         # Production checklist
│   └── Setup-Summary.md                # Post-setup guide
├── Makefile                            # Common operations
├── .gitlab-ci.yml                      # CI/CD pipeline
└── README.md                           # This file
```

---

## 🔧 Configuration

### terraform.tfvars

```hcl
# Environment
environment = "dev"

# OIC Instances
oic_instances = {
  dev  = { url = "...", instance_name = "...", idcs_url = "..." }
  test = { url = "...", instance_name = "...", idcs_url = "..." }
  prod = { url = "...", instance_name = "...", idcs_url = "..." }
}

# JWT Credentials (from environment variables)
oauth_credentials = {
  dev  = { client_id = "", client_secret = "", username = "", private_key_path = "" }
  test = { client_id = "", client_secret = "", username = "", private_key_path = "" }
  prod = { client_id = "", client_secret = "", username = "", private_key_path = "" }
}

# Object Storage
bucket_config = {
  name           = "oic-migration-artifacts"
  namespace      = "your-tenancy"
  compartment_id = "ocid1.compartment.oc1..."
}

# Integrations to Migrate
integrations_to_migrate = [
  {
    id      = "HELLO_WORLD|01.00.0000"
    code    = "HELLO_WORLD"
    version = "01.00.0000"
    
    connections = {
      rest_conn = {
        id = "REST_CONNECTION"
        test_properties = { ... }
        prod_properties = { ... }
      }
    }
  }
]
```

---

## 💻 Common Commands

### Discovery & Status

```bash
make list-integrations ENV=dev      # List all integrations
make status ENV=test                 # Show current status
make test-auth ENV=dev               # Test JWT authentication
```

### Export & Import

```bash
make export-dev                      # Export from DEV
make import-test                     # Import to TEST
make import-prod                     # Import to PROD (with confirmation)
```

### Complete Workflows

```bash
make promote-to-test                 # DEV → TEST (export + import + test)
make promote-to-prod                 # DEV → PROD (export + import + test)
```

### Testing

```bash
make test ENV=test                   # Run all integration tests
make test-connections ENV=test       # Test connections only
make smoke-test ENV=prod             # Quick smoke test
```

### Backup & Recovery

```bash
make backup ENV=prod                 # Backup PROD integrations
make list-backups                    # Show available backups
make restore ENV=prod DATE=<date>    # Restore from backup
```

### Utilities

```bash
make help                            # Show all commands
make validate                        # Validate Terraform
make format                          # Format Terraform files
make clean                           # Clean temporary files
```

---

## 🔐 Authentication

Uses JWT User Assertion for secure API access to OIC3 instances.

### Authentication Flow

```
1. Generate JWT Token
   ├── Sign with private key
   ├── Include username and client ID
   └── Valid for 5 minutes

2. Exchange JWT for Access Token
   ├── POST to IDCS OAuth2 endpoint
   ├── grant_type: jwt-bearer
   └── Get access token (valid 1 hour)

3. Call OIC REST APIs
   └── Authorization: Bearer <access_token>
```

### Setup

See [Quick Start Guide](./docs/Quick-Start-Guide.md#step-3-configure-oauth2-with-jwt-10-minutes) for detailed JWT setup instructions.

---

## 🔄 Typical Workflow

### 1. Development

```bash
# Develop integration in DEV OIC console
# Test the integration
```

### 2. Export

```bash
# Discover integrations
make list-integrations ENV=dev

# Export to Object Storage
make export-dev
```

### 3. Import to TEST

```bash
# Import and configure
make import-test

# Test
make test ENV=test
```

### 4. Promote to PROD

```bash
# After TEST validation
make import-prod

# Manual approval required
# Type: PROD
```

---

## 🤖 CI/CD Pipeline

GitLab CI/CD pipeline included with:

- ✅ **Automatic validation** on merge requests
- ✅ **Automatic export** from DEV on main branch
- ✅ **Automatic import** to TEST
- ✅ **Automated testing** in TEST
- ✅ **Manual approval** for PROD deployment
- ✅ **Rollback capability**
- ✅ **Slack notifications** (optional)

### Configure GitLab CI/CD

Set these variables in GitLab → Settings → CI/CD → Variables:

**JWT Credentials (for each environment):**
- `OAUTH_CLIENT_ID_DEV`
- `OAUTH_CLIENT_SECRET_DEV` (Protected, Masked)
- `OAUTH_USERNAME_DEV`
- `OAUTH_PRIVATE_KEY_DEV` (File type)

Repeat for TEST and PROD.

See [.gitlab-ci.yml](./.gitlab-ci.yml) for complete configuration.

---

## 📊 Monitoring & Testing

### Automated Tests

After each import, the solution automatically:

1. **Tests connections** - Verifies connectivity and credentials
2. **Tests integrations** - Checks activation status
3. **Generates reports** - HTML test reports with results

### Test Reports

```bash
# Run tests
make test ENV=test

# View report
open test_report_test.html
```

Reports include:
- ✅ Integration activation status
- ✅ Connection test results
- ✅ Detailed error messages
- ✅ Summary statistics

---

## 🛡️ Security

### Best Practices

- ✅ **JWT User Assertion** - Certificate-based authentication
- ✅ **OCI Vault** - Store credentials securely (recommended)
- ✅ **Environment Variables** - Never commit credentials to Git
- ✅ **GitLab Protected Variables** - Use protected and masked variables
- ✅ **Certificate Rotation** - Rotate annually
- ✅ **Access Control** - Limit who can deploy to PROD
- ✅ **Audit Trail** - All API calls logged

### Storing Credentials

**Option 1: Environment Variables (Development)**
```bash
export OAUTH_CLIENT_ID_DEV="..."
export OAUTH_CLIENT_SECRET_DEV="..."
export OAUTH_USERNAME_DEV="..."
export OAUTH_PRIVATE_KEY_DEV="~/.oic-certs/dev/private-key.pem"
```

**Option 2: OCI Vault (Production)**
```bash
./scripts/manage-credentials.sh store-oauth dev \
  "$CLIENT_ID" "$CLIENT_SECRET" "$USERNAME" "$PRIVATE_KEY_PATH"
```

---

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [Implementation Guide](./docs/Implementation-Guide.md) | Complete setup and reference guide |
| [Deployment Checklist](./docs/Deployment-Checklist.md) | Production deployment checklist |
| [Setup Summary](./docs/Setup-Summary.md) | Post-setup guide and next steps |

---

## 🐛 Troubleshooting

### Authentication Issues

```bash
# Test JWT authentication
./scripts/test-jwt-auth.sh dev

# Should show:
# ✓ All Tests Passed!
```

**Common issues:**
- Certificate not uploaded to IDCS
- App not assigned to OIC instance
- Wrong client ID or secret
- Private key not readable

### Export/Import Issues

```bash
# Enable debug logging
export TF_LOG=DEBUG

# Run plan to see details
make plan ENV=test

# Check logs
cat terraform-debug.log
```

### Connection Issues

```bash
# Test connections manually
make test-connections ENV=test

# Check OIC console
# Connections → [Your Connection] → Test
```

See [Implementation Guide](./docs/Implementation-Guide.md#troubleshooting) for detailed troubleshooting.

---

## 🤝 Contributing

1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Submit a pull request
5. Ensure CI/CD passes

### Development Setup

```bash
# Install development dependencies
make dev-setup

# Run development tests
make dev-test

# Clean development environment
make dev-clean
```

---

## 📜 License

[Your License Here]

---

## 🙏 Support

- 📖 Check the [documentation](./docs/)
- 🐛 Open an [issue](../../issues)
- 💬 Contact your OIC administrator
- 📚 Review [OIC documentation](https://docs.oracle.com/en/cloud/paas/application-integration/)

---

## 🔗 Resources

- [Oracle Integration Cloud Documentation](https://docs.oracle.com/en/cloud/paas/application-integration/)
- [OIC REST API Reference](https://docs.oracle.com/en/cloud/paas/application-integration/rest-api/)
- [Terraform OCI Provider](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [JWT User Assertion Guide](https://docs.oracle.com/en/cloud/paas/application-integration/rest-adapter/authenticate-requests-invoking-oic-integration-flows.html)

---

**Made with ❤️ for OIC automation**  
**Version:** 1.0 (JWT-Only)  
**Authentication:** JWT User Assertion with Certificates
