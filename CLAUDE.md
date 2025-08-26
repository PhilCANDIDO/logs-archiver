# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Bash script project for archiving log files with compression. The script copies log files from a source path pattern to a destination folder with compression (bzip2 format), maintaining the original directory structure.

## Development Guidelines

### Script Requirements
- The main script must be idempotent - safe to run multiple times with the same result
- Include a header with version number, author, and support information
- Update version number and maintain a changelog for main modifications
- Implement comprehensive error controls for each command
- Provide detailed logging of operations

### Script Parameters
The script must support these command-line arguments:
- `--help` or `-h`: Display help information
- `--no-log`: Display only standard output
- `--verbose`: Enable verbose output
- `--src-path`: Source root path (mandatory)
- `--src-pattern`: Pattern with YYYY (year), MM (month), DD (day) placeholders (mandatory)
- `--dst-path`: Destination archive path (mandatory)
- `--retention`: Days to keep logs in source (default: 5)
- `--log-path`: Script execution log location (default: script directory)
- `--compress-level`: Compression level for archives

### Key Functionality
1. Copy logs from source using pattern matching (e.g., `/var/syslog/{YYYY}/{MM}/{DD}/{device-name}.log`)
2. Compress to destination maintaining structure (e.g., `.log` → `.log.bz2`)
3. Delete source files older than retention period after successful copy
4. Generate execution log with:
   - Parameters used
   - File count and sizes (before/after compression)
   - Total execution time

## Commands

### Testing the Script

```bash
# Make scripts executable
chmod +x logs-archiver.sh test-script.sh

# Run the test script (creates test environment and runs archiver)
./test-script.sh

# Or test manually with help
./logs-archiver.sh --help

# Run with example parameters
./logs-archiver.sh \
  --src-path /var/syslog \
  --src-pattern "{YYYY}/{MM}/{DD}/*.log" \
  --dst-path /archives \
  --retention 5 \
  --verbose
```

## Architecture Notes

This is a single Bash script project focused on log archival. The script should:
- Handle date pattern replacements ({YYYY}, {MM}, {DD})
- Perform atomic operations to ensure data integrity
- Provide robust error handling and recovery
- Support both interactive and cron-based execution