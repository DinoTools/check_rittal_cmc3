#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use Class::Load qw(try_load_class is_class_loaded);

use Net::SNMP;

use constant OK         => 0;
use constant WARNING    => 1;
use constant CRITICAL   => 2;
use constant UNKNOWN    => 3;
use constant DEPENDENT  => 4;

my $pkg_nagios_available = 0;
my $pkg_monitoring_available = 0;

BEGIN {
    $pkg_nagios_available = try_load_class('Nagios::Plugin');
    $pkg_monitoring_available = try_load_class('Monitoring::Plugin');
    if($pkg_monitoring_available == 1) {
        require Monitoring::Plugin;
        require Monitoring::Plugin::Functions;
        require Monitoring::Plugin::Threshold;
    } elsif ($pkg_nagios_available == 1) {
        require Nagios::Plugin;
        require Nagios::Plugin::Functions;
        require Nagios::Plugin::Threshold;
        *Monitoring::Plugin:: = *Nagios::Plugin::;
    }
}

my $mp = Monitoring::Plugin->new(
    shortname => "check_rittal_cmc3",
    usage => ""
);

$mp->add_arg(
    spec    => 'community|C=s',
    help    => 'Community string (Default: public)',
    default => 'public'
);

$mp->add_arg(
    spec => 'hostname|H=s',
    help => '',
    required => 1
);

$mp->add_arg(
    spec => 'device|D=s',
    help => ''
);

$mp->add_arg(
    spec    => 'scan',
    help    => '',
    default => 0
);


$mp->getopts;

#Open SNMP Session
my ($session, $error) = Net::SNMP->session(
    -hostname => $mp->opts->hostname,
    -version => 'snmpv2c',
    -community => $mp->opts->community,
);

if (!defined($session)) {
    wrap_exit(UNKNOWN, $error)
}

my $cmcIIINumberOfDevs  = '1.3.6.1.4.1.2606.7.4.1.1.2.0';
my $cmcIIIDevName       = "1.3.6.1.4.1.2606.7.4.1.2.1.2.";
my $cmcIIIDevType       = "1.3.6.1.4.1.2606.7.4.1.2.1.4.";

my $result;
my $device_name;
my $device_type;

$result = $session->get_request(
    -varbindlist => [$cmcIIINumberOfDevs]
);

my $device_number = $result->{$cmcIIINumberOfDevs};

if($mp->opts->scan) {
    print(" ID | Name \n");
    print("----|----------------------\n");
    for (my $i = 1; $i <= $device_number; $i++) {
        $result = $session->get_request(
            -varbindlist => [
                $cmcIIIDevName . $i,
                $cmcIIIDevType . $i
            ]
        );
        $device_name = $result->{$cmcIIIDevName . $i};
        $device_type = $result->{$cmcIIIDevType . $i};
        printf("% 3u | %-16s\n", $i, $device_name);
    }
    exit(UNKNOWN);
}

if($mp->opts->device < 1 || $mp->opts->device > $device_number) {
    wrap_exit( UNKNOWN, 'Device ID not found');
}

my $device_id = $mp->opts->device;

$result = $session->get_request(
    -varbindlist => [
        $cmcIIIDevName . $device_id,
        $cmcIIIDevType . $device_id
    ]
);

if (!defined($result)) {
    my $error_msg = $session->error;
    $session->close;
    wrap_exit(UNKNOWN, $error_msg)
}

$device_name = $result->{$cmcIIIDevName . $device_id};
$device_type = $result->{$cmcIIIDevType . $device_id};

if($device_name eq 'CMCIII-TMP') {
    check_temp($session, $device_id);
} else {
    wrap_exit( UNKNOWN, 'Unsupported device: Name: ' . $device_name . ' Type: ' . $device_type);
}

my ($code, $message) = $mp->check_messages();
wrap_exit($code, $message);


sub wrap_exit
{
    if($pkg_monitoring_available == 1) {
        $mp->plugin_exit( @_ );
    } else {
        $mp->nagios_exit( @_ );
    }
}

sub check_temp
{
    my ($session, $device_id) = @_;
    my $oid_base = '1.3.6.1.4.1.2606.7.4.2.2.1.11.' . $device_id;
    my $oid_value           = $oid_base . '.2';
    my $oid_high_critical   = $oid_base . '.3';
    my $oid_high_warning    = $oid_base . '.4';
    my $oid_low_warning     = $oid_base . '.5';
    my $oid_low_critical    = $oid_base . '.6';
    $result = $session->get_request(
        -varbindlist => [
            $oid_value,
            $oid_high_critical,
            $oid_high_warning,
            $oid_low_critical,
            $oid_low_warning
        ]
    );

    my $value = $result->{$oid_value} / 100;
    my $high_critical = $result->{$oid_high_critical} / 100;
    my $high_warning = $result->{$oid_high_warning} / 100;
    my $low_critical = $result->{$oid_low_critical} / 100;
    my $low_warning = $result->{$oid_low_warning} / 100;

    my $threshold = Monitoring::Plugin::Threshold->set_thresholds(
        warning   => $high_warning,
        critical  => $high_critical
    );

    $mp->add_perfdata(
        label     => 'temperature',
        value     => $value,
        uom       => 'C',
        threshold => $threshold
    );
    $mp->add_message($threshold->get_status($value), 'Temperature: ' . $value . '°C');
}
