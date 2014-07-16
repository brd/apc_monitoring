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
if ( $args == 0 ) {
    usage();
}
elsif ( $args == 1 ) {
    if ( $ARGV[0] eq "graphite" ) {
		# Include the config
		require 'config.pl' or die "Unable to open config.pl: $!";
        graphite();
    }
    else {
        usage();
    }
}
elsif ( $args == 2 || $args == 3 ) {
    if ( $ARGV[0] eq "nagios" ) {
        if ( $args == 2 ) {
            nagios( 2, $ARGV[1] );
        }
        elsif ( $args == 3 ) {
            nagios( 3, $ARGV[1], $ARGV[2] );
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
our ( %hostlist, $debug, $graphite_enable, $graphite_host, $graphite_path );

# The Current Epoch time
my $epoch = time;

sub snmppoll {

    my ( $host, $community ) = @_;
    my %snmpresults;

    # OIDs for the PDUs
    # PowerNet-MIB::sPDUIdentModelNumber.0
    my $pdu_model_oid = '.1.3.6.1.4.1.318.1.1.4.1.4.0';
    # PowerNet-MIB::rPDULoadDevNumBanks.0
    my $num_banks_oid = '.1.3.6.1.4.1.318.1.1.12.2.1.4.0';
    # PowerNet-MIB::rPDUIdentDevicePowerWatts.0
    my $phase_power_oid = '.1.3.6.1.4.1.318.1.1.12.1.16.0';
    # PowerNet-MIB::rPDULoadStatusLoad.1
    my $phase_current_oid = '.1.3.6.1.4.1.318.1.1.12.2.3.1.1.2.1';
    # PowerNet-MIB::rPDULoadStatusLoad.2
    my $bank1_oid = '.1.3.6.1.4.1.318.1.1.12.2.3.1.1.2.2';
    # PowerNet-MIB::rPDULoadStatusLoad.3
    my $bank2_oid = '.1.3.6.1.4.1.318.1.1.12.2.3.1.1.2.3';
    # PowerNet-MIB::rPDULoadPhaseConfigOverloadThreshold.phase1
    my $phase_nearoverload_oid = '.1.3.6.1.4.1.318.1.1.12.2.2.1.1.4.1';
    # PowerNet-MIB::rPDULoadPhaseConfigNearOverloadThreshold.phase1
    my $phase_overload_oid = '.1.3.6.1.4.1.318.1.1.12.2.2.1.1.3.1';

    # OIDs for the UPS
    # PowerNet-MIB::upsBasicIdentModel.0
    my $ups_model_oid = '.1.3.6.1.4.1.318.1.1.1.1.1.1.0';
    # PowerNet-MIB::upsAdvBatteryRunTimeRemaining.0
    my $ups_runtime_oid = '.1.3.6.1.4.1.318.1.1.1.2.2.3.0';
    # PowerNet-MIB::upsAdvConfigAlarmRuntimeUnder.0
    my $ups_lowbatruntime_oid = '.1.3.6.1.4.1.318.1.1.1.5.2.23.0';
    # PowerNet-MIB::upsBasicBatteryStatus.0
    my $ups_battstatus_oid = '.1.3.6.1.4.1.318.1.1.1.2.1.1.0';
    # PowerNet-MIB::upsAdvBatteryCapacity.0
    my $ups_battcapacity_oid = '.1.3.6.1.4.1.318.1.1.1.2.2.1.0';
    # PowerNet-MIB::upsAdvBatteryActualVoltage.0
    my $ups_battvoltage_oid = '.1.3.6.1.4.1.318.1.1.1.2.2.8.0';
    # PowerNet-MIB::upsAdvInputLineVoltage.0
    my $ups_inputvoltage_oid = '.1.3.6.1.4.1.318.1.1.1.3.2.1.0';
    # PowerNet-MIB::upsAdvOutputVoltage.0
    my $ups_outputvoltage_oid = '.1.3.6.1.4.1.318.1.1.1.4.2.1.0';
    # PowerNet-MIB::upsAdvOutputCurrent.0
    my $ups_outputcurrent_oid = '.1.3.6.1.4.1.318.1.1.1.4.2.4.0';
    # PowerNet-MIB::upsAdvBatteryTemperature.0
    my $ups_temp_oid = '.1.3.6.1.4.1.318.1.1.1.2.2.2.0';
    # PowerNet-MIB::upsAdvOutputRedundancy.0
    my $ups_redundancy_oid = '.1.3.6.1.4.1.318.1.1.1.4.2.5.0';

    say "snmppoll(): host: $host, community: \"$community\"";

    my ( $session, $error ) = Net::SNMP->session(
        Hostname  => $host,
        Community => $community,
    ) or warn "Unable to create Session: $!";

    # Test for PDU or UPS
    my $pdu_model = $session->get_request($pdu_model_oid);
    if ( $pdu_model->{$pdu_model_oid} ) {
        $snmpresults{$host}{'type'}  = 'pdu';
        $snmpresults{$host}{'model'} = $pdu_model->{$pdu_model_oid};
    }
    my $ups_model = $session->get_request($ups_model_oid);
    if ( $ups_model->{$ups_model_oid} ) {
        $snmpresults{$host}{'type'}  = 'ups';
        $snmpresults{$host}{'model'} = $ups_model->{$ups_model_oid};
    }

    # Poll
    # PDU
    if ( $snmpresults{$host}{'type'} eq 'pdu' ) {
        my $num_banks = $session->get_request($num_banks_oid)
          or warn "failed to poll number of banks on $host: $!";
        say "banks: $num_banks->{$num_banks_oid}";
        if ( $num_banks->{$num_banks_oid} eq 0 ) {

            # AP7921
            say "banks = 0; $snmpresults{$host}{'model'}";
            my $phase_power = $session->get_request("$phase_power_oid")
              or warn "failed to poll phase power on $host: $!";
            my $phase_current = $session->get_request("$phase_current_oid")
              or warn "failed to poll phase current on $host: $!";
            my $nearoverload = $session->get_request($phase_nearoverload_oid)
              or warn "failed to poll near overload on $host: $!";
            my $overload = $session->get_request($phase_overload_oid)
              or warn "failed to poll overload on $host: $!";
            $snmpresults{$host}{'phasepower'} =
              $phase_power->{$phase_power_oid};
            $snmpresults{$host}{'phasecurrent'} =
              $phase_current->{$phase_current_oid} / 10;
            $snmpresults{$host}{'nearoverload'} =
              $nearoverload->{$phase_nearoverload_oid};
            $snmpresults{$host}{'overload'} = $overload->{$phase_overload_oid};
            say "phase power is: " . $phase_power->{$phase_power_oid};
            say "phase current is: "
              . $phase_current->{$phase_current_oid} / 10;
            say "near overload is: " . $nearoverload->{$phase_nearoverload_oid};
            say "overload is: " . $overload->{$phase_overload_oid};
        }
        elsif ( $num_banks->{$num_banks_oid} eq 2 ) {

            # AP8941
            say "banks = 2; $snmpresults{$host}{'model'}";
            my $phase_power = $session->get_request("$phase_power_oid")
              or warn "failed to poll phase power on $host: $!";
            my $phase_current = $session->get_request("$phase_current_oid")
              or warn "failed to poll phase current on $host: $!";
            my $bank1_current = $session->get_request("$bank1_oid")
              or warn "failed to poll bank1 current on $host: $!";
            my $bank2_current = $session->get_request("$bank2_oid")
              or warn "failed to poll bank2 current on $host: $!";
            my $nearoverload = $session->get_request($phase_nearoverload_oid)
              or warn "failed to poll near overload on $host: $!";
            my $overload = $session->get_request($phase_overload_oid)
              or warn "failed to poll overload on $host: $!";
            $snmpresults{$host}{'phasepower'} =
              $phase_power->{$phase_power_oid};
            $snmpresults{$host}{'phasecurrent'} =
              $phase_current->{$phase_current_oid} / 10;
            $snmpresults{$host}{'bank1current'} =
              $bank1_current->{$bank1_oid} / 10;
            $snmpresults{$host}{'bank2current'} =
              $bank2_current->{$bank2_oid} / 10;
            $snmpresults{$host}{'nearoverload'} =
              $nearoverload->{$phase_nearoverload_oid};
            $snmpresults{$host}{'overload'} = $overload->{$phase_overload_oid};
            say "phase power is: " . $phase_power->{$phase_power_oid};
            say "phase current is: "
              . $phase_current->{$phase_current_oid} / 10;
            say "bank1 current is: " . $bank1_current->{$bank1_oid} / 10;
            say "bank2 current is: " . $bank2_current->{$bank2_oid} / 10;
            say "near overload is: " . $nearoverload->{$phase_nearoverload_oid};
            say "overload is: " . $overload->{$phase_overload_oid};
        }
    }

    # UPS
    elsif ( $snmpresults{$host}{'type'} eq 'ups' ) {
        say "ups model: " . $ups_model->{$ups_model_oid};
        my $runtime       = $session->get_request($ups_runtime_oid);
        my $lowruntime    = $session->get_request($ups_lowbatruntime_oid);
        my $temp          = $session->get_request($ups_temp_oid);
        my $battstatus    = $session->get_request($ups_battstatus_oid);
        my $battcapacity  = $session->get_request($ups_battcapacity_oid);
        my $battvoltage   = $session->get_request($ups_battvoltage_oid);
        my $inputvoltage  = $session->get_request($ups_inputvoltage_oid);
        my $outputvoltage = $session->get_request($ups_outputvoltage_oid);
        my $outputcurrent = $session->get_request($ups_outputcurrent_oid);
        my $redundancy    = $session->get_request($ups_redundancy_oid);
        $snmpresults{$host}{'runtime'} = $runtime->{$ups_runtime_oid};
        $snmpresults{$host}{'lowruntime'} =
          $lowruntime->{$ups_lowbatruntime_oid};
        $snmpresults{$host}{'temp'}       = $temp->{$ups_temp_oid};
        $snmpresults{$host}{'battstatus'} = $battstatus->{$ups_battstatus_oid};
        $snmpresults{$host}{'battcapacity'} =
          $battcapacity->{$ups_battcapacity_oid};
        $snmpresults{$host}{'battvoltage'} =
          $battvoltage->{$ups_battvoltage_oid};
        $snmpresults{$host}{'inputvoltage'} =
          $inputvoltage->{$ups_inputvoltage_oid};
        $snmpresults{$host}{'outputvoltage'} =
          $outputvoltage->{$ups_outputvoltage_oid};
        $snmpresults{$host}{'outputcurrent'} =
          $outputcurrent->{$ups_outputcurrent_oid};
        $snmpresults{$host}{'redundancy'} = $redundancy->{$ups_redundancy_oid};
        say "runtime is: " . $snmpresults{$host}{'runtime'};
        say "lowruntime is: " . $snmpresults{$host}{'lowruntime'};
        say "temp is: " . $snmpresults{$host}{'temp'};
        say "battery status(2=normal): " . $snmpresults{$host}{'battstatus'};
        say "battery capacity(%): " . $snmpresults{$host}{'battcapacity'};
        say "battery voltage: " . $snmpresults{$host}{'battvoltage'};
        say "input line voltage: " . $snmpresults{$host}{'inputvoltage'};
        say "output voltage: " . $snmpresults{$host}{'outputvoltage'};
        say "output current(A): " . $snmpresults{$host}{'outputcurrent'};
        say "redundancy (n+): " . $snmpresults{$host}{'redundancy'};
    }
    else {
        $snmpresults{error}    = 1;
        $snmpresults{errorstr} = "Unable to poll $host";
    }

    return %snmpresults;
}

sub nagios {

    my ( $numofargs, $host, $community ) = @_;
    my %snmpresults = snmppoll( $host, $community );

    if ( $snmpresults{$host}{'error'} != 0 ) {
        say "error: " . $snmpresults{$host}{'errorstr'};
        exit $snmpresults{$host}{'error'};
    }

    # PDU
    elsif ( $snmpresults{$host}{'type'} eq 'pdu' ) {

        # Check if overload or near overload
        if ( $snmpresults{$host}{'phasecurrent'} >
            $snmpresults{$host}{'overload'} )
        {
            say "LOAD CRITICAL - Current: "
              . $snmpresults{$host}{'phasecurrent'}
              . "A > Overload: "
              . $snmpresults{$host}{'overload'} . "A";
            exit 2;
        }
        elsif ( $snmpresults{$host}{'phasecurrent'} >
            $snmpresults{$host}{'nearoverload'} )
        {
            say "LOAD WARNING - Current: "
              . $snmpresults{$host}{'phasecurrent'}
              . "A > NearOverload: "
              . $snmpresults{$host}{'nearoverload'} . "A";
            exit 1;
        }
        else {
            say "LOAD OK - Current: "
              . $snmpresults{$host}{'phasecurrent'}
              . "A < NearOverload: "
              . $snmpresults{$host}{'nearoverload'} . "A";
            exit 0;
        }
    }

    # UPS
    elsif ( $snmpresults{$host}{'type'} eq 'ups' ) {

        # Check runtime
        $snmpresults{$host}{'runtime'} =~ s/ minutes.*$//;
        if ( $snmpresults{$host}{'runtime'} < $snmpresults{$host}{'lowruntime'} ) {
            $snmpresults{error} = 2;
            $snmpresults{errorstr} = "Runtime is $snmpresults{$host}{'runtime'}";
            say "runtime is less than.."
        }
    }

    # Nothing to do
    else {
        say "Nothing to do.";
    }

}

sub graphite {
    while ( my ( $host, $community ) = each %hostlist ) {

        my $session = snmppoll( $host, $community );

        # If Graphite
        if ( $graphite_enable == 1 && $graphite_host ) {

            # Open connection
            print "sending $host data to graphite..";
            my $client = IO::Socket::INET->new(
                Proto    => 'tcp',
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
    say
      "		Single shot check mode of checking just a single host. If the community";
    say "		name is excluded, the config file will be checked or the \"public\"";
    say "		community will be used instead.";
    say "	check_apc graphite";
    say
      "		Check each host listed in config.pl and send the data into the Graphite";
    say "		host configured in 'config.pl'.";
    exit 1;
}

# EOF
