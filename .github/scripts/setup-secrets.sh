#!/bin/bash
# Secret Setup Guide for Daily Backup Workflow
# This script provides instructions for setting up the required GitHub Actions secrets

set -e

echo "========================================="
echo "GitHub Actions Secrets Setup Guide"
echo "========================================="
echo ""
echo "The following secrets need to be configured in the repository:"
echo ""
echo "Repository: phildass/repo-backup"
echo "Path: Settings → Secrets and variables → Actions → New repository secret"
echo ""
echo "========================================="
echo "Required Secrets:"
echo "========================================="
echo ""

cat << 'EOF'
1. BACKUP_GITHUB_TOKEN
   Description: Personal Access Token with 'repo' and 'read:org' scopes
   How to create:
   - Go to https://github.com/settings/tokens/new
   - Select scopes: repo (all), read:org
   - Generate token and copy it
   - DO NOT share this token or commit it to the repository
   
   Set via CLI:
   gh secret set BACKUP_GITHUB_TOKEN --repo phildass/repo-backup

2. AWS_ACCESS_KEY_ID
   Description: AWS IAM user access key ID
   How to create:
   - Go to AWS IAM Console → Users → [Your User] → Security credentials
   - Create access key
   - Copy the Access Key ID
   
   Set via CLI:
   gh secret set AWS_ACCESS_KEY_ID --repo phildass/repo-backup

3. AWS_SECRET_ACCESS_KEY
   Description: AWS IAM user secret access key
   How to create:
   - Created at the same time as AWS_ACCESS_KEY_ID
   - Copy the Secret Access Key (only shown once!)
   
   Set via CLI:
   gh secret set AWS_SECRET_ACCESS_KEY --repo phildass/repo-backup

4. AWS_REGION
   Description: AWS region where S3 bucket is located
   Example: us-east-1
   
   Set via CLI:
   gh secret set AWS_REGION --repo phildass/repo-backup --body "us-east-1"

5. S3_BUCKET
   Description: Name of the S3 bucket for storing backups
   Example: my-backup-bucket
   
   Set via CLI:
   gh secret set S3_BUCKET --repo phildass/repo-backup --body "your-backup-bucket-name"

EOF

echo ""
echo "========================================="
echo "Verification"
echo "========================================="
echo ""
echo "After setting all secrets, verify with:"
echo "  gh secret list --repo phildass/repo-backup"
echo ""
echo "You should see all 5 secrets listed."
echo ""

echo "========================================="
echo "Interactive Secret Setup"
echo "========================================="
echo ""

read -p "Would you like to set secrets interactively now? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Setting secrets interactively..."
    echo ""
    
    # Check if gh is authenticated
    if ! gh auth status >/dev/null 2>&1; then
        echo "ERROR: gh CLI is not authenticated."
        echo "Please run: gh auth login"
        exit 1
    fi
    
    echo "Enter BACKUP_GITHUB_TOKEN:"
    gh secret set BACKUP_GITHUB_TOKEN --repo phildass/repo-backup
    
    echo "Enter AWS_ACCESS_KEY_ID:"
    gh secret set AWS_ACCESS_KEY_ID --repo phildass/repo-backup
    
    echo "Enter AWS_SECRET_ACCESS_KEY:"
    gh secret set AWS_SECRET_ACCESS_KEY --repo phildass/repo-backup
    
    echo "Enter AWS_REGION (e.g., us-east-1):"
    read -r AWS_REGION
    gh secret set AWS_REGION --repo phildass/repo-backup --body "$AWS_REGION"
    
    echo "Enter S3_BUCKET name:"
    read -r S3_BUCKET
    gh secret set S3_BUCKET --repo phildass/repo-backup --body "$S3_BUCKET"
    
    echo ""
    echo "Secrets set successfully!"
    echo ""
    echo "Verifying..."
    gh secret list --repo phildass/repo-backup
else
    echo "Skipping interactive setup."
    echo "Please set secrets manually using the commands above."
fi

echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "1. Verify all secrets are set:"
echo "   gh secret list --repo phildass/repo-backup"
echo ""
echo "2. Test the workflow manually:"
echo "   gh workflow run daily-backup.yml --repo phildass/repo-backup --ref backup/workflow-setup"
echo ""
echo "3. Monitor the workflow run:"
echo "   gh run list --repo phildass/repo-backup --workflow=daily-backup.yml"
echo ""
echo "4. View run logs:"
echo "   gh run view --repo phildass/repo-backup --log"
echo ""
