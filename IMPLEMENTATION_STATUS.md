# Backup Workflow Implementation Status

## Completed Tasks ✅

1. **Branch Created**: `backup/workflow-setup`
2. **Workflow File**: `.github/workflows/daily-backup.yml`
   - Scheduled to run daily at 00:00 UTC
   - Supports manual workflow dispatch
   - Installs required dependencies (git, jq, awscli)
   - Configured with all required environment variables

3. **Backup Script**: `.github/scripts/backup_repos.sh`
   - Mirror clones repositories with `git clone --mirror`
   - Exports issues and PRs as paginated JSON
   - Creates tar.gz archives (mirror + issues)
   - Uploads to S3 with organized path structure
   - Implements error handling and retry logic with exponential backoff
   - Comprehensive logging
   - Made executable

4. **Documentation**: Updated `README.md`
   - Complete setup instructions
   - Security warnings and best practices
   - Troubleshooting guide
   - Verification steps
   - IAM policy example

5. **Helper Script**: `.github/scripts/setup-secrets.sh`
   - Interactive secret setup guide
   - Documentation for each required secret

## Pending Tasks - Requires User Action ⚠️

### 1. GitHub Actions Secrets Setup

The following secrets must be manually configured as they require actual credentials:

```bash
# Required secrets (set in phildass/repo-backup → Settings → Secrets → Actions)

1. BACKUP_GITHUB_TOKEN - Personal Access Token with 'repo' and 'read:org' scopes
   gh secret set BACKUP_GITHUB_TOKEN --repo phildass/repo-backup

2. AWS_ACCESS_KEY_ID - AWS IAM access key
   gh secret set AWS_ACCESS_KEY_ID --repo phildass/repo-backup

3. AWS_SECRET_ACCESS_KEY - AWS IAM secret key
   gh secret set AWS_SECRET_ACCESS_KEY --repo phildass/repo-backup

4. AWS_REGION - AWS region (e.g., us-east-1)
   gh secret set AWS_REGION --repo phildass/repo-backup --body "us-east-1"

5. S3_BUCKET - S3 bucket name
   gh secret set S3_BUCKET --repo phildass/repo-backup --body "your-backup-bucket-name"
```

**Why Manual Setup Required:**
- Real AWS credentials (Access Key ID and Secret) are not available in the CI environment
- GitHub Personal Access Token needs to be created by the repository owner
- These credentials cannot be generated automatically for security reasons

### 2. AWS S3 Bucket Setup

If the S3 bucket doesn't exist, create it:

```bash
# Check if bucket exists
aws s3api head-bucket --bucket "your-backup-bucket-name" 2>/dev/null || \
  aws s3api create-bucket \
    --bucket "your-backup-bucket-name" \
    --region "us-east-1"

# Verify bucket is accessible
aws s3 ls s3://your-backup-bucket-name/ --region us-east-1
```

### 3. IAM Policy Configuration

Attach the following policy to the IAM user:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:AbortMultipartUpload"
      ],
      "Resource": [
        "arn:aws:s3:::your-backup-bucket-name",
        "arn:aws:s3:::your-backup-bucket-name/*"
      ]
    }
  ]
}
```

### 4. Testing the Workflow

Once secrets are configured:

```bash
# Trigger manual workflow run
gh workflow run daily-backup.yml --repo phildass/repo-backup --ref backup/workflow-setup

# Monitor the run
gh run list --repo phildass/repo-backup --workflow=daily-backup.yml --limit 5

# View logs
gh run view --repo phildass/repo-backup --log
```

### 5. Verification Steps

After a successful workflow run:

```bash
# List backups in S3
aws s3 ls s3://your-backup-bucket-name/backups/phildass/ --recursive --region us-east-1

# Download a sample backup
aws s3 cp s3://your-backup-bucket-name/backups/phildass/YYYY-MM-DD/repo-name-YYYY-MM-DD.tar.gz . --region us-east-1

# Verify archive contents
tar -tzf repo-name-YYYY-MM-DD.tar.gz | head -n 50
```

## Files Added

```
.github/
├── workflows/
│   └── daily-backup.yml          # GitHub Actions workflow
└── scripts/
    ├── backup_repos.sh            # Main backup script
    └── setup-secrets.sh           # Secret setup helper
README.md                          # Updated documentation
```

## Workflow Features

✅ Daily schedule (00:00 UTC) via cron
✅ Manual trigger support via workflow_dispatch
✅ Mirror clone all repositories for owner "phildass"
✅ Export issues and PRs as JSON with pagination
✅ Create compressed archives (tar.gz)
✅ Upload to S3 with date-organized structure
✅ Retry logic with exponential backoff for API rate limits
✅ Comprehensive error handling and logging
✅ Secure secret handling (no secrets in code)
✅ Continue on individual repo failures
✅ Stop on S3 upload failures

## Expected Workflow Output

When run successfully, the workflow will:

1. Enumerate all repositories for owner "phildass"
2. Log the total count and first few repository names
3. For each repository:
   - Clone the mirror
   - Export issues/PRs
   - Create archive
   - Upload to S3
   - Clean up local files
4. Provide summary with success/failure counts
5. List S3 path for uploaded backups

Example S3 path:
```
s3://your-backup-bucket-name/backups/phildass/2026-02-02/repo-backup-2026-02-02.tar.gz
```

## Security Notes

⚠️ **CRITICAL SECURITY WARNINGS:**
- Never commit secrets to the repository
- Use GitHub Actions Secrets for all credentials
- Rotate BACKUP_GITHUB_TOKEN and AWS keys regularly
- Limit IAM policy to only the backup bucket
- Keep this repository private
- Review access logs regularly

## Next Steps

1. **Set up secrets** using the commands in section "Pending Tasks"
2. **Create/verify S3 bucket** with appropriate permissions
3. **Run workflow manually** to test the setup
4. **Verify backups** are uploaded to S3
5. **Review and merge** this PR to main branch
6. **Monitor** the daily scheduled runs

## Support

For issues or questions:
- Review the comprehensive README.md
- Check GitHub Actions run logs
- Review troubleshooting section in README
- Verify all secrets are configured correctly
