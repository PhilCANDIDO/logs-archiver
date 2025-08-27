#!/usr/bin/env bash

#############################################################################
# Script Name: logs-archiver.sh
# Version: 1.4.2
# Author: System Administrator
# Support: admin@example.com
# Description: Archive and compress log files from source to destination
# Date: 2025-08-27
#############################################################################

# Changelog:
# v1.4.2 - Fixed destination path to preserve full source path structure
# v1.4.1 - Fixed cron generation to exclude --log-path for proper log rotation
# v1.4.0 - Added --cron-schedule for automatic scheduling (hourly/daily/weekly)
# v1.3.1 - Fixed trailing slash issue in paths that prevented file matching
# v1.3.0 - Added --dry-run mode to simulate operations without making changes
# v1.2.0 - Fixed retention logic: retention=1 now correctly archives yesterday's files
# v1.1.0 - Added log retention feature to clean up old script logs
# v1.0.0 - Initial version with compression and retention management

set -euo pipefail

# Default values
RETENTION_DAYS=5
LOG_RETENTION_DAYS=5
VERBOSE=false
NO_LOG=false
DRY_RUN=false
COMPRESS_LEVEL=9
LOG_PATH=""
CRON_SCHEDULE=""
START_TIME=$(date +%s)

# Variables to track statistics
FILES_PROCESSED=0
FILES_FAILED=0
TOTAL_SIZE_BEFORE=0
TOTAL_SIZE_AFTER=0

# Colors for output (only if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# Function to display help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Archive and compress log files from source to destination with retention management.

OPTIONS:
    -h, --help              Display this help message
    --no-log               Display only standard output (no log file)
    --verbose              Enable verbose output
    --dry-run              Simulate operations without making changes
    --src-path PATH        Source root path of log files (REQUIRED)
    --src-pattern PATTERN  Pattern with {YYYY}, {MM}, {DD} placeholders (REQUIRED)
    --dst-path PATH        Destination path for archives (REQUIRED)
    --retention DAYS       Days to keep logs in source (default: 5)
                          0 = archive all files
                          1 = archive files from yesterday and older
                          N = archive files older than N-1 days
    --log-path PATH        Log file location (default: script directory)
    --log-retention DAYS   Days to keep script log files (default: 5)
    --compress-level N     Compression level 1-9 (default: 9)
    --cron-schedule TYPE   Create/update cron job (hourly, daily, weekly)
                          Creates cron file in /etc/cron.d/

EXAMPLE:
    $0 --src-path /var/syslog \\
       --src-pattern "{YYYY}/{MM}/{DD}/*.log" \\
       --dst-path /archives \\
       --retention 7 \\
       --verbose

PATTERN PLACEHOLDERS:
    {YYYY}  - 4-digit year
    {MM}    - 2-digit month
    {DD}    - 2-digit day

EOF
}

# Function to log messages
log_message() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Determine color based on level
    local color=""
    case "$level" in
        ERROR) color="$RED" ;;
        SUCCESS) color="$GREEN" ;;
        WARNING) color="$YELLOW" ;;
        *) color="" ;;
    esac
    
    # Output to console if not in no-log mode or if it's an error
    if [[ "$NO_LOG" == "false" ]] || [[ "$level" == "ERROR" ]]; then
        if [[ "$VERBOSE" == "true" ]] || [[ "$level" != "DEBUG" ]]; then
            echo -e "${color}[$timestamp] [$level] $message${NC}" >&2
        fi
    fi
    
    # Write to log file if configured
    if [[ -n "$LOG_PATH" ]] && [[ "$NO_LOG" == "false" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_PATH"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    for tool in find bzip2 date; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_message ERROR "Missing required tools: ${missing_tools[*]}"
        log_message ERROR "Please install missing tools and try again"
        exit 1
    fi
    
    log_message DEBUG "All required tools are installed"
}

# Function to validate parameters
validate_parameters() {
    local errors=()
    
    if [[ -z "${SRC_PATH:-}" ]]; then
        errors+=("--src-path is required")
    elif [[ ! -d "$SRC_PATH" ]]; then
        errors+=("Source path does not exist: $SRC_PATH")
    fi
    
    if [[ -z "${SRC_PATTERN:-}" ]]; then
        errors+=("--src-pattern is required")
    fi
    
    if [[ -z "${DST_PATH:-}" ]]; then
        errors+=("--dst-path is required")
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        for error in "${errors[@]}"; do
            log_message ERROR "$error"
        done
        echo "Use --help for usage information"
        exit 1
    fi
    
    # Normalize paths - remove trailing slashes
    SRC_PATH="${SRC_PATH%/}"
    DST_PATH="${DST_PATH%/}"
    
    # Create destination if it doesn't exist
    if [[ ! -d "$DST_PATH" ]]; then
        log_message INFO "Creating destination directory: $DST_PATH"
        mkdir -p "$DST_PATH" || {
            log_message ERROR "Failed to create destination directory: $DST_PATH"
            exit 1
        }
    fi
}

# Function to convert pattern to find-compatible format
convert_pattern() {
    local pattern="$1"
    local days_ago="${2:-0}"
    
    # Calculate date for days_ago
    if [[ "$days_ago" -gt 0 ]]; then
        local date_str=$(date -d "$days_ago days ago" '+%Y %m %d')
    else
        local date_str=$(date '+%Y %m %d')
    fi
    read -r year month day <<< "$date_str"
    
    # Replace placeholders
    pattern="${pattern//\{YYYY\}/$year}"
    pattern="${pattern//\{MM\}/$month}"
    pattern="${pattern//\{DD\}/$day}"
    
    echo "$pattern"
}

# Function to get file size in bytes
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -c%s "$file" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# Function to archive a single file
archive_file() {
    local src_file="$1"
    local src_base="$SRC_PATH"
    
    # Preserve full source path structure in destination
    # Remove leading slash from src_base for proper path construction
    local src_path_clean="${src_base#/}"
    local rel_path="${src_file#$src_base/}"
    local dst_file="$DST_PATH/${src_path_clean}/$rel_path.bz2"
    local dst_dir=$(dirname "$dst_file")
    
    # Get source file size
    local size_before=$(get_file_size "$src_file")
    TOTAL_SIZE_BEFORE=$((TOTAL_SIZE_BEFORE + size_before))
    
    if [[ "$DRY_RUN" == "true" ]]; then
        # Dry run mode - just simulate
        log_message DEBUG "[DRY-RUN] Would compress: $src_file -> $dst_file"
        
        # Estimate compressed size (rough estimate: 10% of original for logs)
        local estimated_size_after=$((size_before / 10))
        TOTAL_SIZE_AFTER=$((TOTAL_SIZE_AFTER + estimated_size_after))
        
        local ratio=90  # Estimated compression ratio
        log_message SUCCESS "[DRY-RUN] Would archive: $rel_path (~${ratio}% compression)"
        FILES_PROCESSED=$((FILES_PROCESSED + 1))
        return 0
    fi
    
    # Create destination directory
    if ! mkdir -p "$dst_dir" 2>/dev/null; then
        log_message ERROR "Failed to create directory: $dst_dir"
        FILES_FAILED=$((FILES_FAILED + 1))
        return 1
    fi
    
    # Compress file
    local temp_file="${dst_file}.tmp"
    log_message DEBUG "Compressing: $src_file -> $dst_file"
    
    if bzip2 -${COMPRESS_LEVEL}c "$src_file" > "$temp_file" 2>/dev/null; then
        # Move temp file to final destination
        if mv "$temp_file" "$dst_file" 2>/dev/null; then
            local size_after=$(get_file_size "$dst_file")
            TOTAL_SIZE_AFTER=$((TOTAL_SIZE_AFTER + size_after))
            
            # Calculate compression ratio
            local ratio=0
            if [[ $size_before -gt 0 ]]; then
                ratio=$(( (size_before - size_after) * 100 / size_before ))
            fi
            
            log_message SUCCESS "Archived: $rel_path (${ratio}% compression)"
            FILES_PROCESSED=$((FILES_PROCESSED + 1))
            return 0
        else
            log_message ERROR "Failed to move compressed file: $dst_file"
            rm -f "$temp_file" 2>/dev/null
            FILES_FAILED=$((FILES_FAILED + 1))
            return 1
        fi
    else
        log_message ERROR "Failed to compress: $src_file"
        rm -f "$temp_file" 2>/dev/null
        FILES_FAILED=$((FILES_FAILED + 1))
        return 1
    fi
}

# Function to delete old source files
cleanup_old_files() {
    log_message INFO "Starting cleanup of files older than $RETENTION_DAYS days"
    
    local deleted_count=0
    local delete_failed=0
    
    # Determine mtime parameter for deletion (same logic as archiving)
    local mtime_param=""
    if [[ $RETENTION_DAYS -eq 0 ]]; then
        mtime_param=""
    elif [[ $RETENTION_DAYS -eq 1 ]]; then
        mtime_param="-mtime +0"
    else
        mtime_param="-mtime +$((RETENTION_DAYS - 1))"
    fi
    
    # Find and delete files older than retention period
    while IFS= read -r -d '' file; do
        # Only delete if the file was successfully archived
        local src_path_clean="${SRC_PATH#/}"
        local rel_path="${file#$SRC_PATH/}"
        local archived_file="$DST_PATH/${src_path_clean}/$rel_path.bz2"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            # Dry run mode - just simulate
            if [[ -f "$archived_file" ]] || [[ "$DRY_RUN" == "true" ]]; then
                log_message DEBUG "[DRY-RUN] Would delete: $file"
                deleted_count=$((deleted_count + 1))
            else
                log_message WARNING "[DRY-RUN] Would skip deletion (not archived): $file"
            fi
        elif [[ -f "$archived_file" ]]; then
            if rm "$file" 2>/dev/null; then
                log_message DEBUG "Deleted: $file"
                deleted_count=$((deleted_count + 1))
            else
                log_message WARNING "Failed to delete: $file"
                delete_failed=$((delete_failed + 1))
            fi
        else
            log_message WARNING "Skipping deletion (not archived): $file"
        fi
    done < <(find "$SRC_PATH" -type f -name "*.log" $mtime_param -print0 2>/dev/null)
    
    log_message INFO "Deleted $deleted_count files, $delete_failed failures"
    
    # Clean up empty directories
    cleanup_empty_directories
}

# Function to clean up empty directories
cleanup_empty_directories() {
    log_message INFO "Cleaning up empty directories"
    
    local dir_count=0
    
    if [[ "$DRY_RUN" == "true" ]]; then
        # Dry run mode - just count empty directories
        while IFS= read -r dir; do
            if [[ "$dir" != "$SRC_PATH" ]]; then  # Don't delete the source root
                dir_count=$((dir_count + 1))
                log_message DEBUG "[DRY-RUN] Would remove empty directory: $dir"
            fi
        done < <(find "$SRC_PATH" -depth -type d -empty -print 2>/dev/null)
        
        log_message INFO "[DRY-RUN] Would remove $dir_count empty directories"
    else
        # Find and delete empty directories (bottom-up)
        while IFS= read -r dir; do
            if [[ "$dir" != "$SRC_PATH" ]]; then  # Don't delete the source root
                dir_count=$((dir_count + 1))
                log_message DEBUG "Removed empty directory: $dir"
            fi
        done < <(find "$SRC_PATH" -depth -type d -empty -delete -print 2>/dev/null)
        
        log_message INFO "Removed $dir_count empty directories"
    fi
}

# Function to clean up old script log files
cleanup_old_logs() {
    if [[ "$NO_LOG" == "true" ]] || [[ -z "$LOG_PATH" ]]; then
        return  # No log cleanup needed if not logging
    fi
    
    local log_dir=$(dirname "$LOG_PATH")
    local log_basename="logs-archiver-*.log"
    local deleted_count=0
    
    log_message DEBUG "Cleaning up script logs older than $LOG_RETENTION_DAYS days from $log_dir"
    
    # Find and delete old log files
    while IFS= read -r old_log; do
        if [[ "$old_log" != "$LOG_PATH" ]]; then  # Don't delete the current log file
            if [[ "$DRY_RUN" == "true" ]]; then
                deleted_count=$((deleted_count + 1))
                log_message DEBUG "[DRY-RUN] Would delete old log: $(basename "$old_log")"
            elif rm "$old_log" 2>/dev/null; then
                deleted_count=$((deleted_count + 1))
                log_message DEBUG "Deleted old log: $(basename "$old_log")"
            fi
        fi
    done < <(find "$log_dir" -maxdepth 1 -name "$log_basename" -type f -mtime +${LOG_RETENTION_DAYS} -print 2>/dev/null)
    
    if [[ $deleted_count -gt 0 ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_message INFO "[DRY-RUN] Would delete $deleted_count old script log files"
        else
            log_message INFO "Deleted $deleted_count old script log files"
        fi
    fi
}

# Function to setup cron schedule
setup_cron() {
    if [[ -z "$CRON_SCHEDULE" ]]; then
        return  # No cron setup requested
    fi
    
    # Skip cron setup in dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message INFO "[DRY-RUN] Would create cron job: $CRON_SCHEDULE"
        return
    fi
    
    # Check if running as root (required for /etc/cron.d)
    if [[ $EUID -ne 0 ]]; then
        log_message ERROR "Cron setup requires root privileges. Run with sudo."
        exit 1
    fi
    
    # Get the absolute path of the script
    local script_path=$(readlink -f "${BASH_SOURCE[0]}")
    local script_dir=$(dirname "$script_path")
    local script_name=$(basename "$script_path")
    
    # Generate cron file name based on source path
    local cron_name="logs-archiver-$(echo "$SRC_PATH" | tr '/' '-' | sed 's/^-//' | sed 's/-$//')"
    local cron_file="/etc/cron.d/$cron_name"
    
    # Determine cron schedule pattern
    local cron_pattern=""
    case "$CRON_SCHEDULE" in
        hourly)
            cron_pattern="0 * * * *"  # Every hour at minute 0
            ;;
        daily)
            cron_pattern="0 2 * * *"   # Daily at 2:00 AM
            ;;
        weekly)
            cron_pattern="0 2 * * 0"   # Weekly on Sunday at 2:00 AM
            ;;
    esac
    
    # Build the command line with all parameters (except cron-schedule itself and dry-run)
    local cron_cmd="bash $script_path"
    cron_cmd="$cron_cmd --src-path \"$SRC_PATH\""
    cron_cmd="$cron_cmd --src-pattern \"$SRC_PATTERN\""
    cron_cmd="$cron_cmd --dst-path \"$DST_PATH\""
    cron_cmd="$cron_cmd --retention $RETENTION_DAYS"
    
    if [[ "$LOG_RETENTION_DAYS" != "5" ]]; then
        cron_cmd="$cron_cmd --log-retention $LOG_RETENTION_DAYS"
    fi
    
    if [[ "$COMPRESS_LEVEL" != "9" ]]; then
        cron_cmd="$cron_cmd --compress-level $COMPRESS_LEVEL"
    fi
    
    # Note: We don't include --log-path in cron to allow each execution to create its own log file
    
    # Create cron file
    log_message INFO "Creating cron job: $cron_file"
    cat > "$cron_file" << EOF
# Cron job for logs-archiver
# Generated: $(date)
# Schedule: $CRON_SCHEDULE
# Source: $SRC_PATH
# Pattern: $SRC_PATTERN
# Destination: $DST_PATH

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

$cron_pattern root $cron_cmd >> /var/log/logs-archiver-cron.log 2>&1
EOF
    
    # Set proper permissions for cron file
    chmod 644 "$cron_file"
    
    log_message SUCCESS "Cron job created: $cron_file ($CRON_SCHEDULE)"
    log_message INFO "Cron will run: $cron_pattern"
    
    # Reload cron service if systemctl is available
    if command -v systemctl &> /dev/null; then
        systemctl reload cron 2>/dev/null || systemctl reload crond 2>/dev/null || true
    fi
}

# Function to format bytes to human readable
format_bytes() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$(( bytes / 1024 ))KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$(( bytes / 1048576 ))MB"
    else
        echo "$(( bytes / 1073741824 ))GB"
    fi
}

# Function to print summary
print_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message INFO "========== DRY-RUN SUMMARY =========="
    else
        log_message INFO "========== Archive Summary =========="
    fi
    log_message INFO "Parameters:"
    log_message INFO "  Source Path: $SRC_PATH"
    log_message INFO "  Source Pattern: $SRC_PATTERN"
    log_message INFO "  Destination Path: $DST_PATH"
    log_message INFO "  Retention: $RETENTION_DAYS days"
    log_message INFO "  Log Retention: $LOG_RETENTION_DAYS days"
    log_message INFO "  Compression Level: $COMPRESS_LEVEL"
    log_message INFO ""
    log_message INFO "Results:"
    log_message INFO "  Files Processed: $FILES_PROCESSED"
    log_message INFO "  Files Failed: $FILES_FAILED"
    log_message INFO "  Total Size Before: $(format_bytes $TOTAL_SIZE_BEFORE)"
    log_message INFO "  Total Size After: $(format_bytes $TOTAL_SIZE_AFTER)"
    if [[ $TOTAL_SIZE_BEFORE -gt 0 ]]; then
        local compression_ratio=$(( (TOTAL_SIZE_BEFORE - TOTAL_SIZE_AFTER) * 100 / TOTAL_SIZE_BEFORE ))
        log_message INFO "  Compression Ratio: ${compression_ratio}%"
    fi
    log_message INFO "  Execution Time: ${duration} seconds"
    log_message INFO "====================================="
}

# Main function
main() {
    log_message INFO "Starting logs-archiver v1.4.2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message INFO "*** DRY-RUN MODE - No changes will be made ***"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Validate parameters
    validate_parameters
    
    log_message INFO "Processing files from: $SRC_PATH"
    log_message INFO "Pattern: $SRC_PATTERN"
    log_message INFO "Destination: $DST_PATH"
    
    # Process files to archive (older than retention days)
    local find_pattern="${SRC_PATTERN//\{YYYY\}/*}"
    find_pattern="${find_pattern//\{MM\}/*}"
    find_pattern="${find_pattern//\{DD\}/*}"
    
    # Build find command
    # Note: When RETENTION_DAYS=1, we want files from yesterday and older
    # So we use -mtime with the value directly (not +N)
    local mtime_param=""
    if [[ $RETENTION_DAYS -eq 0 ]]; then
        # Archive all files
        mtime_param=""
    elif [[ $RETENTION_DAYS -eq 1 ]]; then
        # Archive files from yesterday and older (≥1 day old)
        mtime_param="-mtime +0"
    else
        # Archive files older than N days
        mtime_param="-mtime +$((RETENTION_DAYS - 1))"
    fi
    
    local file_count=0
    while IFS= read -r -d '' file; do
        archive_file "$file"
        file_count=$((file_count + 1))
    done < <(find "$SRC_PATH" -type f -path "$SRC_PATH/$find_pattern" $mtime_param -print0 2>/dev/null)
    
    if [[ $file_count -eq 0 ]]; then
        log_message INFO "No files found older than $RETENTION_DAYS days"
    else
        log_message INFO "Processed $file_count files"
        
        # Cleanup old source files
        cleanup_old_files
    fi
    
    # Print summary
    print_summary
    
    # Clean up old script log files
    cleanup_old_logs
    
    # Setup cron schedule if requested
    setup_cron
    
    log_message INFO "Archive process completed"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --no-log)
            NO_LOG=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --src-path)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --src-path requires an argument"
                exit 1
            fi
            SRC_PATH="$2"
            shift 2
            ;;
        --src-pattern)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --src-pattern requires an argument"
                exit 1
            fi
            SRC_PATTERN="$2"
            shift 2
            ;;
        --dst-path)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --dst-path requires an argument"
                exit 1
            fi
            DST_PATH="$2"
            shift 2
            ;;
        --retention)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --retention requires an argument"
                exit 1
            fi
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --log-path)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --log-path requires an argument"
                exit 1
            fi
            LOG_PATH="$2"
            shift 2
            ;;
        --log-retention)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --log-retention requires an argument"
                exit 1
            fi
            LOG_RETENTION_DAYS="$2"
            shift 2
            ;;
        --compress-level)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --compress-level requires an argument"
                exit 1
            fi
            COMPRESS_LEVEL="$2"
            if [[ ! "$COMPRESS_LEVEL" =~ ^[1-9]$ ]]; then
                echo "Error: Compression level must be between 1 and 9"
                exit 1
            fi
            shift 2
            ;;
        --cron-schedule)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --cron-schedule requires an argument"
                exit 1
            fi
            CRON_SCHEDULE="$2"
            if [[ ! "$CRON_SCHEDULE" =~ ^(hourly|daily|weekly)$ ]]; then
                echo "Error: Cron schedule must be hourly, daily, or weekly"
                exit 1
            fi
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set default log path if not specified and not in no-log mode
if [[ -z "$LOG_PATH" ]] && [[ "$NO_LOG" == "false" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LOG_PATH="${SCRIPT_DIR}/logs-archiver-$(date +%Y%m%d-%H%M%S).log"
fi

# Run main function
main

exit 0