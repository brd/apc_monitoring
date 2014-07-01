apc_monitoring
==============

Perl tools to get data into Nagios/Graphite

Basic usage:

    check_apc nagios host [community] warn crit
        Single shot check mode of checking just a single host. If the community
        name is excluded, the config file will be checked or the "public"
        community will be used instead.

    check_apc graphite
        Check each host listed in config.pl and send the data into the Graphite
        host configured in 'config.pl'.
