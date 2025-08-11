# GitHub Actions CI/CD Setup

This directory contains GitHub Actions workflows for automated CI/CD pipeline for the retail store sample application.

## Workflows

### 1. CI/CD Pipeline (`ci-cd.yml`)
- **Trigger**: Push to `main`/`develop` branches or PR to `main` with changes in `src/` directory
- **Features**:
  - Detects changes in individual microservices
  - Builds and pushes Docker images to ECR only for changed services
  - Updates Helm chart values with new image tags
  - Includes security scanning with Trivy
  - Supports parallel builds for multiple services

### 2. Setup ECR Repositories (`setup-ecr.yml`)
- **Trigger**: Manual dispatch or push to main (when workflow file changes)
- **Purpose**: Creates ECR repositories for all microservices with proper configuration
- **Features**:
  - Creates repositories with image scanning enabled
  - Sets up lifecycle policies to keep only last 10 images
  - Idempotent - won't recreate existing repositories

### 3. Manual Deployment (`manual-deploy.yml`)
- **Trigger**: Manual dispatch with parameters
- **Purpose**: Deploy specific services to chosen environments
- **Parameters**:
  - Service: Choose individual service or "all"
  - Environment: development/staging/production
  - Image tag: Optional specific tag (defaults to latest)

## Setup Instructions

### 1. GitHub Secrets Configuration

Add the following secrets to your GitHub repository:

```
AWS_ACCESS_KEY_ID       # AWS Access Key ID with ECR and EKS permissions
AWS_SECRET_ACCESS_KEY   # AWS Secret Access Key
AWS_ACCOUNT_ID          # Your AWS Account ID (12-digit number)
```

### 2. AWS Permissions Required

The AWS credentials need the following permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:PutImage",
                "ecr:CreateRepository",
                "ecr:DescribeRepositories",
                "ecr:PutLifecyclePolicy"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters"
            ],
            "Resource": "*"
        }
    ]
}
```

### 3. Initial Setup Steps

1. **Create ECR Repositories**:
   - Go to Actions tab in GitHub
   - Run "Setup ECR Repositories" workflow manually
   - This will create all required ECR repositories

2. **Update Kubernetes Configuration**:
   - Edit the workflows to include your EKS cluster name
   - Replace `your-cluster-name` with your actual cluster name in:
     - `manual-deploy.yml` (line with `aws eks update-kubeconfig`)
     - `ci-cd.yml` (commented section for Kubernetes deployment)

3. **Customize Environment Variables**:
   - Update `AWS_REGION` in workflow files if using different region
   - Modify ECR registry URL format if needed

### 4. Workflow Behavior

#### Automatic CI/CD Flow:
1. Developer pushes changes to `src/` directory
2. Workflow detects which services changed
3. Builds Docker images only for changed services
4. Pushes images to ECR with commit SHA as tag
5. Updates Helm chart values.yaml with new image tags
6. Commits the updated Helm charts back to repository
7. Optionally deploys to Kubernetes (uncomment deployment section)

#### Manual Deployment Flow:
1. Go to Actions tab → Manual Deployment
2. Select service(s) and target environment
3. Optionally specify image tag
4. Workflow deploys using Helm to specified namespace

### 5. Customization Options

#### Enable Automatic Kubernetes Deployment:
Uncomment the deployment section in `ci-cd.yml`:
```yaml
- name: Deploy to Kubernetes (Optional)
  if: needs.detect-changes.outputs[matrix.service] == 'true' && github.event_name != 'pull_request' && github.ref == 'refs/heads/main'
  run: |
    # Install Helm if not already installed
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    # Add your Kubernetes cluster configuration here
    aws eks update-kubeconfig --region ${{ env.AWS_REGION }} --name your-cluster-name
    
    # Deploy using Helm
    helm upgrade --install retail-store-${{ matrix.service }} ./src/${{ matrix.service }}/chart \
      --namespace retail-store \
      --create-namespace \
      --set image.tag=${{ steps.image-tag.outputs.tag }}
```

#### Add Slack/Teams Notifications:
Add notification steps to the `notify` job in `ci-cd.yml`.

#### Add Additional Environments:
Modify the `manual-deploy.yml` to include more environment options.

### 6. Monitoring and Troubleshooting

- Check Actions tab for workflow execution logs
- ECR repositories will have image scanning results
- Use `kubectl` commands in manual deployment for verification
- Trivy security scan results appear in Security tab

### 7. Best Practices

- Use pull requests for code review before merging to main
- Monitor ECR repository sizes and costs
- Regularly review security scan results
- Test deployments in development environment first
- Use semantic versioning for production releases

## File Structure

```
.github/
└── workflows/
    ├── ci-cd.yml           # Main CI/CD pipeline
    ├── setup-ecr.yml       # ECR repository setup
    ├── manual-deploy.yml   # Manual deployment workflow
    └── README.md          # This documentation
```
