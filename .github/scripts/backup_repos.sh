#!/bin/bash
set -e  # Exit on error
set -o pipefail  # Exit on pipe failures

# Script: backup_repos.sh
# Purpose: Mirror-clone all repositories for a GitHub owner, export issues/PRs, and upload to S3

# ========================================
# Configuration and Environment Variables
# ========================================

OWNER="${OWNER:-phildass}"
BACKUP_TO_ORG_REPOS="${BACKUP_TO_ORG_REPOS:-false}"
S3_BUCKET="${S3_BUCKET}"
S3_PREFIX="${S3_PREFIX:-backups}"
KEEP_ISSUES="${KEEP_ISSUES:-true}"
USE_GITHUB_PAT="${USE_GITHUB_PAT:-true}"
BACKUP_GITHUB_TOKEN="${BACKUP_GITHUB_TOKEN}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Date for backup folder structure
DATE=$(date -u +%Y-%m-%d)
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)

# Working directory
WORK_DIR="/tmp/backup-${TIMESTAMP}"
mkdir -p "${WORK_DIR}"

# ========================================
# Logging Functions
# ========================================

log() {
    echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] $*"
}

log_error() {
    echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] ERROR: $*" >&2
}

log_success() {
    echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] SUCCESS: $*"
}

# ========================================
# Validate Required Environment Variables
# ========================================

validate_environment() {
    log "Validating environment variables..."
    
    local missing_vars=()
    
    if [[ -z "${OWNER}" ]]; then
        missing_vars+=("OWNER")
    fi
    
    if [[ -z "${S3_BUCKET}" ]]; then
        missing_vars+=("S3_BUCKET")
    fi
    
    if [[ "${USE_GITHUB_PAT}" == "true" ]] && [[ -z "${BACKUP_GITHUB_TOKEN}" ]]; then
        missing_vars+=("BACKUP_GITHUB_TOKEN")
    fi
    
    if [[ -z "${AWS_ACCESS_KEY_ID}" ]]; then
        missing_vars+=("AWS_ACCESS_KEY_ID")
    fi
    
    if [[ -z "${AWS_SECRET_ACCESS_KEY}" ]]; then
        missing_vars+=("AWS_SECRET_ACCESS_KEY")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        exit 1
    fi
    
    log_success "Environment validation passed"
}

# ========================================
# GitHub API Functions with Retry Logic
# ========================================

github_api_call() {
    local url="$1"
    local max_attempts=3
    local attempt=1
    local backoff=5
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        log "API call attempt ${attempt}/${max_attempts}: ${url}"
        
        local response
        local http_code
        
        if [[ "${USE_GITHUB_PAT}" == "true" ]]; then
            response=$(curl -s -w "\n%{http_code}" -H "Authorization: token ${BACKUP_GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" "${url}")
        else
            response=$(curl -s -w "\n%{http_code}" -H "Accept: application/vnd.github.v3+json" "${url}")
        fi
        
        http_code=$(echo "${response}" | tail -n 1)
        body=$(echo "${response}" | sed '$d')
        
        if [[ "${http_code}" == "200" ]]; then
            echo "${body}"
            return 0
        elif [[ "${http_code}" == "403" ]]; then
            log_error "Rate limited or forbidden (HTTP ${http_code}). Attempt ${attempt}/${max_attempts}"
            if [[ ${attempt} -lt ${max_attempts} ]]; then
                sleep $((backoff * attempt))
            fi
        else
            log_error "API call failed with HTTP ${http_code}"
            if [[ ${attempt} -lt ${max_attempts} ]]; then
                sleep ${backoff}
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "API call failed after ${max_attempts} attempts"
    return 1
}

# ========================================
# Enumerate Repositories
# ========================================

enumerate_repositories() {
    log "Enumerating repositories for owner: ${OWNER}"
    
    local all_repos=()
    local page=1
    local per_page=100
    
    while true; do
        local api_url
        if [[ "${BACKUP_TO_ORG_REPOS}" == "true" ]]; then
            api_url="https://api.github.com/orgs/${OWNER}/repos?per_page=${per_page}&page=${page}"
        else
            api_url="https://api.github.com/users/${OWNER}/repos?per_page=${per_page}&page=${page}"
        fi
        
        local repos_json
        repos_json=$(github_api_call "${api_url}")
        
        if [[ -z "${repos_json}" ]] || [[ "${repos_json}" == "[]" ]]; then
            break
        fi
        
        local repo_names
        repo_names=$(echo "${repos_json}" | jq -r '.[].full_name')
        
        if [[ -z "${repo_names}" ]]; then
            break
        fi
        
        all_repos+=("${repo_names}")
        log "Found ${#all_repos[@]} repositories so far (page ${page})"
        
        page=$((page + 1))
    done
    
    if [[ ${#all_repos[@]} -eq 0 ]]; then
        log_error "No repositories found for owner: ${OWNER}"
        exit 1
    fi
    
    log_success "Total repositories found: ${#all_repos[@]}"
    echo "${all_repos[@]}"
}

# ========================================
# Mirror Clone Repository
# ========================================

mirror_clone_repo() {
    local repo_full_name="$1"
    local repo_name=$(basename "${repo_full_name}")
    local repo_dir="${WORK_DIR}/${repo_name}.git"
    
    log "Cloning repository: ${repo_full_name} (mirror)"
    
    local clone_url
    if [[ "${USE_GITHUB_PAT}" == "true" ]]; then
        clone_url="https://${BACKUP_GITHUB_TOKEN}@github.com/${repo_full_name}.git"
    else
        clone_url="https://github.com/${repo_full_name}.git"
    fi
    
    if git clone --mirror "${clone_url}" "${repo_dir}"; then
        log_success "Cloned ${repo_full_name}"
        echo "${repo_dir}"
        return 0
    else
        log_error "Failed to clone ${repo_full_name}"
        return 1
    fi
}

# ========================================
# Export Issues and Pull Requests
# ========================================

export_issues_and_prs() {
    local repo_full_name="$1"
    local output_file="$2"
    
    if [[ "${KEEP_ISSUES}" != "true" ]]; then
        log "Skipping issues/PRs export (KEEP_ISSUES=${KEEP_ISSUES})"
        echo "[]" > "${output_file}"
        return 0
    fi
    
    log "Exporting issues and PRs for: ${repo_full_name}"
    
    local all_issues=()
    local page=1
    local per_page=100
    
    while true; do
        local api_url="https://api.github.com/repos/${repo_full_name}/issues?state=all&per_page=${per_page}&page=${page}"
        
        local issues_json
        issues_json=$(github_api_call "${api_url}")
        
        if [[ -z "${issues_json}" ]] || [[ "${issues_json}" == "[]" ]]; then
            break
        fi
        
        all_issues+=("${issues_json}")
        log "Fetched issues page ${page}"
        
        page=$((page + 1))
    done
    
    if [[ ${#all_issues[@]} -eq 0 ]]; then
        echo "[]" > "${output_file}"
        log "No issues/PRs found for ${repo_full_name}"
    else
        # Combine all pages into a single JSON array
        echo "${all_issues[@]}" | jq -s 'add' > "${output_file}"
        local count=$(jq length "${output_file}")
        log_success "Exported ${count} issues/PRs to ${output_file}"
    fi
    
    return 0
}

# ========================================
# Create Archive
# ========================================

create_archive() {
    local repo_name="$1"
    local repo_dir="$2"
    local issues_file="$3"
    local archive_name="${repo_name}-${DATE}.tar.gz"
    local archive_path="${WORK_DIR}/${archive_name}"
    
    log "Creating archive: ${archive_name}"
    
    # Create archive with both mirror repo and issues file
    tar -czf "${archive_path}" -C "${WORK_DIR}" \
        "$(basename "${repo_dir}")" \
        "$(basename "${issues_file}")" 2>/dev/null || {
        # If issues file doesn't exist or is empty, just archive the repo
        tar -czf "${archive_path}" -C "${WORK_DIR}" "$(basename "${repo_dir}")"
    }
    
    if [[ -f "${archive_path}" ]]; then
        log_success "Created archive: ${archive_path} ($(du -h "${archive_path}" | cut -f1))"
        echo "${archive_path}"
        return 0
    else
        log_error "Failed to create archive for ${repo_name}"
        return 1
    fi
}

# ========================================
# Upload to S3
# ========================================

upload_to_s3() {
    local archive_path="$1"
    local repo_name="$2"
    local s3_path="s3://${S3_BUCKET}/${S3_PREFIX}/${OWNER}/${DATE}/$(basename "${archive_path}")"
    
    log "Uploading to S3: ${s3_path}"
    
    if aws s3 cp "${archive_path}" "${s3_path}" --region "${AWS_REGION}"; then
        log_success "Uploaded to ${s3_path}"
        echo "${s3_path}"
        return 0
    else
        log_error "Failed to upload ${archive_path} to S3"
        return 1
    fi
}

# ========================================
# Cleanup Local Files
# ========================================

cleanup_repo_files() {
    local repo_dir="$1"
    local issues_file="$2"
    local archive_path="$3"
    
    log "Cleaning up local files for repository"
    
    rm -rf "${repo_dir}"
    rm -f "${issues_file}"
    rm -f "${archive_path}"
}

# ========================================
# Process Single Repository
# ========================================

process_repository() {
    local repo_full_name="$1"
    local repo_name=$(basename "${repo_full_name}")
    
    log "========================================"
    log "Processing repository: ${repo_full_name}"
    log "========================================"
    
    # Mirror clone
    local repo_dir
    if ! repo_dir=$(mirror_clone_repo "${repo_full_name}"); then
        log_error "Skipping ${repo_full_name} due to clone failure"
        return 1
    fi
    
    # Export issues and PRs
    local issues_file="${WORK_DIR}/${repo_name}-issues.json"
    if ! export_issues_and_prs "${repo_full_name}" "${issues_file}"; then
        log_error "Failed to export issues for ${repo_full_name}, continuing anyway"
    fi
    
    # Create archive
    local archive_path
    if ! archive_path=$(create_archive "${repo_name}" "${repo_dir}" "${issues_file}"); then
        log_error "Skipping ${repo_full_name} due to archive creation failure"
        cleanup_repo_files "${repo_dir}" "${issues_file}" ""
        return 1
    fi
    
    # Upload to S3
    local s3_path
    if ! s3_path=$(upload_to_s3 "${archive_path}" "${repo_name}"); then
        log_error "Failed to upload ${repo_full_name} to S3 - STOPPING"
        cleanup_repo_files "${repo_dir}" "${issues_file}" "${archive_path}"
        exit 1
    fi
    
    # Cleanup
    cleanup_repo_files "${repo_dir}" "${issues_file}" "${archive_path}"
    
    log_success "Completed backup for ${repo_full_name}"
    return 0
}

# ========================================
# Main Execution
# ========================================

main() {
    log "========================================"
    log "Starting GitHub Repository Backup"
    log "========================================"
    log "Owner: ${OWNER}"
    log "S3 Bucket: ${S3_BUCKET}"
    log "S3 Prefix: ${S3_PREFIX}"
    log "Date: ${DATE}"
    log "Keep Issues: ${KEEP_ISSUES}"
    log "========================================"
    
    # Validate environment
    validate_environment
    
    # Enumerate repositories
    local repos
    repos=($(enumerate_repositories))
    
    log "========================================"
    log "Starting backup of ${#repos[@]} repositories"
    log "First few repositories:"
    for i in "${!repos[@]}"; do
        if [[ ${i} -lt 5 ]]; then
            log "  - ${repos[${i}]}"
        fi
    done
    log "========================================"
    
    # Process each repository
    local success_count=0
    local failure_count=0
    local failed_repos=()
    
    for repo in "${repos[@]}"; do
        if process_repository "${repo}"; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
            failed_repos+=("${repo}")
        fi
    done
    
    # Summary
    log "========================================"
    log "Backup Summary"
    log "========================================"
    log "Total repositories: ${#repos[@]}"
    log "Successful backups: ${success_count}"
    log "Failed backups: ${failure_count}"
    
    if [[ ${failure_count} -gt 0 ]]; then
        log "Failed repositories:"
        for failed_repo in "${failed_repos[@]}"; do
            log "  - ${failed_repo}"
        done
    fi
    
    log "S3 Path: s3://${S3_BUCKET}/${S3_PREFIX}/${OWNER}/${DATE}/"
    log "========================================"
    
    # Cleanup work directory
    rm -rf "${WORK_DIR}"
    
    if [[ ${failure_count} -gt 0 ]]; then
        log_error "Backup completed with ${failure_count} failures"
        exit 0  # Don't fail the entire job for individual repo failures
    else
        log_success "Backup completed successfully for all repositories"
    fi
}

# Execute main function
main
