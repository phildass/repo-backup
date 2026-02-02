# Pull Request: Daily Repository Backup Workflow

## 📋 Summary

This PR adds automated daily backups for all repositories owned by `phildass` to AWS S3.

## 🎯 Purpose

Implement a GitHub Actions workflow that:
- Runs daily at 00:00 UTC (also supports manual triggers)
- Mirror-clones all repositories for the owner
- Exports issues and pull requests as JSON
- Creates compressed archives containing repository data and issues
- Uploads backups to AWS S3 with organized folder structure

## 📁 Files Added

### Workflow
- `.github/workflows/daily-backup.yml` - GitHub Actions workflow definition

### Scripts  
- `.github/scripts/backup_repos.sh` - Main backup script with error handling and retry logic
- `.github/scripts/setup-secrets.sh` - Interactive helper for setting up required secrets

### Documentation
- `README.md` - Comprehensive guide (updated)
- `IMPLEMENTATION_STATUS.md` - Implementation status and setup instructions

## ✅ Features Implemented

- [x] Daily scheduled backup at 00:00 UTC via cron
- [x] Manual workflow dispatch support
- [x] Mirror clone of all repositories
- [x] Issues and PRs export with pagination
- [x] Compressed tar.gz archives
- [x] S3 upload with date-organized paths
- [x] GitHub API retry logic with exponential backoff
- [x] Comprehensive error handling and logging
- [x] Secure secret management
- [x] Continue on individual repo failures
- [x] Stop immediately on S3 upload failures
- [x] Detailed documentation and setup guides

## 🔐 Required Secrets

The following GitHub Actions secrets must be configured before running the workflow:

| Secret | Description | Required |
|--------|-------------|----------|
| `BACKUP_GITHUB_TOKEN` | GitHub PAT with `repo` and `read:org` scopes | ✅ Yes |
| `AWS_ACCESS_KEY_ID` | AWS IAM access key ID | ✅ Yes |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM secret access key | ✅ Yes |
| `AWS_REGION` | AWS region (e.g., `us-east-1`) | ✅ Yes |
| `S3_BUCKET` | S3 bucket name for backups | ✅ Yes |

### Setting Secrets

```bash
gh secret set BACKUP_GITHUB_TOKEN --repo phildass/repo-backup
gh secret set AWS_ACCESS_KEY_ID --repo phildass/repo-backup
gh secret set AWS_SECRET_ACCESS_KEY --repo phildass/repo-backup
gh secret set AWS_REGION --repo phildass/repo-backup --body "us-east-1"
gh secret set S3_BUCKET --repo phildass/repo-backup --body "your-backup-bucket-name"
```

Or use the interactive helper:
```bash
.github/scripts/setup-secrets.sh
```

## 🔒 AWS IAM Policy

The IAM user needs the following permissions:

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

## 📍 Backup Location

Backups are stored in S3 with the following structure:

```
s3://[S3_BUCKET]/backups/phildass/YYYY-MM-DD/repo-name-YYYY-MM-DD.tar.gz
```

Each archive contains:
- `repo-name.git/` - Complete mirror clone
- `repo-name-issues.json` - All issues and PRs

## 🧪 Testing Checklist

Before merging, verify:

- [ ] All 5 secrets are configured in repository settings
- [ ] S3 bucket exists and is accessible
- [ ] IAM user has correct permissions
- [ ] Manual workflow run completes successfully
- [ ] At least one archive uploaded to S3
- [ ] Downloaded archive contains valid git mirror and issues JSON
- [ ] Workflow logs show correct repo enumeration
- [ ] No secrets exposed in logs

### Manual Test Run

```bash
# Trigger workflow
gh workflow run daily-backup.yml --repo phildass/repo-backup --ref backup/workflow-setup

# Monitor run
gh run list --repo phildass/repo-backup --workflow=daily-backup.yml --limit 1

# View logs
gh run view --repo phildass/repo-backup --log

# Verify S3 uploads
aws s3 ls s3://your-backup-bucket-name/backups/phildass/ --recursive --region us-east-1

# Download and verify a sample
aws s3 cp s3://your-backup-bucket-name/backups/phildass/YYYY-MM-DD/repo-name-YYYY-MM-DD.tar.gz .
tar -tzf repo-name-YYYY-MM-DD.tar.gz
```

## 🔍 Verification Steps

After testing:

1. **Check Workflow Logs**: Verify repository enumeration, clones, and uploads succeeded
2. **List S3 Backups**: Confirm archives are in the expected S3 path
3. **Download Sample**: Download one archive and verify contents
4. **Extract Archive**: Ensure git mirror and issues JSON are valid
5. **Review Logs**: No errors or security warnings

## ⚠️ Security Warnings

**CRITICAL - READ BEFORE MERGING:**

- ❌ **Never commit secrets** - Always use GitHub Actions Secrets
- 🔄 **Rotate credentials regularly** - Especially if they're temporary or shared
- 🔒 **Limit IAM permissions** - Use minimal policy scoped to backup bucket only
- 🔐 **Keep repo private** - Contains sensitive backup workflows
- 📊 **Review access logs** - Regularly audit S3 and GitHub Actions logs
- ⏰ **Set retention policy** - Configure S3 lifecycle rules (recommended: 90 days)

### Credential Rotation

If credentials need rotation:
1. Generate new credentials (PAT or AWS keys)
2. Update secrets in repository settings
3. Test with manual workflow run
4. Revoke old credentials

## 🚀 Post-Merge Actions

1. Verify scheduled workflow runs daily at 00:00 UTC
2. Set up S3 lifecycle rules for automatic retention management
3. Configure CloudWatch or S3 notifications for backup monitoring
4. Document backup restoration procedures
5. Schedule periodic test restores to verify backup integrity

## 📚 Documentation

See `README.md` for:
- Complete setup instructions
- Troubleshooting guide
- Security best practices
- Backup verification steps
- How to disable backups

See `IMPLEMENTATION_STATUS.md` for:
- Current implementation status
- Pending manual steps
- Expected workflow output
- Support information

## 🐛 Error Handling

The workflow includes:
- ✅ Retry logic for GitHub API rate limits (3 attempts with exponential backoff)
- ✅ Continue on individual repository clone failures
- ✅ Stop on S3 upload failures (critical error)
- ✅ Detailed logging for troubleshooting
- ✅ Summary report with success/failure counts

## 📊 Expected Output

Successful workflow run will log:
```
Total repositories: N
Successful backups: N
Failed backups: 0
S3 Path: s3://bucket/backups/phildass/2026-02-02/
```

## 🔄 Rollback Instructions

To disable backups:
1. Rename or delete `.github/workflows/daily-backup.yml`
2. Or disable workflow in Actions settings

To rollback changes:
```bash
git revert <commit-sha>
```

## 👤 Assignee

@phildass

## 🏷️ Labels

- enhancement
- automation
- infrastructure
- security

---

**Ready for Review**: This PR is ready for review and testing once all required secrets are configured.

**Merge After**: Successful manual workflow run with verified S3 uploads.
