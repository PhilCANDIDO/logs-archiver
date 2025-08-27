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
- `--template-name`: Template used in rsyslog setting file. (mandatory)
- `--dst-logs`: Destination path logs storage (mandatory)
- `--device-ip`: Address IP of the device (mandatory)
- `--device-hostname`: Hostname of the device. If is not provide, used the `--device-ip` valude
- `--action`: Can be 3 types of action `Add`(default), `create` and  `delete`. `Add` add a new device or modify it. `delete` delete device in setting file. `create` create a new setting file from the rsyslog template file.

> [!NOTE]
> For the `add` and `delete` action, use the `--device-ip` value to find the rule section.

## Rsyslog template file

The rsyslog template file allow to create a new rsyslog file to accept logs sending from remote devices.

The ryslog setting base file template is [rsyslog-setting.tmpl](./rsyslog-setting.tmpl).

The ryslog rule base file template is [rsyslog-rule.tmpl](./rsyslog-rule-setting.tmpl).

In each template file replace the variable with :
- `{{TemplateName}}`: value of parameter `--template-name`
- `{{DstLogs}}`: value of parameter `--dst-logs`
- `{{DeviceIp}}`: value of parameter `--device-ip`
- `{{DeviceHostname}}`: value of parameter `--device-hostname`

## Examples

We have the rsyslog setting file `/etc/rsyslog.d/20-firewalls.conf` with the contains :

```conf
## Create from script syslog-settings.sh
## DO NOT REMOVE COMMENTS
# Templating : YYYY/MM/DD/Device.log
template(name="FirewallLogTemplate" type="string" string="/var/syslog/firewalls/%$YEAR%/%$MONTH%/%$DAY%/%HOSTNAME%.log")

# Rule 10.0.92.1
# Hostname: 10.0.92.1
if ($fromhost-ip == '10.0.92.1') then {
    action(type="omfile" dynaFile="FirewallLogTemplate")
    stop
}
## End rule 10.0.92.1

# Rule 10.0.2.30
# Hostname: 10.0.2.30
if ($fromhost-ip == '10.0.2.30') then {
    action(type="omfile" dynaFile="FirewallLogTemplate")
    stop
}
## End rule 10.0.2.30
```

### Example add rule 

The command `bash syslog-settings.sh --syslog-file 20-firewalls.conf --template-name FirewallLogTemplate --dst-logs /var/syslog/firewalls --device-ip 10.0.3.254 --device-hostname fortigate-external` add a new rule in the file `/etc/rsyslog.d/20-firewalls.conf` :

```conf
## Create from script syslog-settings.sh
## DO NOT REMOVE COMMENTS
# Templating : YYYY/MM/DD/Device.log
template(name="FirewallLogTemplate" type="string" string="/var/syslog/firewalls/%$YEAR%/%$MONTH%/%$DAY%/%HOSTNAME%.log")

# Rule 10.0.92.1
# Hostname: 10.0.92.1
if ($fromhost-ip == '10.0.92.1') then {
    action(type="omfile" dynaFile="FirewallLogTemplate")
    stop
}
## End rule 10.0.92.1

# Rule 10.0.2.30
# Hostname: 10.0.92.1
if ($fromhost-ip == '10.0.2.30') then {
    action(type="omfile" dynaFile="FirewallLogTemplate")
    stop
}
## End rule 10.0.92.1

# Rule 10.0.3.254
# Hostname: fortigate-external
if ($fromhost-ip == '10.0.3.254') then {
    action(type="omfile" dynaFile="FirewallLogTemplate")
    stop
}
## End rule 10.0.92.1
```

### Example delete rule 

The command `bash syslog-settings.sh --syslog-file 20-firewalls.conf --template-name FirewallLogTemplate --dst-logs /var/syslog/firewalls --device-ip 10.0.3.254 --action delete` delete the rule contains ip "10.0.3.254" the file `/etc/rsyslog.d/20-firewalls.conf` :

```conf
## Create from script syslog-settings.sh
## DO NOT REMOVE COMMENTS
# Templating : YYYY/MM/DD/Device.log
template(name="FirewallLogTemplate" type="string" string="/var/syslog/firewalls/%$YEAR%/%$MONTH%/%$DAY%/%HOSTNAME%.log")

# Rule 10.0.92.1
# Hostname: 10.0.92.1
if ($fromhost-ip == '10.0.92.1') then {
    action(type="omfile" dynaFile="FirewallLogTemplate")
    stop
}
## End rule 10.0.92.1

# Rule 10.0.2.30
# Hostname: 10.0.92.1
if ($fromhost-ip == '10.0.2.30') then {
    action(type="omfile" dynaFile="FirewallLogTemplate")
    stop
}
## End rule 10.0.92.1
```

### Example create a new rsyslog setting file

The command `bash syslog-settings.sh --syslog-file 30-switches.conf --template-name SwitchLogTemplate --dst-logs /var/syslog/switches --device-ip 10.10.10.10 --action create` create the file `/etc/rsyslog.d/30-switches.conf` and the the rule :

```conf
## Create from script syslog-settings.sh
## DO NOT REMOVE COMMENTS
# Templating : YYYY/MM/DD/Device.log
template(name="SwitchLogTemplate" type="string" string="/var/syslog/switches/%$YEAR%/%$MONTH%/%$DAY%/%HOSTNAME%.log")

# Rule 10.10.10.10
# Hostname: 10.10.10.10
if ($fromhost-ip == '10.10.10.10') then {
    action(type="omfile" dynaFile="SwitchLogTemplate")
    stop
}
## End rule 10.10.10.10
```

