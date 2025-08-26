#!/bin/bash

# Test script for logs-archiver.sh
# This script creates a test environment and runs the archiver

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Setting up test environment ===${NC}"

# Create test directory structure
TEST_DIR="/tmp/test-logs-archiver"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"/{source,archives}

# Create sample log files with different dates
echo "Creating sample log files..."
for days_ago in 1 3 6 8 10 15; do
    date_str=$(date -d "$days_ago days ago" '+%Y/%m/%d')
    dir="$TEST_DIR/source/$date_str"
    mkdir -p "$dir"
    
    # Create some log files
    for device in router1 router2 switch1 firewall1; do
        log_file="$dir/${device}.log"
        echo "Sample log entry for $device on $(date -d "$days_ago days ago")" > "$log_file"
        # Add some content to make compression visible
        for i in {1..100}; do
            echo "Log line $i: Sample data for compression testing - $(date -d "$days_ago days ago" '+%Y-%m-%d %H:%M:%S')" >> "$log_file"
            echo "Event: Connection from 192.168.1.$i to server" >> "$log_file"
        done
        # Set the file modification time
        touch -d "$days_ago days ago" "$log_file"
    done
done

echo -e "${GREEN}Test environment created with $(find $TEST_DIR/source -type f -name '*.log' | wc -l) log files${NC}"

echo -e "\n${GREEN}=== Running logs-archiver.sh ===${NC}"
echo "Archiving files older than 7 days..."

# Run the archiver
"$(dirname "$0")/logs-archiver.sh" \
    --src-path "$TEST_DIR/source" \
    --src-pattern '{YYYY}/{MM}/{DD}/*.log' \
    --dst-path "$TEST_DIR/archives" \
    --retention 7 \
    --compress-level 9 \
    --verbose

echo -e "\n${GREEN}=== Test Results ===${NC}"
echo "Archived files:"
find "$TEST_DIR/archives" -type f -name "*.bz2" | wc -l

echo -e "\nRemaining source files (should be recent ones only):"
find "$TEST_DIR/source" -type f -name "*.log" | wc -l

echo -e "\nArchive directory structure:"
tree "$TEST_DIR/archives" 2>/dev/null || find "$TEST_DIR/archives" -type d | sort

echo -e "\n${YELLOW}Test complete! Check $TEST_DIR for results.${NC}"