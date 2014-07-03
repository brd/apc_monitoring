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
no warnings 'uninitialized';

# Check which mode we are running in
# Nagios or Graphite
my $args = $#ARGV + 1;
if($args == 0) {
	usage();
}
elsif($args == 1) {
	if($ARGV[0] eq "graphite") {
		graphite();
	}
	else {
		usage();
	}
}
elsif($args == 2 || $args == 3) {
	if($ARGV[0] eq "nagios") {
		if ($args == 2) {
			nagios(2, $ARGV[1]);
		}
		elsif($args == 3) {
			nagios(3, $ARGV[1], $ARGV[2]);
		}
		else {
			usage();
		}
	}
	else {
		usage();
	}
}
else {
	usage();
}

# Predefine variables
our (%hostlist, $debug, $graphite_enable, $graphite_host, $graphite_path);

# Include the config
require 'config.pl' or die "Unable to open config.pl: $!";

# The Current Epoch time
my $epoch = time;


sub snmppoll {

	 my ($host, $community) = @_;
	 my %snmpresults;

	 # OIDs for the PDUs
	 my $num_banks_oid = '.1.3.6.1.4.1.318.1.1.12.2.1.4.0';
	 my $phase_power_oid  = '.1.3.6.1.4.1.318.1.1.12.1.16.0';
	 my $phase_current_oid = '.1.3.6.1.4.1.318.1.1.12.2.3.1.1.2.1';
	 my $bank1_oid = '.1.3.6.1.4.1.318.1.1.12.2.3.1.1.2.2';
	 my $bank2_oid = '.1.3.6.1.4.1.318.1.1.12.2.3.1.1.2.3';
	 my $phase_nearoverload_oid = '.1.3.6.1.4.1.318.1.1.12.2.2.1.1.4.1';
	 my $phase_overload_oid = '.1.3.6.1.4.1.318.1.1.12.2.2.1.1.3.1';

	 say "snmppoll(): host: $host, community: \"$community\"";

	 my ($session, $error) = Net::SNMP->session(
			Hostname => $host,
			Community => $community,
		) or warn "Unable to create Session: $!";

	 # Poll
	 my $num_banks = $session->get_request($num_banks_oid) or warn "failed to poll number of banks on $host: $!";
	 say "banks: $num_banks->{$num_banks_oid}";
	 if($num_banks->{$num_banks_oid} eq 0) {
	 	# AP7921
		say "banks = 0; ap7921";
	 	my $phase_power = $session->get_request("$phase_power_oid")     or warn "failed to poll phase power on $host: $!";
	 	my $phase_current = $session->get_request("$phase_current_oid") or warn "failed to poll phase current on $host: $!";
		my $nearoverload = $session->get_request($phase_nearoverload_oid) or warn "failed to poll near overload on $host: $!";
		my $overload = $session->get_request($phase_overload_oid) or warn "failed to poll overload on $host: $!";
		$snmpresults{$host}{'phasepower'} = $phase_power->{$phase_power_oid};
		$snmpresults{$host}{'phasecurrent'} = $phase_current->{$phase_current_oid} / 10;
		$snmpresults{$host}{'nearoverload'} = $nearoverload->{$phase_nearoverload_oid};
		$snmpresults{$host}{'overload'} = $overload->{$phase_overload_oid};
	 	say "phase power is: " . $phase_power->{$phase_power_oid};
	 	say "phase current is: " . $phase_current->{$phase_current_oid} / 10;
		say "near overload is: " . $nearoverload->{$phase_nearoverload_oid};
		say "overload is: " . $overload->{$phase_overload_oid};
	 }
	 elsif($num_banks->{$num_banks_oid} eq 2) {
	 	# AP8941
		say "banks = 2; ap8941";
	 	my $phase_power = $session->get_request("$phase_power_oid")     or warn "failed to poll phase power on $host: $!";
	 	my $phase_current = $session->get_request("$phase_current_oid") or warn "failed to poll phase current on $host: $!";
	 	my $bank1_current = $session->get_request("$bank1_oid")	 or warn "failed to poll bank1 current on $host: $!";
	 	my $bank2_current = $session->get_request("$bank2_oid")	 or warn "failed to poll bank2 current on $host: $!";
		my $nearoverload = $session->get_request($phase_nearoverload_oid) or warn "failed to poll near overload on $host: $!";
		my $overload = $session->get_request($phase_overload_oid) or warn "failed to poll overload on $host: $!";
		$snmpresults{$host}{'phasepower'} = $phase_power->{$phase_power_oid};
		$snmpresults{$host}{'phasecurrent'} = $phase_current->{$phase_current_oid} / 10;
		$snmpresults{$host}{'bank1current'} = $bank1_current->{$bank1_oid} / 10;
		$snmpresults{$host}{'bank2current'} = $bank2_current->{$bank2_oid} / 10;
		$snmpresults{$host}{'nearoverload'} = $nearoverload->{$phase_nearoverload_oid};
		$snmpresults{$host}{'overload'} = $overload->{$phase_overload_oid};
	 	say "phase power is: " . $phase_power->{$phase_power_oid};
	 	say "phase current is: " . $phase_current->{$phase_current_oid} / 10;
	 	say "bank1 current is: " . $bank1_current->{$bank1_oid} / 10;
	 	say "bank2 current is: " . $bank2_current->{$bank2_oid} / 10;
	 	say "near overload is: " . $nearoverload->{$phase_nearoverload_oid};
	 	say "overload is: " . $overload->{$phase_overload_oid};
	 }
	 else {
	 	say "banks unknown";
		$snmpresults{error} = 1;
		$snmpresults{errorstr} = "Unable to poll $host";
	 }

	 return %snmpresults;
}


sub nagios {

	 my ($numofargs, $host, $community) = @_;
	 my %snmpresults = snmppoll($host, $community);

	 # Check if overload or near overload
	 if ($snmpresults{$host}{'phasecurrent'} > $snmpresults{$host}{'overload'}) {
		say "LOAD CRITICAL - " . $snmpresults{$host}{'phasecurrent'} . "A > " . $snmpresults{$host}{'overload'} . "A";
		exit 2;
	 }
	 elsif ($snmpresults{$host}{'phasecurrent'} > $snmpresults{$host}{'nearoverload'}) {
		say "LOAD WARNING - " . $snmpresults{$host}{'phasecurrent'} . "A > " . $snmpresults{$host}{'nearoverload'} . "A";
		exit 1;
	 }
	 else {
		say "LOAD OK - " . $snmpresults{$host}{'phasecurrent'} . "A < " . $snmpresults{$host}{'nearoverload'} . "A";
		exit 0;
	 }
}


sub graphite {
	while ( my ($host, $community) = each %hostlist) {

		my $session = snmppoll($host, $community);

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
			#print $client "$graphite_path.$host.watts "   . $phase_power->{$phase_power_oid}          . " " . $epoch . "\n";
			#print $client "$graphite_path.$host.current " . $phase_current->{$phase_current_oid} / 10 . " " . $epoch . "\n";
			#print $client "$graphite_path.$host.bank1 "   . $bank1_current->{$bank1_oid} / 10         . " " . $epoch . "\n";
			#print $client "$graphite_path.$host.bank2 "   . $bank2_current->{$bank2_oid} / 10         . " " . $epoch . "\n";
			close $client;
		}

		# If debugging is enabled
		if ( $debug == 1 && $debug ) {
			#print "$graphite_path.$host.watts "   . $phase_power->{$phase_power_oid}          . " " . $epoch . "\n";
			#print "$graphite_path.$host.current " . $phase_current->{$phase_current_oid} / 10 . " " . $epoch . "\n";
			#print "$graphite_path.$host.bank1 "   . $bank1_current->{$bank1_oid} / 10         . " " . $epoch . "\n";
			#print "$graphite_path.$host.bank2 "   . $bank2_current->{$bank2_oid} / 10         . " " . $epoch . "\n";
		}

		$session->close();
	}
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
