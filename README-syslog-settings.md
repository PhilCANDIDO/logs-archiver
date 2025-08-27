# syslog-settings

## Purpose

Manage the rsyslog setting file to add, remove or modify a syslog source.

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
- `--syslog-file`: rsyslog setting file to manage (mandatory)
- `--template-name`: Tempate used in rsyslog setting file. (mandatory)
- `--dst-logs`: Destination path logs storage (mandatory)
- `--device-ip`: Address IP of the device (mandatory)
- `--device-hostname`: Hostname of the device. If is not provide, used the `--device-ip` valude
- `--action`: Can be 3 types of action `Add`(default), `create` and  `delete`. `Add` add a new device or modify it. `delete` delete device in setting file. `create` create a new setting file from the rsyslog template file.

## Rsyslog template file



## Examples

We have the rsyslog setting file `/etc/rsyslog.d/20-firewalls.conf` with the contains :

```conf
# Templating : YYYY/MM/DD/Device.log
template(name="FirewallLogTemplate" type="string" string="/var/syslog/firewalls/%$YEAR%/%$MONTH%/%$DAY%/%HOSTNAME%.log")

# Rule for 10.0.92.1
if ($fromhost-ip == '10.0.92.1') then {
    action(type="omfile" dynaFile="FirewallLogTemplate")
    stop
}

# Rule for 10.0.2.30
if ($fromhost-ip == '10.0.2.30') then {
    action(type="omfile" dynaFile="FirewallLogTemplate")
    stop
}
```

If the 