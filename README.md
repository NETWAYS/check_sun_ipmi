check_sun_ipmi
==============

This script can be used to monitor IPMI sensors in nagios via
FreeIPMI's ipmimonitoring utility.  The Nominal, Warning, and
Critical states of each sensor will be collected and counted.  The
overall IPMI sensor status will be mapped into a Nagios status of
OK, Warning, or Critical.  Details will then be output for Nagios to
read.

    
### Usage

    ./check_ipmi.pl -H <hostname(s)> -M <path> -m <sensors arguments> -v -h
      -H specify hostname(s) to remotely access
      -M specify an alternate ipmimonitoring path
      -m specify additional ipmimonitoring arguments
      -v be verbose/print debug info
      -h output help
