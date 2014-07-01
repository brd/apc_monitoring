apc_monitoring
==============

Perl tools to get APC PDU / UPS data into Nagios/Graphite.

Tested with the following PDUs: AP8941, AP7921, AP7941 and a Symmetra LX UPS.

Basic usage:

    check_apc nagios host [community] warn crit
        Single shot check mode of checking just a single host. If the community
        name is excluded, the config file will be checked or the "public"
        community will be used instead.

    check_apc graphite
        Check each host listed in config.pl and send the data into the Graphite
        host configured in 'config.pl'.
