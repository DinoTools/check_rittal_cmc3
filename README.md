check_rittal_cmc3
=================

Monitoring plugin for [Icinga](https://www.icinga.org/), [Nagios](https://www.nagios.org/) etc. supporting [Rittal](https://www.rittal.com/) CMC3 devices.

Requriements
------------

**General**

- Perl 5
- Perl Modules
    - Net::SNMP
    - Class::Load
    - Monitoring::Plugin or Nagios::Plugin

**RHEL/CentOS**

- perl
- perl-Class-Load
- perl-Monitoring-Plugin or perl-Nagios-Plugin
- perl-Net-SNMP

Installation
------------

Just copy the file `check_rittal_cmc3.pl` to your Icinga or Nagios plugin directory.

**Icinga 2**

Add a new check command

```
object CheckCommand "rittal-cmc3" {
  import "plugin-check-command"
  import "ipv4-or-ipv6"

  command = [ PluginDir + "/check_rittal_cmc3.pl" ]

  arguments = {
    "-H" = {
      value = "$rittal_cmc3_address$"
      description = "Hostname of the CMCIII unit."
      required = true
    }
    "-C" = {
      value = "$rittal_cmc3_community$"
      description = "SNMP community. Defaults to 'public' if omitted."
    }
    "-D" = {
      value = "$rittal_cmc3_device$"
      description = "ID of the device connected to the CMCIII"
      required = true
    }
    "--sensor" = {
      value = "$rittal_cmc3_sensors$"
      repeat_key = true
    }
  }

  vars.rittal_cmc3_address = "$check_address$"
}
```

License
-------

GPLv3
