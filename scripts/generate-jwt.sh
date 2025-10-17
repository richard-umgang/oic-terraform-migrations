#!/bin/bash

#################################################################
# JWT Token Generator for OIC3 OAuth
#
# Generates a JWT token for JWT User Assertion authentication
# 
# Usage: ./generate-jwt.sh <username> <client_id> <private_key_path> [key_alias]
#################################################################

set -e

# Check arguments
if [ $# -lt 3 ]; then
    echo "Usage: $0 <username> <client_id> <private_key_path> [key_alias]"
    echo ""
    echo "Arguments:"
    echo "  username          - IDCS username with ServiceInvoker role"
    echo "                      (e.g., john.doe@example.com or service-account@example.com)"
    echo "  client_id         - OAuth client ID from confidential application"
    echo "  private_key_path  - Path to private key PEM file"
    echo "  key_alias         - (Optional) Certificate alias/kid matching keytool alias"
    echo "                      Default: 'oic-jwt'"
    echo ""
    echo "Example:"
    echo "  $0 john.doe@example.com abc123-client-id ~/.oic-certs/dev/private-key.pem oic-jwt-dev"
    echo ""
    echo "Note: The username must be assigned the ServiceInvoker role in IDCS"
    exit 1
fi

USERNAME="$1"
CLIENT_ID="$2"
PRIVATE_KEY_PATH="$3"
KEY_ALIAS="${4:-oic-jwt}"  # Default to 'oic-jwt' if not provided

# Verify private key exists
if [ ! -f "$PRIVATE_KEY_PATH" ]; then
    echo "Error: Private key not found: $PRIVATE_KEY_PATH"
    exit 1
fi

# Check if we have required tools
if ! command -v python3 &> /dev/null && ! command -v node &> /dev/null; then
    echo "Error: Neither Python 3 nor Node.js found. Please install one of them."
    exit 1
fi

# Generate JWT using Python (preferred)
if command -v python3 &> /dev/null; then
    python3 - <<EOF
import json
import time
import base64
import hashlib
import hmac
from pathlib import Path

def base64url_encode(data):
    """Base64url encode"""
    if isinstance(data, str):
        data = data.encode('utf-8')
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('utf-8')

def generate_jwt(username, client_id, private_key_path, key_alias):
    """Generate JWT token for JWT User Assertion"""
    
    # Read private key
    with open(private_key_path, 'r') as f:
        private_key = f.read()
    
    # Current time and expiry (5 minutes from now)
    now = int(time.time())
    exp = now + 300
    
    # Generate unique JWT ID to prevent replay attacks
    import uuid
    jti = str(uuid.uuid4())
    
    # JWT Header - MUST include kid matching certificate alias
    header = {
        "alg": "RS256",
        "typ": "JWT",
        "kid": key_alias
    }
    
    # JWT Payload
    payload = {
        "sub": username,
        "jti": jti,
        "iat": now,
        "exp": exp,
        "iss": client_id,
        "aud": "https://identity.oraclecloud.com/"
    }
    
    # Encode header and payload
    header_encoded = base64url_encode(json.dumps(header, separators=(',', ':')))
    payload_encoded = base64url_encode(json.dumps(payload, separators=(',', ':')))
    
    # Create signing input
    signing_input = f"{header_encoded}.{payload_encoded}"
    
    # Sign with private key (requires PyJWT or cryptography)
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding
        from cryptography.hazmat.backends import default_backend
        
        # Load private key
        private_key_obj = serialization.load_pem_private_key(
            private_key.encode(),
            password=None,
            backend=default_backend()
        )
        
        # Sign
        signature = private_key_obj.sign(
            signing_input.encode(),
            padding.PKCS1v15(),
            hashes.SHA256()
        )
        
        signature_encoded = base64url_encode(signature)
        
        # Complete JWT
        jwt_token = f"{signing_input}.{signature_encoded}"
        print(jwt_token)
        
    except ImportError:
        # Fallback: use PyJWT if available
        import jwt
        jwt_token = jwt.encode(payload, private_key, algorithm='RS256', headers=header)
        print(jwt_token)

# Generate JWT
generate_jwt("$USERNAME", "$CLIENT_ID", "$PRIVATE_KEY_PATH", "$KEY_ALIAS")
EOF

# Generate JWT using Node.js (fallback)
elif command -v node &> /dev/null; then
    node - <<EOF
const fs = require('fs');
const crypto = require('crypto');

function base64urlEncode(str) {
    return Buffer.from(str)
        .toString('base64')
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=/g, '');
}

function generateJWT(username, clientId, privateKeyPath, keyAlias) {
    // Read private key
    const privateKey = fs.readFileSync(privateKeyPath, 'utf8');
    
    // Current time and expiry
    const now = Math.floor(Date.now() / 1000);
    const exp = now + 300;
    
    // Generate unique JWT ID to prevent replay attacks
    const crypto = require('crypto');
    const jti = crypto.randomUUID();
    
    // JWT Header - MUST include kid matching certificate alias
    const header = {
        alg: 'RS256',
        typ: 'JWT',
        kid: keyAlias
    };
    
    // JWT Payload
    const payload = {
        sub: username,
        jti: jti,
        iat: now,
        exp: exp,
        iss: clientId,
        aud: 'https://identity.oraclecloud.com/'
    };
    
    // Encode
    const headerEncoded = base64urlEncode(JSON.stringify(header));
    const payloadEncoded = base64urlEncode(JSON.stringify(payload));
    const signingInput = \`\${headerEncoded}.\${payloadEncoded}\`;
    
    // Sign
    const sign = crypto.createSign('RSA-SHA256');
    sign.update(signingInput);
    const signature = sign.sign(privateKey);
    const signatureEncoded = base64urlEncode(signature);
    
    // Complete JWT
    const jwt = \`\${signingInput}.\${signatureEncoded}\`;
    console.log(jwt);
}

generateJWT('$USERNAME', '$CLIENT_ID', '$PRIVATE_KEY_PATH', '$KEY_ALIAS');
EOF
fi
