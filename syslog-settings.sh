#!/usr/bin/env bash

#############################################################################
# Script Name: syslog-settings.sh
# Version: 1.1.1
# Author: Philippe CANDIDO (philippe.candido@emerging-it.fr)
# Support: support@emerging-it.fr
# Description: Manage rsyslog configuration for remote device logging
# Date: 2025-08-27
#############################################################################

# Changelog:
# v1.1.1 - Fixed rsyslog template syntax error with newline character (use %LF%)
# v1.1.0 - Added support for catch-all template to capture unmatched messages
# v1.0.0 - Initial version with add, delete, and create actions

set -euo pipefail

# Default values
VERBOSE=false
NO_LOG=false
DRY_RUN=false
ACTION="add"
DEVICE_HOSTNAME=""
RSYSLOG_DIR="/etc/rsyslog.d"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output (only if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Function to display help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Manage rsyslog configuration files for remote device logging.

OPTIONS:
    -h, --help              Display this help message
    --no-log               Display only standard output
    --verbose              Enable verbose output  
    --dry-run              Simulate operations without making changes
    --syslog-file FILE     Rsyslog setting file to manage (REQUIRED)
    --template-name NAME   Template name in rsyslog file (REQUIRED)
    --dst-logs PATH        Destination path for logs (REQUIRED)
    --device-ip IP         IP address of the device (REQUIRED)
    --device-hostname NAME Hostname of device (default: device-ip value)
    --action ACTION        Action: add (default), delete, or create

ACTIONS:
    add     - Add a new device or modify existing rule
    delete  - Remove device rule from configuration
    create  - Create new rsyslog configuration file

EXAMPLES:
    # Add a new device
    $0 --syslog-file 20-firewalls.conf --template-name FirewallLogTemplate \\
       --dst-logs /var/syslog/firewalls --device-ip 10.0.1.1 \\
       --device-hostname firewall01

    # Delete a device
    $0 --syslog-file 20-firewalls.conf --template-name FirewallLogTemplate \\
       --dst-logs /var/syslog/firewalls --device-ip 10.0.1.1 --action delete

    # Create new configuration
    $0 --syslog-file 30-switches.conf --template-name SwitchLogTemplate \\
       --dst-logs /var/syslog/switches --device-ip 10.0.2.1 --action create

EOF
}

# Function to log messages
log_message() {
    local level=$1
    shift
    local message="$*"
    
    if [[ "$NO_LOG" == "true" ]] && [[ "$level" != "ERROR" ]]; then
        return
    fi
    
    # Determine color based on level
    local color=""
    case "$level" in
        ERROR) color="$RED" ;;
        SUCCESS) color="$GREEN" ;;
        WARNING) color="$YELLOW" ;;
        INFO) color="$BLUE" ;;
        *) color="" ;;
    esac
    
    # Output message
    if [[ "$VERBOSE" == "true" ]] || [[ "$level" != "DEBUG" ]]; then
        echo -e "${color}[$level] $message${NC}" >&2
    fi
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ ! $ip =~ $valid_ip_regex ]]; then
        return 1
    fi
    
    # Check each octet
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if (( octet > 255 )); then
            return 1
        fi
    done
    
    return 0
}

# Function to validate parameters
validate_parameters() {
    local errors=()
    
    # Check required parameters
    if [[ -z "${SYSLOG_FILE:-}" ]]; then
        errors+=("--syslog-file is required")
    fi
    
    if [[ -z "${TEMPLATE_NAME:-}" ]]; then
        errors+=("--template-name is required")
    fi
    
    if [[ -z "${DST_LOGS:-}" ]]; then
        errors+=("--dst-logs is required")
    fi
    
    if [[ -z "${DEVICE_IP:-}" ]]; then
        errors+=("--device-ip is required")
    else
        if ! validate_ip "$DEVICE_IP"; then
            errors+=("Invalid IP address: $DEVICE_IP")
        fi
    fi
    
    # Validate action
    if [[ ! "$ACTION" =~ ^(add|delete|create)$ ]]; then
        errors+=("Invalid action: $ACTION (must be add, delete, or create)")
    fi
    
    # Display errors and exit if any
    if [[ ${#errors[@]} -gt 0 ]]; then
        for error in "${errors[@]}"; do
            log_message ERROR "$error"
        done
        echo "Use --help for usage information"
        exit 1
    fi
    
    # Set default hostname if not provided
    if [[ -z "$DEVICE_HOSTNAME" ]]; then
        DEVICE_HOSTNAME="$DEVICE_IP"
    fi
    
    # Build full path for syslog file
    SYSLOG_FILE_PATH="$RSYSLOG_DIR/$SYSLOG_FILE"
}

# Function to backup file
backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d-%H%M%S)"
        if [[ "$DRY_RUN" == "true" ]]; then
            log_message INFO "[DRY-RUN] Would create backup: $backup"
        else
            cp "$file" "$backup"
            log_message INFO "Created backup: $backup"
        fi
    fi
}

# Function to load template
load_template() {
    local template_file=$1
    local content=""
    
    if [[ -f "$template_file" ]]; then
        content=$(<"$template_file")
    else
        log_message ERROR "Template file not found: $template_file"
        exit 1
    fi
    
    # Replace variables
    content="${content//\{\{TemplateName\}\}/$TEMPLATE_NAME}"
    content="${content//\{\{DstLogs\}\}/$DST_LOGS}"
    content="${content//\{\{DeviceIp\}\}/$DEVICE_IP}"
    content="${content//\{\{DeviceHostname\}\}/$DEVICE_HOSTNAME}"
    content="${content//\{\{ TemplateName \}\}/$TEMPLATE_NAME}"
    content="${content//\{\{ DstLogs \}\}/$DST_LOGS}"
    content="${content//\{\{ DeviceIp \}\}/$DEVICE_IP}"
    content="${content//\{\{ DeviceHostname \}\}/$DEVICE_HOSTNAME}"
    content="${content//\{\{ ScriptName \}\}/syslog-settings.sh}"
    # Also support Unknown template name for catch-all
    content="${content//Unknown\{\{TemplateName\}\}/Unknown$TEMPLATE_NAME}"
    
    echo "$content"
}

# Function to find rule section in file
find_rule_section() {
    local ip=$1
    local file=$2
    local start_line=0
    local end_line=0
    
    if [[ ! -f "$file" ]]; then
        echo "0:0"
        return
    fi
    
    # Find rule start and end lines
    while IFS= read -r line_info; do
        if [[ "$line_info" =~ ^([0-9]+):(.*)$ ]]; then
            local line_num="${BASH_REMATCH[1]}"
            local line_content="${BASH_REMATCH[2]}"
            
            if [[ "$line_content" =~ ^#\ Rule\ ${ip}$ ]]; then
                start_line=$line_num
            elif [[ "$line_content" =~ ^##\ End\ rule\ ${ip}$ ]] && [[ $start_line -gt 0 ]]; then
                end_line=$line_num
                break
            fi
        fi
    done < <(grep -n "^#.*${ip}" "$file" 2>/dev/null || true)
    
    echo "${start_line}:${end_line}"
}

# Function to extract catch-all section from file
extract_catchall_section() {
    local file=$1
    
    if [[ ! -f "$file" ]]; then
        echo ""
        return
    fi
    
    # Look for catch-all section
    if grep -q "^# Catch-all" "$file" 2>/dev/null; then
        # Extract everything from "# Catch-all" to the end of file
        sed -n '/^# Catch-all/,$p' "$file"
    else
        echo ""
    fi
}

# Function to remove catch-all section from content
remove_catchall_section() {
    local file=$1
    
    if [[ ! -f "$file" ]]; then
        return
    fi
    
    # Remove catch-all section if present
    if grep -q "^# Catch-all" "$file" 2>/dev/null; then
        local catchall_line=$(grep -n "^# Catch-all" "$file" | head -1 | cut -d: -f1)
        if [[ -n "$catchall_line" ]] && [[ "$catchall_line" -gt 0 ]]; then
            sed -i "1,$((catchall_line - 1))!d" "$file"
            # Clean up trailing empty lines
            sed -i -e :a -e '/^\s*$/d;N;ba' "$file"
        fi
    fi
}

# Function to create new rsyslog configuration
action_create() {
    log_message INFO "Creating new rsyslog configuration: $SYSLOG_FILE"
    
    if [[ -f "$SYSLOG_FILE_PATH" ]] && [[ "$DRY_RUN" != "true" ]]; then
        log_message WARNING "File already exists: $SYSLOG_FILE_PATH"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_message INFO "Aborted"
            exit 0
        fi
        backup_file "$SYSLOG_FILE_PATH"
    fi
    
    # Load base template
    local base_content=$(load_template "$SCRIPT_DIR/rsyslog-setting.tmpl")
    
    # Load rule template  
    local rule_content=$(load_template "$SCRIPT_DIR/rsyslog-rule.tmpl")
    
    # Load catch-all template if it exists
    local catchall_content=""
    if [[ -f "$SCRIPT_DIR/rsyslog-catchall.tmpl" ]]; then
        catchall_content=$(load_template "$SCRIPT_DIR/rsyslog-catchall.tmpl")
    fi
    
    # Combine templates
    local full_content="${base_content}

${rule_content}"
    
    # Add catch-all at the end if available
    if [[ -n "$catchall_content" ]]; then
        full_content="${full_content}

${catchall_content}"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message INFO "[DRY-RUN] Would create file: $SYSLOG_FILE_PATH"
        echo "Content:"
        echo "$full_content"
    else
        echo "$full_content" > "$SYSLOG_FILE_PATH"
        chmod 644 "$SYSLOG_FILE_PATH"
        log_message SUCCESS "Created configuration file: $SYSLOG_FILE_PATH"
        
        # Validate rsyslog syntax
        if command -v rsyslogd &> /dev/null; then
            if rsyslogd -N1 -f "$SYSLOG_FILE_PATH" &>/dev/null; then
                log_message SUCCESS "Rsyslog syntax validation passed"
            else
                log_message WARNING "Rsyslog syntax validation failed - please check the configuration"
            fi
        fi
    fi
}

# Function to add or update device rule
action_add() {
    log_message INFO "Adding/updating device rule for IP: $DEVICE_IP"
    
    # Check if file exists
    if [[ ! -f "$SYSLOG_FILE_PATH" ]]; then
        log_message ERROR "Configuration file not found: $SYSLOG_FILE_PATH"
        log_message INFO "Use --action create to create a new configuration file"
        exit 1
    fi
    
    # Extract catch-all section before modifications
    local catchall_section=$(extract_catchall_section "$SYSLOG_FILE_PATH")
    
    # Find existing rule
    local rule_location=$(find_rule_section "$DEVICE_IP" "$SYSLOG_FILE_PATH")
    IFS=':' read -r start_line end_line <<< "$rule_location"
    
    backup_file "$SYSLOG_FILE_PATH"
    
    if [[ $start_line -gt 0 ]] && [[ $end_line -gt 0 ]]; then
        # Rule exists - update it
        log_message INFO "Updating existing rule for $DEVICE_IP"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_message INFO "[DRY-RUN] Would update rule at lines $start_line-$end_line"
        else
            # Create new content without the old rule
            local new_content=$(sed "${start_line},${end_line}d" "$SYSLOG_FILE_PATH")
            
            # Load new rule from template
            local rule_content=$(load_template "$SCRIPT_DIR/rsyslog-rule.tmpl")
            
            # Insert new rule at the same position
            local before_rule=$(head -n $((start_line - 1)) "$SYSLOG_FILE_PATH")
            local after_rule=$(tail -n +$((end_line + 1)) "$SYSLOG_FILE_PATH")
            
            {
                echo "$before_rule"
                echo "$rule_content"
                echo "$after_rule"
            } > "$SYSLOG_FILE_PATH"
            
            log_message SUCCESS "Updated rule for $DEVICE_IP (hostname: $DEVICE_HOSTNAME)"
        fi
    else
        # Rule doesn't exist - add it
        log_message INFO "Adding new rule for $DEVICE_IP"
        
        # Load rule template
        local rule_content=$(load_template "$SCRIPT_DIR/rsyslog-rule.tmpl")
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_message INFO "[DRY-RUN] Would add new rule:"
            echo "$rule_content"
        else
            # First, remove catch-all section temporarily
            remove_catchall_section "$SYSLOG_FILE_PATH"
            
            # Append rule to file
            echo "" >> "$SYSLOG_FILE_PATH"
            echo "$rule_content" >> "$SYSLOG_FILE_PATH"
            
            # Re-add catch-all section if it existed
            if [[ -n "$catchall_section" ]]; then
                echo "" >> "$SYSLOG_FILE_PATH"
                echo "$catchall_section" >> "$SYSLOG_FILE_PATH"
            fi
            
            log_message SUCCESS "Added rule for $DEVICE_IP (hostname: $DEVICE_HOSTNAME)"
        fi
    fi
}

# Function to delete device rule
action_delete() {
    log_message INFO "Deleting device rule for IP: $DEVICE_IP"
    
    # Check if file exists
    if [[ ! -f "$SYSLOG_FILE_PATH" ]]; then
        log_message ERROR "Configuration file not found: $SYSLOG_FILE_PATH"
        exit 1
    fi
    
    # Find existing rule
    local rule_location=$(find_rule_section "$DEVICE_IP" "$SYSLOG_FILE_PATH")
    IFS=':' read -r start_line end_line <<< "$rule_location"
    
    if [[ $start_line -eq 0 ]] || [[ $end_line -eq 0 ]]; then
        log_message WARNING "No rule found for IP: $DEVICE_IP"
        exit 0
    fi
    
    backup_file "$SYSLOG_FILE_PATH"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message INFO "[DRY-RUN] Would delete rule at lines $start_line-$end_line"
        sed -n "${start_line},${end_line}p" "$SYSLOG_FILE_PATH"
    else
        # Delete the rule section
        sed -i "${start_line},${end_line}d" "$SYSLOG_FILE_PATH"
        
        # Clean up extra blank lines
        sed -i '/^$/N;/^\n$/d' "$SYSLOG_FILE_PATH"
        
        log_message SUCCESS "Deleted rule for $DEVICE_IP"
    fi
}

# Function to restart rsyslog service
restart_rsyslog() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message INFO "[DRY-RUN] Would restart rsyslog service"
        return
    fi
    
    if command -v systemctl &> /dev/null; then
        if systemctl restart rsyslog &>/dev/null; then
            log_message SUCCESS "Rsyslog service restarted"
        else
            log_message WARNING "Failed to restart rsyslog service"
        fi
    elif command -v service &> /dev/null; then
        if service rsyslog restart &>/dev/null; then
            log_message SUCCESS "Rsyslog service restarted"
        else
            log_message WARNING "Failed to restart rsyslog service"
        fi
    else
        log_message WARNING "Could not restart rsyslog service - please restart manually"
    fi
}

# Main function
main() {
    log_message INFO "Starting syslog-settings v1.1.1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message INFO "*** DRY-RUN MODE - No changes will be made ***"
    fi
    
    # Validate parameters
    validate_parameters
    
    # Execute action
    case "$ACTION" in
        create)
            action_create
            ;;
        add)
            action_add
            ;;
        delete)
            action_delete
            ;;
    esac
    
    # Reload rsyslog if not in dry-run mode
    if [[ "$DRY_RUN" != "true" ]]; then
        restart_rsyslog
    fi
    
    log_message INFO "Operation completed"
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
        --syslog-file)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --syslog-file requires an argument"
                exit 1
            fi
            SYSLOG_FILE="$2"
            shift 2
            ;;
        --template-name)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --template-name requires an argument"
                exit 1
            fi
            TEMPLATE_NAME="$2"
            shift 2
            ;;
        --dst-logs)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --dst-logs requires an argument"
                exit 1
            fi
            DST_LOGS="$2"
            shift 2
            ;;
        --device-ip)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --device-ip requires an argument"
                exit 1
            fi
            DEVICE_IP="$2"
            shift 2
            ;;
        --device-hostname)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --device-hostname requires an argument"
                exit 1
            fi
            DEVICE_HOSTNAME="$2"
            shift 2
            ;;
        --action)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --action requires an argument"
                exit 1
            fi
            ACTION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main

exit 0