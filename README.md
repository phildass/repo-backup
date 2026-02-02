# repo-backup

Automated daily backups of all GitHub repositories for owner `phildass` to AWS S3.

## Overview

This repository contains a GitHub Actions workflow that automatically backs up all repositories for a specified GitHub owner. The workflow:

- Runs daily at 00:00 UTC (or can be triggered manually)
- Mirror-clones each repository using `git clone --mirror`
- Exports issues and pull requests as JSON
- Creates compressed tar.gz archives containing both the repository and issues
- Uploads archives to AWS S3 with organized folder structure

## Files

- `.github/workflows/daily-backup.yml` - GitHub Actions workflow definition
- `.github/scripts/backup_repos.sh` - Bash script that performs the backup operations

## Required Secrets

The following secrets must be configured in the repository settings (Settings → Secrets → Actions):

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `BACKUP_GITHUB_TOKEN` | Personal Access Token with `repo` and `read:org` scopes | `ghp_xxxxxxxxxxxx` |
| `AWS_ACCESS_KEY_ID` | AWS IAM access key ID | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM secret access key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_REGION` | AWS region for S3 bucket | `us-east-1` |
| `S3_BUCKET` | Name of the S3 bucket for backups | `my-backup-bucket` |

### Setting Secrets via GitHub CLI

```bash
gh secret set BACKUP_GITHUB_TOKEN --repo phildass/repo-backup
gh secret set AWS_ACCESS_KEY_ID --repo phildass/repo-backup
gh secret set AWS_SECRET_ACCESS_KEY --repo phildass/repo-backup
gh secret set AWS_REGION --repo phildass/repo-backup --body "us-east-1"
gh secret set S3_BUCKET --repo phildass/repo-backup --body "your-backup-bucket-name"
```

## AWS IAM Policy

The AWS IAM user must have the following permissions for the S3 bucket:

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

## S3 Backup Structure

Backups are organized in S3 with the following structure:

```
s3://your-backup-bucket-name/backups/phildass/YYYY-MM-DD/repo-name-YYYY-MM-DD.tar.gz
```

Each archive contains:
- `repo-name.git/` - Mirror clone of the repository
- `repo-name-issues.json` - All issues and pull requests in JSON format

## Running the Workflow

### Manual Trigger

1. Go to Actions tab in GitHub
2. Select "Daily Repository Backup" workflow
3. Click "Run workflow"
4. Select the branch (e.g., `backup/workflow-setup` or `main`)
5. Click "Run workflow"

Or use GitHub CLI:

```bash
gh workflow run daily-backup.yml --repo phildass/repo-backup --ref main
```

### Scheduled Runs

The workflow runs automatically every day at 00:00 UTC via the cron schedule.

## Testing and Verification

### Verify Backup Completion

1. Check the GitHub Actions run log for success status
2. Look for log entries showing:
   - Number of repositories enumerated
   - Successful clones for each repository
   - Archive creation confirmations
   - S3 upload confirmations

### List Backups in S3

```bash
aws s3 ls s3://your-backup-bucket-name/backups/phildass/ --recursive --region us-east-1
```

### Download and Verify an Archive

```bash
# Download a backup
aws s3 cp s3://your-backup-bucket-name/backups/phildass/2026-02-02/repo-name-2026-02-02.tar.gz . --region us-east-1

# Extract and view contents
tar -tzf repo-name-2026-02-02.tar.gz | head -n 50

# Extract the archive
tar -xzf repo-name-2026-02-02.tar.gz

# Verify the mirror repository
ls -la repo-name.git/

# View issues data
jq . repo-name-issues.json | head -n 50
```

## Security Considerations

⚠️ **IMPORTANT SECURITY WARNINGS:**

- **Never commit secrets to the repository** - Always use GitHub Actions Secrets
- **Rotate credentials regularly** - The `BACKUP_GITHUB_TOKEN` and AWS keys should be rotated periodically
- **Limit AWS IAM permissions** - Use the minimal IAM policy shown above, scoped only to the backup bucket
- **Keep this repository private** - Contains sensitive backup workflows
- **Review access logs** - Regularly review S3 access logs and GitHub Actions logs

### Rotating Credentials

If credentials need to be rotated:

1. Generate new GitHub PAT or AWS access keys
2. Update the secrets in repository settings
3. Test with a manual workflow run
4. Revoke the old credentials

## Backup Retention

Configure S3 lifecycle rules to manage backup retention:

```bash
# Example: Delete backups older than 90 days
aws s3api put-bucket-lifecycle-configuration \
  --bucket your-backup-bucket-name \
  --lifecycle-configuration file://lifecycle-policy.json
```

Example lifecycle policy (`lifecycle-policy.json`):

```json
{
  "Rules": [
    {
      "Id": "DeleteOldBackups",
      "Status": "Enabled",
      "Prefix": "backups/",
      "Expiration": {
        "Days": 90
      }
    }
  ]
}
```

## Troubleshooting

### Workflow Fails to Enumerate Repositories

- Check that `BACKUP_GITHUB_TOKEN` has `repo` and `read:org` scopes
- Verify the token hasn't expired
- Check rate limits in GitHub API

### Clone Failures

- Verify PAT has access to all repositories (including private ones)
- Check for network connectivity issues
- Review repository permissions

### S3 Upload Failures

- Verify AWS credentials are correct and not expired
- Check IAM policy allows `s3:PutObject` on the bucket
- Verify bucket exists and region is correct
- Check S3 bucket permissions and CORS settings

### Rate Limiting

The script includes automatic retry with exponential backoff for GitHub API rate limits. If you hit limits frequently:

- Use a token with higher rate limits
- Reduce backup frequency
- Contact GitHub support for rate limit increases

## Disabling Backups

To disable automatic backups:

1. Rename or delete `.github/workflows/daily-backup.yml`
2. Or disable the workflow in repository settings (Actions → Workflows → Daily Repository Backup → Disable)

## License

This backup solution is provided as-is for use with the phildass organization repositories.
