#!/bin/bash
# Run Ansible playbooks using Podman container
# This eliminates the need to install Ansible on the host

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="localhost/regional-dr-ansible:latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Source secret.sh if it exists and credentials are not already set
if [ -f "$SCRIPT_DIR/secret.sh" ] && [ -z "$AWS_ACCESS_KEY_ID_1" ]; then
    print_info "Loading credentials from secret.sh"
    source "$SCRIPT_DIR/secret.sh"
fi

# Check if podman is installed
if ! command -v podman &> /dev/null; then
    print_error "Podman is required but not installed"
    echo "Install podman:"
    echo "  RHEL/Fedora: sudo dnf install -y podman"
    echo "  Ubuntu/Debian: sudo apt install -y podman"
    exit 1
fi

# Build the Ansible container image if it doesn't exist
build_image() {
    print_info "Checking for Ansible container image..."

    if podman image exists "$IMAGE_NAME"; then
        print_info "Ansible container image already exists"
        return 0
    fi

    print_info "Building Ansible container image..."
    cd "$SCRIPT_DIR"

    if [ -f "Containerfile" ]; then
        # Extract openshift_version from group_vars for the container build
        local ocp_version
        ocp_version=$(grep -E '^\s*openshift_version:' "$SCRIPT_DIR/inventory/group_vars/all.yml" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' || echo "4.19")
        print_info "Building with OpenShift version: $ocp_version"
        podman build --build-arg OPENSHIFT_VERSION="$ocp_version" -t "$IMAGE_NAME" -f Containerfile .
        print_info "Image built successfully"
    else
        print_error "Containerfile not found in $SCRIPT_DIR"
        exit 1
    fi
}

# Function to run Ansible playbook in container
run_ansible() {
    local playbook="$1"
    shift
    local extra_args="$@"

    if [ ! -f "$SCRIPT_DIR/$playbook" ]; then
        print_error "Playbook not found: $playbook"
        exit 1
    fi

    print_info "Running playbook: $playbook"

    # Ensure cache directory exists
    mkdir -p /tmp/openshift-installer-cache

    # Prepare volume mounts
    local volumes=(
        "-v" "$SCRIPT_DIR:/workspace:Z"
        "-v" "/tmp/openshift-installer-cache:/tmp/openshift-installer-cache:Z"
    )

    # Mount SSH key if it exists
    if [ -f "$SCRIPT_DIR/ssh-key" ]; then
        volumes+=("-v" "$SCRIPT_DIR/ssh-key:/workspace/ssh-key:Z")
    fi

    # Prepare environment variables
    local env_vars=()

    # Pass through kubeconfig
    if [ -n "$KUBECONFIG" ]; then
        env_vars+=("-e" "KUBECONFIG=${KUBECONFIG}")
        if [ -f "$KUBECONFIG" ]; then
            volumes+=("-v" "$KUBECONFIG:$KUBECONFIG:Z")
        fi
    fi

    # Pass through all AWS credential sets (1-3)
    for i in 1 2 3; do
        local access_key_var="AWS_ACCESS_KEY_ID_${i}"
        local secret_key_var="AWS_SECRET_ACCESS_KEY_${i}"
        local region_var="AWS_REGION_${i}"

        if [ -n "${!access_key_var}" ]; then
            env_vars+=("-e" "${access_key_var}=${!access_key_var}")
            env_vars+=("-e" "${secret_key_var}=${!secret_key_var}")
            env_vars+=("-e" "${region_var}=${!region_var:-us-east-1}")
        fi
    done

    # Run the container
    podman run --rm -it \
        "${volumes[@]}" \
        "${env_vars[@]}" \
        --network host \
        "$IMAGE_NAME" \
        -i /workspace/inventory/hosts \
        "$playbook" \
        $extra_args
}

# Show usage
usage() {
    cat << EOF
Usage: $0 <command> [options]

Commands:
    build           Build the Ansible container image
    generate-configs Generate install-config.yaml without deploying
    deploy          Deploy OpenShift cluster(s) on AWS
    destroy         Destroy OpenShift cluster(s) on AWS
    operators       Install DR operators on deployed clusters
    import          Import spoke clusters into ACM hub
    infra-dr        Configure DR infrastructure (Submariner, ODF, SSL certs)
    app             Deploy DR-protected sample application (Quarkus + MySQL)
    certs           Install cert-manager and Let's Encrypt wildcard certificate
    netobserv       Install NetObserv for network traffic monitoring
    acs             Install ACS (Advanced Cluster Security) for cluster security
    virt            Deploy VM DR example (OpenShift Virtualization + Regional DR)
    validate        Validate configuration and credentials
    list            List configured clusters
    run <playbook>  Run a specific playbook
    shell           Open a shell in the Ansible container

Options:
    --limit <host>      Limit execution to specific host
    -v, --verbose       Verbose output
    --check             Run in check mode
    --yes               Skip confirmation prompts (for destroy command)
    --destroy           Remove resources (for operators, import, infra-dr, certs commands)
    -h, --help          Show this help message

Examples:
    $0 build
    $0 generate-configs --limit cluster1
    $0 deploy
    $0 deploy --limit cluster1 -v
    $0 destroy --yes
    $0 certs                          # Install Let's Encrypt cert with Route53 DNS-01
    $0 certs --limit cluster1         # Install cert on specific cluster
    $0 certs --destroy                # Remove cert-manager and certificates
    $0 netobserv                      # Install NetObserv on clusters with netobserv: true
    $0 netobserv --limit cluster1     # Install on specific cluster
    $0 netobserv --destroy            # Remove NetObserv, Loki, and S3 bucket
    $0 acs                            # Install ACS Central + SecuredCluster on all clusters
    $0 acs --destroy                  # Remove ACS from all clusters
    $0 virt                           # Deploy VM DR example on spoke clusters
    $0 virt --destroy                 # Remove VM DR example and CNV policy
    $0 operators
    $0 infra-dr
    $0 app                            # Deploy DR-protected sample application
    $0 app --destroy                  # Remove DR application and DRPolicy
    $0 validate
    $0 list

Certificate Command (./ansible-runner.sh certs):
    Installs cert-manager operator and configures Let's Encrypt wildcard certificates
    using Route53 DNS-01 validation for automatic certificate renewal.
    
    Prerequisites:
    1. Cluster must be deployed: $0 deploy
    2. AWS credentials must be set (via environment variables):
       export AWS_ACCESS_KEY_ID_N="..."
       export AWS_SECRET_ACCESS_KEY_N="..."
       export AWS_REGION_N="us-east-1"
    3. AWS credentials must have Route53 permissions for DNS validation
    4. acme_email must be configured in inventory/group_vars/all.yml
    
    What it does:
    1. Installs cert-manager operator from OperatorHub
    2. Creates Let's Encrypt ClusterIssuer with Route53 DNS-01 solver
    3. Generates wildcard certificate for *.apps.<base-domain>
    4. Patches IngressController to use the certificate
    5. Sets up automatic certificate renewal
    
    Verify installation:
       oc get certificate -n kube-system
       oc get clusterissuer
       oc get ingresscontroller default -n openshift-ingress-operator

NetObserv Command (./ansible-runner.sh netobserv):
    Installs NetObserv for network traffic monitoring with Loki backend on S3.
    Only runs on clusters marked with netobserv: true in inventory.
    
    Prerequisites:
    1. Cluster must be deployed: $0 deploy
    2. Cluster must have netobserv: true label in inventory/host_vars/
    3. AWS credentials must be set (via environment variables):
       export AWS_ACCESS_KEY_ID_N="..."
       export AWS_SECRET_ACCESS_KEY_N="..."
       export AWS_REGION_N="us-east-1"
    4. AWS credentials must have S3 and IAM permissions
    
    What it does:
    1. Provisions S3 bucket for Loki log storage
    2. Installs Loki operator from OperatorHub
    3. Configures LokiStack with S3 backend
    4. Installs NetObserv operator from OperatorHub
    5. Creates FlowCollector with eBPF agent for network monitoring
    6. Configures FlowCollector to send flows to Loki
    
    Configuration in inventory/host_vars/<cluster>.yml:
       netobserv: true              # Enable NetObserv on this cluster
    
    Verify installation:
       oc get lokistack -n openshift-logging
       oc get flowcollector -n netobserv
       oc port-forward -n netobserv svc/netobserv-ui 3000:3000
       # Open http://localhost:3000

ACS Command (./ansible-runner.sh acs):
    Installs Red Hat Advanced Cluster Security (RHACS) with Central on the hub
    and SecuredCluster on all managed clusters via ACM Policy.

    Prerequisites:
    1. Clusters deployed: $0 deploy
    2. Operators installed: $0 operators
    3. Clusters imported: $0 import

    What it does:
    1. Installs ACS operator on hub cluster
    2. Creates Central CR with route exposure, PVC, and scanner
    3. Generates init bundle via Central REST API
    4. Creates ACM Policy to deploy ACS operator on managed clusters
    5. Injects init bundle TLS secrets via hub templates
    6. Creates SecuredCluster CR on all managed clusters

    Configuration in inventory/group_vars/all.yml:
       acs_channel: "stable"           # ACS operator channel
       acs_deploy_all_clusters: true   # Deploy to all clusters (or set acs: true per cluster)

    Verify installation:
       oc get central -n stackrox
       oc get route central -n stackrox
       oc get securedcluster -n stackrox
       oc get pods -n stackrox

    Central console:
       URL: oc get route central -n stackrox -o jsonpath='{.spec.host}'
       User: admin
       Pass: oc get secret central-htpasswd -n stackrox -o jsonpath='{.data.password}' | base64 -d

DR Application Command (./ansible-runner.sh app):
    Deploys TWO DR-protected instances of a sample application (Quarkus + MySQL):

    Instance 1 (GitOps): Deployed via OpenShift GitOps (ArgoCD) in push mode.
      - Installs GitOps operator, registers spokes with ArgoCD
      - ApplicationSet with ClusterDecisionResource generator
      - DRPlacementControl manages failover by changing PlacementDecision
      - Namespace: quarkus-web-app

    Instance 2 (Direct): Manifests applied directly to primary spoke.
      - oc apply manifests to preferred spoke cluster
      - DRPlacementControl with kubeObjectProtection for failover
      - Namespace: quarkus-web-app-direct

    Prerequisites:
    1. Clusters deployed: $0 deploy
    2. Operators installed: $0 operators
    3. Clusters imported: $0 import
    4. DR infrastructure configured: $0 infra-dr
    5. app_git_url configured in inventory/group_vars/all.yml
       (Git repo URL containing the app/ directory manifests)

    What it does:
    1. Enables Ceph RBD mirroring via MirrorPeer between spokes
    2. Creates DRPolicy for async replication
    3. Installs OpenShift GitOps and configures ArgoCD push mode
    4. Deploys Instance 1 via ArgoCD ApplicationSet + DRPlacementControl
    5. Deploys Instance 2 directly to primary spoke + DRPlacementControl

    GitOps failover:
       oc patch drplacementcontrol quarkus-mysql-app-gitops-drpc -n openshift-gitops \\
         --type=merge --patch='{"spec":{"action":"Failover","failoverCluster":"<cluster>"}}'

    Direct failover:
       oc patch drplacementcontrol quarkus-mysql-app-direct-drpc -n quarkus-web-app-direct \\
         --type=merge --patch='{"spec":{"action":"Failover","failoverCluster":"<cluster>"}}'

    Verify installation:
       oc get drpolicy
       oc get applicationset -n openshift-gitops
       oc get drplacementcontrol -n openshift-gitops
       oc get drplacementcontrol -n quarkus-web-app-direct
       oc get pods -n quarkus-web-app          # GitOps instance on spoke
       oc get pods -n quarkus-web-app-direct   # Direct instance on spoke

VM DR Example Command (./ansible-runner.sh virt):
    Deploys a DR-protected VirtualMachine between spoke clusters using
    OpenShift Virtualization operator (via ACM Policy) and GitOps (ArgoCD).

    Prerequisites:
    1. Clusters deployed: $0 deploy
    2. Operators installed: $0 operators
    3. Clusters imported: $0 import
    4. DR infrastructure configured: $0 infra-dr
    5. DR app deployed (for GitOps setup): $0 app
    6. app_git_url configured pointing to repo with vm-app/ directory

    What it does:
    1. Installs OpenShift Virtualization operator on spokes via ACM Policy
    2. Waits for HyperConverged CR readiness on each spoke
    3. Deploys Fedora VM with persistent data disk via ArgoCD ApplicationSet
    4. Creates DRPlacementControl for VM failover/relocate
    5. Verifies VM is running and test data is written

    Failover:
       oc patch drplacementcontrol vm-dr-example-gitops-drpc -n openshift-gitops \\
         --type=merge --patch='{"spec":{"action":"Failover","failoverCluster":"<cluster>"}}'

    Relocate (failback):
       oc patch drplacementcontrol vm-dr-example-gitops-drpc -n openshift-gitops \\
         --type=merge --patch='{"spec":{"action":"Relocate","preferredCluster":"<cluster>"}}'

    Verify installation:
       oc get hyperconverged -n openshift-cnv       # CNV operator on spokes
       oc get vm -n vm-example                      # VM on preferred spoke
       oc get vmi -n vm-example                     # VM instance
       oc get pvc -n vm-example                     # Persistent data disk
       oc get applicationset -n openshift-gitops    # ArgoCD ApplicationSet
       oc get drplacementcontrol -n openshift-gitops # DR protection

Environment Variables:
    AWS_ACCESS_KEY_ID_1         Primary AWS access key
    AWS_SECRET_ACCESS_KEY_1     Primary AWS secret key
    AWS_REGION_1                Primary region (default: us-east-1)

    AWS_ACCESS_KEY_ID_2         Secondary AWS access key
    AWS_SECRET_ACCESS_KEY_2     Secondary AWS secret key
    AWS_REGION_2                Secondary region

    AWS_ACCESS_KEY_ID_3         Tertiary AWS access key
    AWS_SECRET_ACCESS_KEY_3     Tertiary AWS secret key
    AWS_REGION_3                Tertiary region

    KUBECONFIG                  Path to kubeconfig file (for ACM integration)

Configuration:
    Edit inventory/group_vars/all.yml to configure:
    - acme_email: Email for Let's Encrypt registration (REQUIRED)
    - acme_server: Use staging or production Let's Encrypt server
    - certmanager_channel: Operator channel (default: stable-v1)

Authentication:
    Set up to 3 AWS credential sets as environment variables.
    Each cluster specifies which credential set to use via aws_credential_set.

EOF
}

# Main command processing
case "${1:-}" in
    build)
        build_image
        ;;

    generate-configs)
        build_image
        shift
        run_ansible "generate-configs.yml" "$@"
        ;;

    deploy)
        build_image
        shift
        run_ansible "deploy-clusters.yml" "$@"
        ;;

    destroy)
        build_image
        shift
        # Check for --yes flag and filter it out from args
        filtered_args=()
        extra_args=""
        for arg in "$@"; do
            if [ "$arg" = "--yes" ] || [ "$arg" = "-y" ]; then
                extra_args="-e force_destroy=true"
            else
                filtered_args+=("$arg")
            fi
        done
        run_ansible "destroy-clusters.yml" $extra_args "${filtered_args[@]}"
        ;;

    operators)
        build_image
        shift
        # Check for --destroy flag and switch playbook
        filtered_args=()
        playbook="setup-operators.yml"
        for arg in "$@"; do
            if [ "$arg" = "--destroy" ]; then
                playbook="destroy-operators.yml"
            else
                filtered_args+=("$arg")
            fi
        done
        run_ansible "$playbook" "${filtered_args[@]}"
        ;;

    import)
        build_image
        shift
        # Check for --destroy flag and switch playbook
        filtered_args=()
        playbook="import-clusters.yml"
        for arg in "$@"; do
            if [ "$arg" = "--destroy" ]; then
                playbook="detach-clusters.yml"
            else
                filtered_args+=("$arg")
            fi
        done
        run_ansible "$playbook" "${filtered_args[@]}"
        ;;

    infra-dr)
        build_image
        shift
        # Check for --destroy flag and switch playbook
        filtered_args=()
        playbook="infra-dr.yml"
        for arg in "$@"; do
            if [ "$arg" = "--destroy" ]; then
                playbook="destroy-infra-dr.yml"
            else
                filtered_args+=("$arg")
            fi
        done
        run_ansible "$playbook" "${filtered_args[@]}"
        ;;

    app)
        build_image
        shift
        # Check for --destroy flag and switch playbook
        filtered_args=()
        playbook="deploy-app.yml"
        for arg in "$@"; do
            if [ "$arg" = "--destroy" ]; then
                playbook="destroy-app.yml"
            else
                filtered_args+=("$arg")
            fi
        done
        run_ansible "$playbook" "${filtered_args[@]}"
        ;;

    certs)
        build_image
        shift
        # Check for --destroy flag and switch playbook
        filtered_args=()
        playbook="setup-certs.yml"
        for arg in "$@"; do
            if [ "$arg" = "--destroy" ]; then
                playbook="destroy-certs.yml"
            else
                filtered_args+=("$arg")
            fi
        done
        run_ansible "$playbook" "${filtered_args[@]}"
        ;;

    netobserv)
        build_image
        shift
        # Check for --destroy flag and switch playbook
        filtered_args=()
        playbook="setup-netobserv.yml"
        for arg in "$@"; do
            if [ "$arg" = "--destroy" ]; then
                playbook="destroy-netobserv.yml"
            else
                filtered_args+=("$arg")
            fi
        done
        run_ansible "$playbook" "${filtered_args[@]}"
        ;;

    acs)
        build_image
        shift
        # Check for --destroy flag and switch playbook
        filtered_args=()
        playbook="setup-acs.yml"
        for arg in "$@"; do
            if [ "$arg" = "--destroy" ]; then
                playbook="destroy-acs.yml"
            else
                filtered_args+=("$arg")
            fi
        done
        run_ansible "$playbook" "${filtered_args[@]}"
        ;;

    virt)
        build_image
        shift
        # Check for --destroy flag and switch playbook
        filtered_args=()
        playbook="setup-virt.yml"
        for arg in "$@"; do
            if [ "$arg" = "--destroy" ]; then
                playbook="destroy-virt.yml"
            else
                filtered_args+=("$arg")
            fi
        done
        run_ansible "$playbook" "${filtered_args[@]}"
        ;;

    validate)
        build_image
        shift
        run_ansible "validate.yml" "$@"
        ;;

    list)
        build_image
        shift
        run_ansible "list-clusters.yml" "$@"
        ;;

    run)
        if [ -z "$2" ]; then
            print_error "Please specify a playbook to run"
            usage
            exit 1
        fi
        build_image
        shift
        playbook="$1"
        shift
        run_ansible "$playbook" "$@"
        ;;

    shell)
        build_image
        print_info "Opening shell in Ansible container..."
        podman run --rm -it \
            -v "$SCRIPT_DIR:/workspace:Z" \
            --network host \
            --entrypoint /bin/bash \
            "$IMAGE_NAME"
        ;;

    -h|--help|help)
        usage
        ;;

    *)
        print_error "Unknown command: ${1:-}"
        echo ""
        usage
        exit 1
        ;;
esac
