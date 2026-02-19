# Certificate Setup Fix Summary

## Problem
The `./ansible-runner.sh certs` command was not working correctly. It needed to:
1. Install cert-manager operator
2. Create AWS credentials secret for Route53 access
3. Generate a CSR for Let's Encrypt via Route53 DNS-01 validation
4. Use AWS credentials on the cluster for DNS challenge
5. Install the certificate as the default ingress certificate

## Solution Implemented

### 1. Rewrote setup-certs.yml Playbook
**Restructured into 3 separate plays:**

#### Play 1: Install cert-manager operator
- Creates `openshift-cert-manager-operator` namespace
- Installs cert-manager operator from OperatorHub
- Configures CertManager CR with Route53 DNS-01 settings
- Waits for CRDs (ClusterIssuer, Certificate) to be available
- Enhanced error handling and validation

#### Play 2: Generate Let's Encrypt wildcard certificate via Route53
- Retrieves AWS credentials from environment variables
- Dynamically queries cluster base domain, Route53 zone ID, and AWS region
- Creates AWS credentials secret in kube-system namespace
- Creates Let's Encrypt ClusterIssuer with Route53 DNS-01 solver
- Generates wildcard certificate (*.apps.<domain>)
- Waits for certificate issuance (DNS-01 validation via Route53)

#### Play 3: Patch OpenShift IngressController
- Copies certificate secret to openshift-ingress namespace
- Patches default IngressController to use the certificate
- Waits for router pods to rollout new certificate
- Verifies IngressController is available with new certificate

### 2. Enhanced Configuration (inventory/group_vars/all.yml)
- Added comprehensive documentation for certificate settings
- Clarified acme_email requirement
- Documented Let's Encrypt staging vs. production
- Added prerequisites and AWS permissions info

### 3. Improved Container (Containerfile)
- Added `jq` and `curl` utilities
- Better documented dependencies
- Cleaner formatting

### 4. Updated Documentation (ansible-runner.sh)
- Added detailed `certs` command documentation
- Explained prerequisites (AWS credentials, email, Route53 permissions)
- Provided verification commands
- Clarified staging vs. production usage

### 5. Created CERTIFICATE-SETUP.md
Comprehensive guide including:
- Overview of certificate installation process
- Prerequisites and IAM permissions
- Step-by-step installation instructions
- How Route53 DNS-01 validation works
- Verification procedures
- Troubleshooting guide
- Advanced configuration options
- Certificate renewal monitoring

## Key Improvements

### 1. Proper Error Handling
- Assert statements for required configurations
- Detailed error messages with solutions
- Retry logic with sensible delays
- Better status checks throughout

### 2. Route53 Integration
- Creates AWS credentials secret in kube-system for cert-manager access
- ClusterIssuer properly configured with Route53 DNS-01 solver
- Automatic zone ID and region detection from cluster
- Full support for DNS challenge validation

### 3. Three-Play Structure
- Separated concerns (installation → certificate generation → ingress patching)
- Each play can be debugged independently
- Better progress reporting

### 4. Secret Management
- AWS credentials stored in kube-system namespace
- Certificate secrets copied to openshift-ingress namespace
- Proper secret copying between namespaces

### 5. Ingress Controller Patching
- Proper secret reference in IngressController spec
- Waits for router pods to rollout
- Verifies final availability status
- Comprehensive verification output

## AWS Permissions Required

For Route53 DNS-01 validation to work, AWS credentials must have:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:GetChange",
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "*"
    }
  ]
}
```

## Usage Examples

### Install Let's Encrypt certificate on all clusters:
```bash
./ansible-runner.sh certs
```

### Install on specific cluster:
```bash
./ansible-runner.sh certs --limit cluster1
```

### Remove certificates:
```bash
./ansible-runner.sh certs --destroy
```

### Verbose output for debugging:
```bash
./ansible-runner.sh certs -v
```

## Verification

After installation, verify with:

```bash
# Check certificate status
oc get certificate acme-wildcard-cert -n kube-system

# Check ClusterIssuer
oc get clusterissuer letsencrypt

# Check IngressController is using certificate
oc get ingresscontroller default -n openshift-ingress-operator -o yaml | grep defaultCertificate

# Test HTTPS connection
curl -I https://console-openshift-console.apps.<domain>
```

## Files Modified

1. `/setup-certs.yml` - Complete rewrite with 3-play structure
2. `/inventory/group_vars/all.yml` - Enhanced certificate configuration documentation
3. `/Containerfile` - Added jq and curl utilities
4. `/ansible-runner.sh` - Improved certs command documentation and usage info
5. `/CERTIFICATE-SETUP.md` - New comprehensive setup guide

## Testing Recommendations

1. **Test with staging first** (default configuration):
   - Unlimited rate limits
   - Non-trusted certificates
   - Perfect for validation

2. **Then switch to production**:
   - Update `acme_server` in inventory/group_vars/all.yml
   - Destroy staging setup
   - Install production certificate

3. **Verify at each step**:
   - Cluster connectivity
   - AWS credentials and Route53 permissions
   - Certificate readiness
   - IngressController availability

## Backward Compatibility

All changes are backward compatible:
- Existing playbooks unaffected
- Configuration variables renamed with explanations
- destroy-certs.yml still works correctly
- No breaking changes to inventory structure
