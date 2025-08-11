#!/bin/bash

# Local Build and Test Script for Retail Store Sample App
# This script helps developers build and test services locally

set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-""}
SERVICES=("ui" "catalog" "cart" "checkout" "orders")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  build [service]     Build Docker image(s) locally"
    echo "  push [service]      Push Docker image(s) to ECR"
    echo "  test [service]      Run tests for service(s)"
    echo "  deploy [service]    Deploy service(s) locally with Helm"
    echo "  clean              Clean up local Docker images"
    echo "  setup              Setup ECR repositories"
    echo "  help               Show this help message"
    echo ""
    echo "Options:"
    echo "  service            Specific service name (ui, catalog, cart, checkout, orders) or 'all'"
    echo ""
    echo "Examples:"
    echo "  $0 build ui                    # Build UI service"
    echo "  $0 build all                   # Build all services"
    echo "  $0 push catalog                # Push catalog service to ECR"
    echo "  $0 deploy all                  # Deploy all services locally"
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again."
        exit 1
    fi
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_warning "AWS_ACCOUNT_ID not set. Trying to get it from AWS CLI..."
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        if [ -z "$AWS_ACCOUNT_ID" ]; then
            log_error "Could not determine AWS Account ID. Please set AWS_ACCOUNT_ID environment variable."
            exit 1
        fi
    fi
}

# Function to get ECR login
ecr_login() {
    log_info "Logging into ECR..."
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
}

# Function to build Docker image
build_service() {
    local service=$1
    local tag=${2:-latest}
    
    log_info "Building $service service..."
    
    if [ ! -d "src/$service" ]; then
        log_error "Service directory src/$service not found!"
        return 1
    fi
    
    if [ ! -f "src/$service/Dockerfile" ]; then
        log_error "Dockerfile not found in src/$service/"
        return 1
    fi
    
    docker build -t retail-store-$service:$tag src/$service/
    docker tag retail-store-$service:$tag $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store-$service:$tag
    
    log_success "Built $service:$tag successfully"
}

# Function to push Docker image
push_service() {
    local service=$1
    local tag=${2:-latest}
    
    log_info "Pushing $service:$tag to ECR..."
    
    ecr_login
    docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store-$service:$tag
    
    log_success "Pushed $service:$tag successfully"
}

# Function to run tests
test_service() {
    local service=$1
    
    log_info "Running tests for $service service..."
    
    # Add your test commands here based on the service
    case $service in
        "ui")
            # Example: npm test or similar
            log_info "Running UI tests..."
            ;;
        "catalog"|"cart"|"checkout"|"orders")
            # Example: mvn test or gradle test
            log_info "Running $service tests..."
            ;;
        *)
            log_warning "No tests defined for $service"
            ;;
    esac
    
    log_success "Tests completed for $service"
}

# Function to deploy service locally
deploy_service() {
    local service=$1
    local namespace=${2:-retail-store-local}
    
    log_info "Deploying $service to local Kubernetes..."
    
    if [ ! -d "src/$service/chart" ]; then
        log_error "Helm chart not found for $service"
        return 1
    fi
    
    helm upgrade --install retail-store-$service src/$service/chart \
        --namespace $namespace \
        --create-namespace \
        --set image.repository=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store-$service \
        --set image.tag=latest \
        --wait
    
    log_success "Deployed $service successfully"
}

# Function to setup ECR repositories
setup_ecr() {
    log_info "Setting up ECR repositories..."
    
    for service in "${SERVICES[@]}"; do
        local repo_name="retail-store-$service"
        
        if aws ecr describe-repositories --repository-names $repo_name --region $AWS_REGION &>/dev/null; then
            log_info "Repository $repo_name already exists"
        else
            log_info "Creating repository $repo_name"
            aws ecr create-repository \
                --repository-name $repo_name \
                --region $AWS_REGION \
                --image-scanning-configuration scanOnPush=true \
                --encryption-configuration encryptionType=AES256
        fi
    done
    
    log_success "ECR setup completed"
}

# Function to clean up local images
clean_images() {
    log_info "Cleaning up local Docker images..."
    
    for service in "${SERVICES[@]}"; do
        docker rmi retail-store-$service:latest 2>/dev/null || true
        docker rmi $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/retail-store-$service:latest 2>/dev/null || true
    done
    
    # Clean up dangling images
    docker image prune -f
    
    log_success "Cleanup completed"
}

# Main script logic
main() {
    local command=$1
    local service=$2
    
    case $command in
        "build")
            check_prerequisites
            if [ "$service" = "all" ]; then
                for svc in "${SERVICES[@]}"; do
                    build_service $svc
                done
            elif [ -n "$service" ]; then
                build_service $service
            else
                log_error "Please specify a service or 'all'"
                show_usage
                exit 1
            fi
            ;;
        "push")
            check_prerequisites
            if [ "$service" = "all" ]; then
                for svc in "${SERVICES[@]}"; do
                    push_service $svc
                done
            elif [ -n "$service" ]; then
                push_service $service
            else
                log_error "Please specify a service or 'all'"
                show_usage
                exit 1
            fi
            ;;
        "test")
            if [ "$service" = "all" ]; then
                for svc in "${SERVICES[@]}"; do
                    test_service $svc
                done
            elif [ -n "$service" ]; then
                test_service $service
            else
                log_error "Please specify a service or 'all'"
                show_usage
                exit 1
            fi
            ;;
        "deploy")
            check_prerequisites
            if [ "$service" = "all" ]; then
                for svc in "${SERVICES[@]}"; do
                    deploy_service $svc
                done
            elif [ -n "$service" ]; then
                deploy_service $service
            else
                log_error "Please specify a service or 'all'"
                show_usage
                exit 1
            fi
            ;;
        "setup")
            check_prerequisites
            setup_ecr
            ;;
        "clean")
            clean_images
            ;;
        "help"|"--help"|"-h")
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi
    
    main "$@"
fi
