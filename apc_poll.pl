#!/usr/bin/perl

# need to add
#	locking with flock
#	check an snmp value to see if a PDU has 2 banks and respond appropriately
#	argument checking to run for nagios for a specific host or graphite for all hosts

use v5.10;
use strict;
use warnings;
use Net::SNMP;
use IO::Socket;

# Check which mode we are running in
# Nagios or Graphite
my $args = $#ARGV + 1;
if($args == 0) {
	usage();
}

# Predefine variables
our (%hostlist, $debug, $graphite_enable, $graphite_host, $graphite_path);

# Include the config
require 'config.pl' or die "Unable to open config.pl: $!";

# OIDs for the PDUs
my $phase_power_oid  = ".1.3.6.1.4.1.318.1.1.12.1.16.0";
my $phase_current_oid = ".1.3.6.1.4.1.318.1.1.12.2.3.1.1.2.1";
my $bank1_oid = ".1.3.6.1.4.1.318.1.1.12.2.3.1.1.2.2";
my $bank2_oid = ".1.3.6.1.4.1.318.1.1.12.2.3.1.1.2.3";

# The Current Epoch time
my $epoch = time;

while ( my ($host, $community) = each %hostlist) {

	my ($session, $error) = Net::SNMP->session(
		Hostname => "$host",
		Community => $community,
	) or warn "Session: $!";
	
	# Poll
	my $phase_power = $session->get_request("$phase_power_oid")     or warn "failed to poll phase power on $host: $!";
	my $phase_current = $session->get_request("$phase_current_oid") or warn "failed to poll phase current on $host: $!";
	my $bank1_current = $session->get_request("$bank1_oid")	 or warn "failed to poll bank1 current on $host: $!";
	my $bank2_current = $session->get_request("$bank2_oid")	 or warn "failed to poll bank2 current on $host: $!";

	print "hostname: $host\n";
	print "phase power is:   $phase_power->{$phase_power_oid}\n";
	print "phase current is: " . $phase_current->{$phase_current_oid} / 10 . "\n";
	print "bank1 current is: " . $bank1_current->{$bank1_oid} / 10 . "\n";
	print "bank2 current is: " . $bank2_current->{$bank2_oid} / 10 . "\n";
	
	# If Graphite
	if ( $graphite_enable == 1 && $graphite_host ) {
		# Open connection
		print "sending $host data to graphite..";
		my $client = IO::Socket::INET->new(
				Proto => 'tcp',
				PeerAddr => $graphite_host,
				PeerPort => 2003,
			) or die "Cannot connect: $!";
	
		# Write the data to graphite
		print $client "$graphite_path.$host.watts "   . $phase_power->{$phase_power_oid}          . " " . $epoch . "\n";
		print $client "$graphite_path.$host.current " . $phase_current->{$phase_current_oid} / 10 . " " . $epoch . "\n";
		print $client "$graphite_path.$host.bank1 "   . $bank1_current->{$bank1_oid} / 10         . " " . $epoch . "\n";
		print $client "$graphite_path.$host.bank2 "   . $bank2_current->{$bank2_oid} / 10         . " " . $epoch . "\n";
		close $client;
	}

	# If debugging is enabled
	if ( $debug == 1 && $debug ) {
		print "$graphite_path.$host.watts "   . $phase_power->{$phase_power_oid}          . " " . $epoch . "\n";
		print "$graphite_path.$host.current " . $phase_current->{$phase_current_oid} / 10 . " " . $epoch . "\n";
		print "$graphite_path.$host.bank1 "   . $bank1_current->{$bank1_oid} / 10         . " " . $epoch . "\n";
		print "$graphite_path.$host.bank2 "   . $bank2_current->{$bank2_oid} / 10         . " " . $epoch . "\n";
	}
	
	print " done\n";
	
	$session->close();
}


sub usage {
	 say "Usage:";
	 say "	check_apc nagios host [community] warn crit";
	 say "		Single shot check mode of checking just a single host. If the community";
	 say "		name is excluded, the config file will be checked or the \"public\"";
	 say "		community will be used instead.";
	 say "	check_apc graphite";
	 say "		Check each host listed in config.pl and send the data into the Graphite";
	 say "		host configured in 'config.pl'.";
	 exit 1;
}

# EOF
