# Let's Encrypt Certificate Setup for OpenShift Clusters

This guide explains how to use the `./ansible-runner.sh certs` command to install cert-manager and configure Let's Encrypt wildcard certificates with Route53 DNS-01 validation.

## Overview

The `certs` command automates the entire process of:
1. Installing cert-manager operator from Red Hat's OperatorHub
2. Creating a Let's Encrypt ClusterIssuer with Route53 DNS-01 solver
3. Generating a wildcard certificate for `*.apps.<cluster-base-domain>`
4. Patching the OpenShift IngressController to use the certificate
5. Configuring automatic certificate renewal

## Prerequisites

### 1. Deployed Clusters
Your clusters must already be deployed:
```bash
./ansible-runner.sh deploy
```

### 2. AWS Credentials with Route53 Permissions
Each cluster's AWS credential set must have permissions to modify Route53 records for DNS-01 validation:

```bash
export AWS_ACCESS_KEY_ID_1="your-access-key"
export AWS_SECRET_ACCESS_KEY_1="your-secret-key"
export AWS_REGION_1="us-east-1"
```

**Required IAM Permissions:**
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

### 3. Email Configuration
Set your email address for Let's Encrypt registration in `inventory/group_vars/all.yml`:

```yaml
acme_email: "admin@yourdomain.com"
```

This email will receive certificate expiry notifications.

## Installation

### Basic Usage

To install Let's Encrypt certificates on all clusters:

```bash
./ansible-runner.sh certs
```

To install on a specific cluster:

```bash
./ansible-runner.sh certs --limit cluster1
```

### Using Let's Encrypt Staging (Recommended for Testing)

The default configuration uses Let's Encrypt **staging environment**:
- ✓ No rate limits
- ✓ Certificates not trusted by browsers (for testing)
- ✓ Ideal for validating setup

```bash
# Staging is the default in inventory/group_vars/all.yml
./ansible-runner.sh certs
```

### Using Let's Encrypt Production (Real Certificates)

Once testing is complete, switch to production certificates in `inventory/group_vars/all.yml`:

```yaml
acme_server: "https://acme-v02.api.letsencrypt.org/directory"
```

Then install:
```bash
./ansible-runner.sh certs
```

**Warning:** Let's Encrypt production has rate limits:
- 50 certificates per domain per week
- 5 duplicate certificates per week
- Use staging first to validate your setup!

## How It Works

### Step 1: Install cert-manager Operator
The playbook installs the Red Hat cert-manager operator from OperatorHub:
- Namespace: `openshift-cert-manager-operator`
- Provides CertManager, Certificate, and ClusterIssuer CRDs

### Step 2: Create AWS Credentials Secret
AWS credentials are stored in `kube-system` namespace for Route53 access:
```bash
oc get secret aws-route53-credentials -n kube-system
```

### Step 3: Create Let's Encrypt ClusterIssuer
A ClusterIssuer resource is created that:
- Points to Let's Encrypt ACME server
- Uses Route53 DNS-01 solver for domain validation
- Stores ACME account key in `<issuer-name>-account-key` secret

### Step 4: Generate Wildcard Certificate
A Certificate resource triggers certificate generation:
- Domain: `*.apps.<cluster-base-domain>`
- Validation: Route53 DNS challenge (cert-manager creates temporary TXT records)
- Duration: 90 days (Let's Encrypt standard)
- Renewal: Automatic 30 days before expiry

### Step 5: Patch IngressController
The OpenShift IngressController is patched to use the new certificate:
- Secret is copied to `openshift-ingress` namespace
- IngressController `default` is patched with the certificate reference
- All ingress routes now use the wildcard certificate

## Verification

### Verify Certificate is Ready
```bash
# Check certificate status
oc get certificate acme-wildcard-cert -n kube-system

# Get detailed certificate info
oc describe certificate acme-wildcard-cert -n kube-system

# Check certificate secret in kube-system
oc get secret acme-wildcard-cert-secret -n kube-system
```

### Verify IngressController is Using Certificate
```bash
# Check IngressController configuration
oc get ingresscontroller default -n openshift-ingress-operator -o yaml

# Check router pod is running
oc get pods -n openshift-ingress

# Verify certificate in openshift-ingress namespace
oc get secret acme-wildcard-cert-secret -n openshift-ingress
```

### Test Certificate with HTTPS
```bash
# Get cluster API domain
DOMAIN=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')
APPS_DOMAIN="*.apps.$DOMAIN"

# Test with any ingress route (e.g., console)
curl -k -I https://console-openshift-console.apps.$DOMAIN

# For production certificates, verify without -k
curl -I https://console-openshift-console.apps.$DOMAIN
```

### Check Let's Encrypt Account
```bash
# View ACME account key secret (staging or production)
oc get secret letsencrypt-account-key -n kube-system -o yaml
```

## Troubleshooting

### Certificate Stuck in "Pending" State

**Check for DNS validation errors:**
```bash
oc describe certificate acme-wildcard-cert -n kube-system
```

**Common issues:**
1. **AWS credentials invalid** - Verify Route53 permissions
2. **Zone ID incorrect** - Verify Route53 hosted zone contains cluster domain
3. **DNS propagation delay** - Wait up to 2 minutes for Route53 records to propagate

**Manual investigation:**
```bash
# Check cert-manager logs
oc logs -n openshift-cert-manager deployment/cert-manager -f

# Check DNS solver pod
oc get pods -n openshift-cert-manager | grep acme

# View certificate challenge status
oc get challenge -n kube-system
```

### IngressController Not Updated

**Check if certificate secret exists in openshift-ingress:**
```bash
oc get secret acme-wildcard-cert-secret -n openshift-ingress
```

**Manual patch if needed:**
```bash
oc patch ingresscontroller default -n openshift-ingress-operator \
  --type=merge \
  -p '{"spec":{"defaultCertificate":{"name":"acme-wildcard-cert-secret"}}}'
```

**Watch router pods rollout:**
```bash
oc rollout status deployment/router-default -n openshift-ingress
```

### Certificate Not Trusted by Browsers

**If using staging environment:**
This is expected! Staging certificates are not trusted. Switch to production:
1. Update `acme_server` in `inventory/group_vars/all.yml`
2. Run `./ansible-runner.sh certs --destroy` to clean up staging cert
3. Run `./ansible-runner.sh certs` to install production cert

**If using production:**
- Verify certificate is issued by "R3" (Let's Encrypt)
- Check certificate is for `*.apps.<domain>` wildcard
- Verify browser trusts Let's Encrypt CA

## Removing Certificates

To remove cert-manager and all certificates:

```bash
./ansible-runner.sh certs --destroy
```

This will:
- Delete Certificate resources
- Delete ClusterIssuer resources
- Remove AWS credentials secret
- Remove certificate secrets
- Delete cert-manager operator
- Restore IngressController to default certificate

## Advanced Configuration

### Custom ACME Email
Edit `inventory/group_vars/all.yml`:
```yaml
acme_email: "security@yourdomain.com"
```

### Custom Issuer Name
Override in cluster's `inventory/host_vars/`:
```yaml
acme_issuer_name: "letsencrypt-prod"
```

### Custom Certificate Names
Override in `inventory/group_vars/all.yml`:
```yaml
cert_name: "production-wildcard-cert"
cert_secret_name: "production-cert-secret"
```

### Multiple Certificate Issuers

Create additional ClusterIssuers in `inventory/host_vars/cluster-name.yml`:
```yaml
additional_issuers:
  - name: "letsencrypt-wildcard"
    domain: "*.apps.example.com"
  - name: "letsencrypt-api"
    domain: "api.example.com"
```

## Monitoring Certificate Renewal

cert-manager automatically renews certificates 30 days before expiry. Monitor renewal:

```bash
# Watch certificate for renewal events
oc get events -n kube-system | grep Certificate

# Check certificate remaining validity
oc get certificate acme-wildcard-cert -n kube-system -o jsonpath='{.status.notAfter}'

# Manual renewal (if needed)
oc delete secret acme-wildcard-cert-secret -n kube-system
oc delete certificate acme-wildcard-cert -n kube-system
# Re-apply certificate resource
```

## References

- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [OpenShift IngressController](https://docs.openshift.com/container-platform/latest/networking/routes/route-configuration.html)
- [Route53 DNS API Reference](https://docs.aws.amazon.com/Route53/latest/APIReference/)
