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
my @sensors_enabled = ();
my @sensors_available = ('current', 'humidity', 'input', 'leakage', 'power', 'temperature', 'voltage');

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

$mp->add_arg(
    spec    => 'sensor=s@',
    help    => sprintf('Enabled sensors: all, %s (Default: all)', join(', ', @sensors_available)),
    default => []
);

$mp->add_arg(
    spec    => 'input_warning=i@',
    help    => 'Report this input alarms as warning instead of critical.',
    default => []
);


$mp->getopts;

if(@{$mp->opts->sensor} == 0 || grep(/^all$/, @{$mp->opts->sensor})) {
    @sensors_enabled = @sensors_available;
} else {
    foreach my $name (@{$mp->opts->sensor}) {
        if(!grep(/$name/, @sensors_available)) {
            wrap_exit(UNKNOWN, sprintf('Unknown sensor type: %s', $name));
        }
    }
    @sensors_enabled = @{$mp->opts->sensor};
}

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
if($device_name eq 'CMCIII-HUM') {
    check_humidity($session, $device_id);
    check_temp($session, $device_id);
} elsif($device_name eq 'CMCIII-IO3') {
    check_io3_input($session, $device_id);
} elsif($device_name eq 'CMCIII-LEAK') {
    check_leak($session, $device_id);
} elsif($device_name eq 'PSM-M16') {
    check_psm_current($session, $device_id, 2, 3);
    check_psm_power($session, $device_id, 2, 3);
    check_psm_voltage($session, $device_id, 2, 3);
} elsif($device_name eq 'CMCIII-PU') {
    check_temp($session, $device_id);
} elsif($device_name eq 'CMCIII-TMP') {
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

sub check_humidity
{
    my ($session, $device_id) = @_;
    my $oid_base = '1.3.6.1.4.1.2606.7.4.2.2.1.11.' . $device_id;
    my $oid_value           = $oid_base . '.11';
    my $oid_high_critical   = $oid_base . '.12';
    my $oid_high_warning    = $oid_base . '.13';
    my $oid_low_warning     = $oid_base . '.14';
    my $oid_low_critical    = $oid_base . '.15';

    if (!grep(/^humidity$/, @sensors_enabled)) {
        return;
    }

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
        label     => 'humidity',
        value     => $value,
        uom       => '%',
        threshold => $threshold
    );
    $mp->add_message($threshold->get_status($value), 'Humidity: ' . $value . '%');
}

sub check_io3_input
{
    my ($session, $device_id) = @_;
    my $oid_base_text         = '1.3.6.1.4.1.2606.7.4.2.2.1.10.' . $device_id;
    my $oid_base_value        = '1.3.6.1.4.1.2606.7.4.2.2.1.11.' . $device_id;
    my %input_warning         = map { $_ => 1 } @{$mp->opts->input_warning};

    if (!grep(/^input$/, @sensors_enabled)) {
        return;
    }

    for (my $i=0; $i < 8; $i++) {
        my $id_label = $i * 6 + 1;
        my $id_status = $i * 6 + 5;
        my $oid_label        = $oid_base_text . ".$id_label";
        my $oid_status_text  = $oid_base_text . ".$id_status";
        my $oid_status_value = $oid_base_value . ".$id_status";
        $result = $session->get_request(
            -varbindlist => [
                $oid_status_text,
                $oid_status_value,
                $oid_label
            ]
        );

        my $label = $result->{$oid_label};
        my $status_text = $result->{$oid_status_text};
        my $status_value = $result->{$oid_status_value};
        my $result_status = OK;
        if ($status_value == 5) {
            if (exists($input_warning{$i + 1})) {
                $result_status = WARNING;
            } else {
                $result_status = CRITICAL;
            }
        }
        $mp->add_message($result_status, sprintf('%s: %s', $label, $status_text));
    }
}

sub check_leak
{
    my ($session, $device_id) = @_;
    my $oid_base_text    = '1.3.6.1.4.1.2606.7.4.2.2.1.10.' . $device_id;
    my $oid_base_value   = '1.3.6.1.4.1.2606.7.4.2.2.1.11.' . $device_id;
    my $oid_status_text  = $oid_base_text . '.4';
    my $oid_status_value = $oid_base_value . '.4';
    my $result_status    = OK;

    if (!grep(/^leakage$/, @sensors_enabled)) {
        return;
    }

    $result = $session->get_request(
        -varbindlist => [
            $oid_status_text,
            $oid_status_value
        ]
    );
    my $status_text = $result->{$oid_status_text};
    my $status_value = $result->{$oid_status_value};
    if ($status_value != 4) {
        $result_status = CRITICAL;
    }

    $mp->add_message($result_status, 'Status: ' . $status_text);
}

sub check_psm_current
{
    my ($session, $device_id, $circuits, $lines) = @_;
    my $oid_base            = '1.3.6.1.4.1.2606.7.4.2.2.1.11.' . $device_id;
    my @messages = ();
    my $status = OK;

    if (!grep(/^current$/, @sensors_enabled)) {
        return;
    }

    for(my $circuit = 1; $circuit <= $circuits; $circuit++) {
        for(my $line = 1; $line <= $lines; $line++) {
            my @suboids = ();

            @suboids = (44, 45, 46, 47, 48) if $circuit == 1 && $line == 1;
            @suboids = (53, 54, 55, 56, 57) if $circuit == 1 && $line == 2;
            @suboids = (62, 63, 64, 65, 66) if $circuit == 1 && $line == 3;
            @suboids = (134, 135, 136, 137, 138) if $circuit == 2 && $line == 1;
            @suboids = (143, 144, 145, 146, 147) if $circuit == 2 && $line == 2;
            @suboids = (152, 153, 154, 155, 156) if $circuit == 2 && $line == 3;

            wrap_exit(UNKNOWN, sprintf('Unkonwn circuit %u and line %u', $circuit, $line)) if (!@suboids);

            my $oid_value           = $oid_base . '.' . $suboids[0];
            my $oid_high_critical   = $oid_base . '.' . $suboids[1];
            my $oid_high_warning    = $oid_base . '.' . $suboids[2];
            my $oid_low_warning     = $oid_base . '.' . $suboids[3];
            my $oid_low_critical    = $oid_base . '.' . $suboids[4];

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
                label     => sprintf('c%ul%u_current', $circuit, $line),
                value     => $value,
                threshold => $threshold
            );
            $status = $threshold->get_status($value) if ($threshold->get_status($value) > $status);
            push(@messages, sprintf('C%uL%u: %.1fA', $circuit, $line, $value))
        }
    }
    $mp->add_message(
        $status,
        sprintf('Current (%s)', join(', ', @messages))
    );
}

sub check_psm_power
{
    my ($session, $device_id, $circuits, $lines) = @_;
    my $oid_base            = '1.3.6.1.4.1.2606.7.4.2.2.1.11.' . $device_id;
    my @messages = ();

    if (!grep(/^power$/, @sensors_enabled)) {
        return;
    }

    my $oid_value;
    my @suboids;
    my $value;
    for(my $circuit = 1; $circuit <= $circuits; $circuit++) {
        for(my $line = 1; $line <= $lines; $line++) {
            @suboids = ();

            @suboids = (73) if $circuit == 1 && $line == 1;
            @suboids = (74) if $circuit == 1 && $line == 2;
            @suboids = (75) if $circuit == 1 && $line == 3;
            @suboids = (163) if $circuit == 2 && $line == 1;
            @suboids = (164) if $circuit == 2 && $line == 2;
            @suboids = (165) if $circuit == 2 && $line == 3;

            wrap_exit(UNKNOWN, sprintf('Unkonwn circuit %u and line %u', $circuit, $line)) if (!@suboids);

            $oid_value = $oid_base . '.' . $suboids[0];

            $result = $session->get_request(
                -varbindlist => [$oid_value]
            );

            $value = $result->{$oid_value};

            $mp->add_perfdata(
                label     => sprintf('c%ul%u_power', $circuit, $line),
                value     => $value
            );
            push(@messages, sprintf('L%u: %.1fW', $line, $value))
        }
        @suboids = ();
        @suboids = (5) if $circuit == 1;
        @suboids = (95) if $circuit == 2;

        $oid_value = $oid_base . '.' . $suboids[0];
        $result = $session->get_request(
            -varbindlist => [$oid_value]
        );

        $value = $result->{$oid_value};

        $mp->add_perfdata(
            label => sprintf('c%u_power', $circuit),
            value => $value
        );
        $mp->add_message(
            OK,
            sprintf('Power C%u: %.1fW (%s)', $circuit, $value, join(', ', @messages))
        );
    }

}

sub check_psm_voltage
{
    my ($session, $device_id, $circuits, $lines) = @_;
    my $oid_base            = '1.3.6.1.4.1.2606.7.4.2.2.1.11.' . $device_id;
    my @messages = ();
    my $status = OK;

    if (!grep(/^voltage$/, @sensors_enabled)) {
        return;
    }

    for(my $circuit = 1; $circuit <= $circuits; $circuit++) {
        for(my $line = 1; $line <= $lines; $line++) {
            my @suboids = ();

            @suboids = (17, 18, 19, 20, 21) if $circuit == 1 && $line == 1;
            @suboids = (26, 27, 28, 29, 30) if $circuit == 1 && $line == 2;
            @suboids = (35, 36, 37, 38, 39) if $circuit == 1 && $line == 3;
            @suboids = (107, 108, 109, 110, 111) if $circuit == 2 && $line == 1;
            @suboids = (116, 117, 118, 119, 120) if $circuit == 2 && $line == 2;
            @suboids = (125, 126, 127, 128, 129) if $circuit == 2 && $line == 3;

            wrap_exit(UNKNOWN, sprintf('Unkonwn circuit %u and line %u', $circuit, $line)) if (!@suboids);

            my $oid_value           = $oid_base . '.' . $suboids[0];
            my $oid_high_critical   = $oid_base . '.' . $suboids[1];
            my $oid_high_warning    = $oid_base . '.' . $suboids[2];
            my $oid_low_warning     = $oid_base . '.' . $suboids[3];
            my $oid_low_critical    = $oid_base . '.' . $suboids[4];

            $result = $session->get_request(
                -varbindlist => [
                    $oid_value,
                    $oid_high_critical,
                    $oid_high_warning,
                    $oid_low_critical,
                    $oid_low_warning
                ]
            );

            my $value = $result->{$oid_value} / 10;
            my $high_critical = $result->{$oid_high_critical} / 10;
            my $high_warning = $result->{$oid_high_warning} / 10;
            my $low_critical = $result->{$oid_low_critical} / 10;
            my $low_warning = $result->{$oid_low_warning} / 10;

            my $threshold = Monitoring::Plugin::Threshold->set_thresholds(
                warning   => $high_warning,
                critical  => $high_critical
            );

            $mp->add_perfdata(
                label     => sprintf('c%ul%u_voltage', $circuit, $line),
                value     => $value,
                threshold => $threshold
            );
            $status = $threshold->get_status($value) if ($threshold->get_status($value) > $status);
            push(@messages, sprintf('C%uL%u: %.1fV', $circuit, $line, $value))
        }
    }
    $mp->add_message(
        $status,
        sprintf('Voltages (%s)', join(', ', @messages))
    );
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

    if (!grep(/^temperature$/, @sensors_enabled)) {
        return;
    }

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
        threshold => $threshold
    );
    $mp->add_message($threshold->get_status($value), 'Temperature: ' . $value . '°C');
}
