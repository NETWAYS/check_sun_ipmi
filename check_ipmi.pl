#!/usr/bin/perl
#-w
#
# nagios: -epn
#
# COPYRIGHT:
#  
# This software is Copyright (c) 2009 NETWAYS GmbH, Birger Schmidt
#                                <info@netways.de>
#      (Except where explicitly superseded by other copyright notices)
#
# Especially, as stated below, it is strongly based on the work of 
#       Albert Chu <chu11 at llnl dot gov>
# The main reason to derive from his work is to add performance data 
# output. And make the command line switches nagios plugin compliant.
# 
#
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from http://www.fsf.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.fsf.org.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to NETWAYS GmbH.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# this Software, to NETWAYS GmbH, you confirm that
# you are the copyright holder for those contributions and you grant
# NETWAYS GmbH a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
#
# Nagios and the Nagios logo are registered trademarks of Ethan Galstad.
#
#
#############################################################################
#
# nagios_ipmimonitoring.sh
#
# Author: 
#
# Albert Chu <chu11 at llnl dot gov>
#
# Description:
#
# This script can be used to monitor IPMI sensors in nagios via
# FreeIPMI's ipmimonitoring utility.  The Nominal, Warning, and
# Critical states of each sensor will be collected and counted.  The
# overall IPMI sensor status will be mapped into a Nagios status of
# OK, Warning, or Critical.  Details will then be output for Nagios to
# read.
#
# Options:
#
# -H - specify hostname(s) to remotely access (don't specify for inband)
# -M - specify an alternate ipmimonitoring location
# -m - specify additional ipmimonitoring arguments
# -v - print debug info
# -h - output help
#
# Environment Variables:
#
# IPMI_HOSTS - specify hostname(s) to remotely access (don't specify for inband)
# IPMIMONITORING_PATH - specify an alternate ipmimonitoring location
# IPMIMONITORING_ARGS - specify additional ipmimonitoring arguments
#
# Setup Notes:
#
# Specify the remote hosts you wish to access IPMI information from
# via the -H option or IPMI_HOSTS environment variable.  If you wish
# only to monitor the local node, do not specify an ipmi host.  The
# input to the -h option is passed directly to ipmimonitoring.  So you
# may specify anything the ipmimonitoring tool accepts including
# hostranged (i.e. foo[0-127]) or comma separated
# (i.e. foo0,foo1,foo2,foo3) inputs.  If you wish to monitor both
# remote and local system, remember to specify one of the hosts as
# "localhost".  Most will probably want to monitor just one host (get
# the IPMI status for each individual machine being monitored),
# however more than one host can be analyzed for a collective result.
#
# If stored in a non-default location the -M option or
# IPMIMONITORING_PATH environment variable must be specified to
# determine the ipmimonitoring location.
#
# In order to specify non-defaults for ipmimonitoring use the -m
# argument or IPMIMONITORING_ARGS environment variable.  Typically,
# this option is necessary for non-default communication information
# or authentication information (i.e. driver path, driver type,
# username, password, etc.).  Non-default communication information
# can also be stored in the FreeIPMI configuration file.  This is the
# suggested method because passwords and other sensitive information
# could show up in ps(1).  If you wish to limit the sensors being
# monitored, you can also specify which record-ids are to be monitored
# (-s option).
#
# The default session timeout length in ipmimonitoring is 20 seconds.
# We would recommend that IPMI not be monitored more frequently than
# that.
#
#############################################################################

use strict;

use Getopt::Std;
use IPC::Open3;
use IO::Socket;

my $debug = 0;

my $IPMI_HOSTS = undef;
my $IPMIMONITORING_PATH = "/usr/local/sbin/ipmimonitoring";
my $IPMIMONITORING_ARGS = "";

my $IPMIMONITORING_OUTPUT;
my @IPMIMONITORING_OUTPUT_LINES;
my $line;

my $cmd;

my $num_output = 0;
my $warning_num = 0;
my $critical_num = 0;
my $fatal_error = 0;

my @msg						= ();
my @perfdata				= ();

our @nagiosstate = ('OK', 'WARNING', 'CRITICAL', 'UNKNOWN');

sub usage
{
    my $prog = $0;
    print "Usage: $prog -H <hostname(s)> -M <path> -m <sensors arguments> -v -h\n";
    print "  -H specify hostname(s) to remotely access\n";
    print "  -M specify an alternate ipmimonitoring path\n";
    print "  -m specify additional ipmimonitoring arguments\n";
    print "  -v be verbose/print debug info\n";
    print "  -h output help\n";
    exit 0;
}

if (!getopts("H:M:m:vh"))
{
    usage();
}

if (defined($main::opt_h))
{
    usage();
}

if (defined($main::opt_H))
{
    $IPMI_HOSTS = $main::opt_H;
}

if (defined($main::opt_M))
{
    $IPMIMONITORING_PATH = $main::opt_M;
}

if (defined($main::opt_m))
{
    $IPMIMONITORING_ARGS = $main::opt_m;
}

if (defined($main::opt_v))
{
    $debug = 1;
}

if ($ENV{"IPMI_HOSTS"})
{
    $IPMI_HOSTS = $ENV{"IPMI_HOSTS"};
}

if ($ENV{"IPMIMONITORING_PATH"})
{
    $IPMIMONITORING_PATH = $ENV{"IPMIMONITORING_PATH"};
}

if ($ENV{"IPMIMONITORING_ARGS"})
{
    $IPMIMONITORING_ARGS = $ENV{"IPMIMONITORING_ARGS"};
}

if ($debug)
{
    print "IPMI_HOSTS=$IPMI_HOSTS\n";
    print "IPMIMONITORING_PATH=$IPMIMONITORING_PATH\n";
    print "IPMIMONITORING_ARGS=$IPMIMONITORING_ARGS\n";
}

if (!(-x $IPMIMONITORING_PATH))
{
    print "$IPMIMONITORING_PATH cannot be executed\n";
    exit(1);
}

if ($IPMI_HOSTS)
{
    $cmd = "$IPMIMONITORING_PATH $IPMIMONITORING_ARGS -h $IPMI_HOSTS --quiet-cache --sdr-cache-recreate --always-prefix";
}
else
{
    $cmd = "$IPMIMONITORING_PATH $IPMIMONITORING_ARGS --quiet-cache --sdr-cache-recreate --always-prefix"
}

sub executeCommand {
	my $command = join ' ', @_;
	($_ = qx{$command 2>&1}, $? >> 8);
}

my ($output, $rc) = executeCommand($cmd);
		
printResultAndExit(2, "ipmimonitoring system call failed with RC $rc.\n" . "OUTPUT: " . $output . "COMMAND: " . $cmd) unless ($rc == 0);

$IPMIMONITORING_OUTPUT = $output;

@IPMIMONITORING_OUTPUT_LINES = split(/\n/, $IPMIMONITORING_OUTPUT);

my %ipmihost=();

foreach $line (@IPMIMONITORING_OUTPUT_LINES)
{
    my $hostname;
    my $record_id;
    my $id_string;
    my $group;
    my $state;
    my $reading;
    my $unit;
    my $id_string_state;

    my $output_str;

    # skip header line
    if ($line =~ "Record_ID")
    {
        next;
    }

    if ($line =~ /(.+)\:\s*(\d+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*$/)
    {
        $hostname = $1;
        $record_id = $2;
        $id_string = $3;
        $group = $4;
        $state = $5;
        $unit = $6;
        $reading = $7;
        if ($debug)
        {
            print ("Parsed: ",
				$hostname, "\t",
				$record_id, "\t",
				$id_string, "\t",
				$group, "\t",
				$state, "\t",
				$unit, "\t",
				$reading, "\n");
        }
	}	
    else
    {
        print "Not parsable: $line";
        $fatal_error++;
        next;
    }

    $id_string =~ tr# |/#_#;

    if ($unit eq 'N/A') 
    {
    	if ($group eq 'Fan') { $unit = 'RPM;0;0;0;0'; } else { $unit = ''; }
    }
	else
	{
    	$unit .= ';0;0;0;0';
	}

	push (@perfdata, "$id_string=\"${reading}${unit}\"");

    if ($state eq 'Nominal') 
    {
		if ($ipmihost{$hostname}{$group} ne 'WARNING' or $ipmihost{$hostname}{$group} ne 'CRITICAL') { $ipmihost{$hostname}{$group}='OK' };
        next;
    }

    if ($state eq 'Warning')
    {
        $warning_num++;
        $output_str = 'WARNING';
		if ($ipmihost{$hostname}{$group} ne 'CRITICAL') { $ipmihost{$hostname}{$group}='WARNING' };
    }
    elsif ($state eq 'Critical')
    {
        $critical_num++;
        $output_str = 'CRITICAL';
		$ipmihost{$hostname}{$group}='CRITICAL';
    }
    else
    {
        print 'State not parsable\n';
        $fatal_error++;
        next;
    } 

    if ($num_output)
    {
        #print "; ";
    }
	push (@msg, "$id_string=\"$output_str\"");
    #print "$id_string - $output_str";
    $num_output++;
}

foreach my $name (sort keys %ipmihost) {
	foreach my $group (sort keys %{$ipmihost{$name}} ) { 
		push (@msg, "$group $ipmihost{$name}{$group}");
	}
}


sub printResultAndExit {

#	# stop timeout
#	alarm(0);

	# print check result and exit

	my $exitVal = shift;

	print "$nagiosstate[$exitVal]:";

	print " @_" if (@_);

	print "\n";

	exit($exitVal);
}

# Nagios Exit Codes
# 0 = OK
# 1 = WARNING
# 2 = CRITICAL
# 3 = UNKNOWN

if ($fatal_error)
{
    printResultAndExit (3, join(' - ', @msg) . "|" . join(' ', @perfdata));
}

if ($critical_num)
{
    printResultAndExit (2, join(' - ', @msg) . "|" . join(' ', @perfdata));
}

if ($warning_num)
{
    printResultAndExit (1, join(' - ', @msg) . "|" . join(' ', @perfdata));
}

printResultAndExit (0, join(' - ', @msg) . "|" . join(' ', @perfdata));

