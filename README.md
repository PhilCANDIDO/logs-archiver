# logs-archiver

## Purpose

Copy log files from a path pattern, to a destination folder with compression.  

## Developpement rules

- This project store a Bash script. 
- The script respect idempotent principe.
- A header contains :
  - Current version of script
  - Author
  - support
- On each main modification, the current version is updated and changelog is created with historic of changements.
- A error controls must be realize on earch command.

## Functions and parameters

The parameters are :

- `--help or -h`: Display the helpline of script
- `--no-log`: Display only std output
- `--verbose`: Display all messages in verbosity.
- `--dry-run`: Simulate operations without making any changes (preview mode)
- `--src-path`: Source root path of logs files (mandatory)
- `--src-pattern`: Pattern of the logs source folders and file. Use YYYY for Year, MM for month, DD for day. (mandatory)
- `--dst-path`: Destination path of the archive (mandatory)
- `--retention`: Number in day, to keep logs from the `--src-path` (default 5 days)
  - 0 = archive all files
  - 1 = archive files from yesterday and older (≥24 hours old)
  - N = archive files older than N-1 days
- `--log-path` : Log file of script execution (default: current script location)
- `--log-retention`: Number in day, to keep script log files (default 5 days)
- `--compress-level`: Compression level of archive

## Examples

The server SYSLOG gather logs from all networt device. The logs are store in path using the pattern `/var/syslog/{YYYY}/{MM}/{DD}/{device-name}.log`
The archive folder, is on the same server on the folder `/archives`.
Ths script must get the logs from the source folder `/var/syslog/{YYYY}/{MM}/{DD}/{device-name}.log`, compress the logs to the folder `/archives/var/syslog/{YYYY}/{MM}/{DD}/{device-name}.log.bz2`. If the copy is success, delete logs from source folder older or equal at `--retention`.
The script must provide a log file, with the summary of parameters used, the number of files copied, with the initial size and the destination size, and the total time of script execution.
