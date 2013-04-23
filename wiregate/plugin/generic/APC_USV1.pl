# 2011-12-08 V1.1
# Simple plugin to interface apcupsd
# apcupsd muss installiert und eingerichtet sein (seriell oder SNMP), 
# kann jedoch auch remote (Win/Linux/Mac) laufen
# mehr unter http://knx-user-forum.de/wiregate/14764-usv-einbinden-2.html#post194641
# Beispiel fuer komplette Ausgabe von apcaccess und apcupsd.conf am Ende

##################
### DEFINITION ###
##################

$plugin_info{$plugname.'_cycle'} = 120;

my $graph = 1; # Global : 1 = RRD-Dateien werden vom Plugin erstellt (besser: collectd verwenden, siehe Forum)
my $upsname = "USV1-SU420"; # Name (Prefix) fuer die RRDs

# Hash fuer UPS-Werte/Gruppenadressen-Zuordnung
# Die Reihenfolge spielt keine Rolle, DPT5 (Scaling 0-100%) fuer Prozentwerte, 
#  DPT9 (2byte float) fuer andere, DPT16 fuer Plaintext-Ausgabe
#  Eintraege koennen einfach hinzugefuegt/weggelassen werden, wenn kein GA-Versand erwuenscht leer lassen
my %items = ( 
    'STATUS' => { 
        'GA' => '13/2/11', 
        'DPT' => '16', 
        'Graph' => 0
    },
    'LINEV' => { 
        'GA' => '', 
        'DPT' => '9', 
        'Graph' => 1
    },
    'LOADPCT' => { 
        'GA' => '13/2/13', 
        'DPT' => '5', 
        'Graph' => 1
    },
    'BCHARGE' => { 
        'GA' => '13/2/14', 
        'DPT' => '5', 
        'Graph' => 1
    },
    'TIMELEFT' => { 
        'GA' => '13/2/15', 
        'DPT' => '9', 
        'Graph' => 1
    },
    'OUTPUTV' => { 
        'GA' => '', 
        'DPT' => '9', 
        'Graph' => 0
    },
    'ITEMP' => { 
        'GA' => '', 
        'DPT' => '9', 
        'Graph' => 1
    },
    'LINEFREQ' => { 
        'GA' => '', 
        'DPT' => '9', 
        'Graph' => 1
    },
    'LASTXFER' => { 
        'GA' => '', 
        'DPT' => '16', 
        'Graph' => 0
    },
    'TONBATT' => { 
        'GA' => '', 
        'DPT' => '9', 
        'Graph' => 0
    },
    'CUMONBATT' => { 
        'GA' => '', 
        'DPT' => '9', 
        'Graph' => 0
    },
    'SELFTEST' => { 
        'GA' => '', 
        'DPT' => '16', 
        'Graph' => 0
    },
    # STATFLAG ist speziell, es gibt das Status-Bytes (Register0) als DPT5.010
    # und die einzelnen Zustaende auf sep. 1Bit GAs aus
    'STATFLAG' => { 
        'GA_byte1' => '13/2/40', 
        'DPT' => '5.010',
        'GA_online' => '13/2/41',
        'GA_onbatt' => '13/2/42',
        'GA_overload' => '13/2/43',
        'GA_battlow' => '13/2/44',
        'GA_replacebatt' => '13/2/45',
    },
    # ERROR wird gesendet wenn die Abfrage nicht geht
    'ERROR' => { 
        'GA' => '13/2/20', 
        'DPT' => '1',
        'Graph' => 0,
        'Value' => '1', # Wert bei Fehler
    },
);

# Hostname/Port wo apcupsd laeuft
my $host = "localhost";
my $port = "3551";

my $debug_log = 1;                # Debug-Ausgabe in Plugin-Log bei Fehlern

#######################
### ENDE DEFINITION ###
#######################


my @out = `apcaccess status $host:$port`;
if ($out[0] =~ /^APC/) {
    foreach my $line (@out) {
        $line =~ s/\r|\n|\s//g; # remove CR/LF & Space
        my ($item,$value) = split(/:/,$line,2);
        if ($items{$item}) {
            if ($items{$item}{GA}) {
                if ($value =~ /([0-9]*\.?[0-9]+)(.*)/) {
                    knx_write($items{$item}{GA},$1,$items{$item}{DPT});
                } elsif ($items{$item}{DPT} == 16) {
                    knx_write($items{$item}{GA},$value,$items{$item}{DPT});
                }
            }
            if ($items{$item} and $item eq "STATFLAG" and $value =~ /(0x[0-9A-F]*)(.*)/) {
                my $statbyte1 = hex($1);
                $statbyte1 &= 0xFF;
                my $online = ($statbyte1 & 0x08) >> 3;
                my $onbatt = ($statbyte1 & 0x10) >> 4;
                my $overload  = ($statbyte1 & 0x20) >> 5;
                my $battlow  = ($statbyte1 & 0x40) >> 6;
                my $replacebatt  = ($statbyte1 & 0x80) >> 7;
                if ($items{$item}{GA_byte1}) {
                    knx_write($items{$item}{GA_byte1},$statbyte1,$items{$item}{DPT});
                }
                if ($items{$item}{GA_online}) {
                    knx_write($items{$item}{GA_online},$online,1);                
                }
                if ($items{$item}{GA_onbatt}) {
                    knx_write($items{$item}{GA_onbatt},$onbatt,1);                
                }
                if ($items{$item}{GA_overload}) {
                    knx_write($items{$item}{GA_overload},$overload,1);                
                }
                if ($items{$item}{GA_battlow}) {
                    knx_write($items{$item}{GA_battlow},$battlow,1);                
                }
                if ($items{$item}{GA_replacebatt}) {
                    knx_write($items{$item}{GA_replacebatt},$replacebatt,1);                
                }
            }
            if ($items{$item}{Graph} and $graph and $value =~ /([0-9]*\.?[0-9]+)(.*)/) {
                update_rrd($upsname,"_$item",$1);
            }
        }
    }
} else {
    # Fehler, mach was damit?
    knx_write($items{ERROR}{GA},$items{ERROR}{Value},$items{ERROR}{DPT});
    return "Error! got: @out" if $debug_log;
}
return;


### BEISPIELE ### (Ausgabe `apcaccess`)
# siehe auch "man apcupsd"

# Seriell
#wiregate1:~# apcaccess 
#APC      : 001,051,1289
#DATE     : Sat Apr 13 13:19:07 CEST 2013
#HOSTNAME : wiregate1
#RELEASE  : 3.14.4
#VERSION  : 3.14.4 (18 May 2008) debian
#UPSNAME  : USV1-SU420
#CABLE    : Custom Cable Smart
#MODEL    : Smart-UPS 420   
#UPSMODE  : Stand Alone
#STARTTIME: Mon Mar 11 17:55:13 CET 2013
#STATUS   : ONLINE 
#LINEV    : 230.4 Volts
#LOADPCT  :  20.8 Percent Load Capacity
#BCHARGE  : 100.0 Percent
#TIMELEFT :  25.0 Minutes
#MBATTCHG : 10 Percent
#MINTIMEL : 5 Minutes
#MAXTIME  : 0 Seconds
#MAXLINEV : 233.2 Volts
#MINLINEV : 230.4 Volts
#OUTPUTV  : 233.2 Volts
#SENSE    : High
#DWAKE    : 000 Seconds
#DSHUTD   : 180 Seconds
#DLOWBATT : 02 Minutes
#LOTRANS  : 208.0 Volts
#HITRANS  : 253.0 Volts
#RETPCT   : 000.0 Percent
#ALARMDEL : Low Battery
#BATTV    : 13.8 Volts
#LINEFREQ : 50.0 Hz
#LASTXFER : Automatic or explicit self test
#NUMXFERS : 2
#XONBATT  : Tue Mar 12 12:19:41 CET 2013
#TONBATT  : 0 seconds
#CUMONBATT: 3 seconds
#XOFFBATT : Tue Mar 12 12:19:43 CET 2013
#LASTSTEST: Tue Mar 12 12:19:41 CET 2013
#SELFTEST : NO
#STESTI   : 168
#STATFLAG : 0x07000008 Status Flag
#REG1     : 0x00 Register 1
#REG2     : 0x00 Register 2
#REG3     : 0x00 Register 3
#MANDATE  : 09/22/99
#SERIALNO : NS9939240943
#BATTDATE : 07/09/10
#NOMOUTV  : 230 Volts
#NOMBATTV :  12.0 Volts
#FIRMWARE : 21.4.I
#APCMODEL : DWI
#END APC  : Sat Apr 13 13:19:59 CEST 2013
#
#
# SNMP-Adapter
#root@wiregate231:~# apcaccess 
#APC      : 001,049,1173
#DATE     : Sat Apr 13 13:18:53 CEST 2013
#HOSTNAME : wiregate231
#RELEASE  : 3.14.4
#VERSION  : 3.14.4 (18 May 2008) debian
#UPSNAME  : SU700EDV
#CABLE    : Custom Cable Smart
#MODEL    : SNMP UPS Driver
#UPSMODE  : Stand Alone
#STARTTIME: Mon Sep 10 20:52:34 CEST 2012
#STATUS   : ONLINE 
#LINEV    : 236.0 Volts
#LOADPCT  :  28.0 Percent Load Capacity
#BCHARGE  : 100.0 Percent
#TIMELEFT :  24.0 Minutes
#MBATTCHG : 10 Percent
#MINTIMEL : 5 Minutes
#MAXTIME  : 0 Seconds
#MAXLINEV : 240.0 Volts
#MINLINEV : 235.0 Volts
#OUTPUTV  : 237.0 Volts
#SENSE    : Medium
#DWAKE    : 060 Seconds
#DSHUTD   : 020 Seconds
#DLOWBATT : 02 Minutes
#LOTRANS  : 196.0 Volts
#HITRANS  : 253.0 Volts
#RETPCT   : 000.0 Percent
#ITEMP    : 44.0 C Internal
#ALARMDEL : 5 seconds
#LINEFREQ : 50.0 Hz
#LASTXFER : Automatic or explicit self test
#NUMXFERS : 0
#TONBATT  : 0 seconds
#CUMONBATT: 0 seconds
#XOFFBATT : N/A
#SELFTEST : OK
#STESTI   : biweekly
#STATFLAG : 0x07000008 Status Flag
#DIPSW    : 0x00 Dip Switch
#MANDATE  : 05/05/00
#SERIALNO : NS0019241899
#BATTDATE : 05/01/11
#NOMOUTV  : 230 Volts
#NOMPOWER : 0 Watts
#EXTBATTS : 0
#BADBATTS : 0
#FIRMWARE : 50.11.I
#APCMODEL : SMART-UPS 700
#END APC  : Sat Apr 13 13:19:37 CEST 2013

# SNMP-Adapter
#wiregate1:~# apcaccess status elab14
#APC      : 001,052,1287
#DATE     : Sat Apr 13 17:39:07 W. Europe Daylight Time 2013
#HOSTNAME : elab14
#RELEASE  : 3.14.0
#VERSION  : 3.14.0 (9 February 2007) Win32
#UPSNAME  : ElabUSV1
#CABLE    : Ethernet Link
#MODEL    : SNMP UPS Driver
#UPSMODE  : Stand Alone
#STARTTIME: Wed Mar 27 10:30:48 W. Europe Standard Time 2013
#STATUS   : REPLACEBATT 
#LINEV    : 243.0 Volts
#LOADPCT  :  27.0 Percent Load Capacity
#BCHARGE  : 000.0 Percent
#TIMELEFT :   0.0 Minutes
#MBATTCHG : 5 Percent
#MINTIMEL : 10 Minutes
#MAXTIME  : 0 Seconds
#MAXLINEV : 243.0 Volts
#MINLINEV : 243.0 Volts
#OUTPUTV  : 227.0 Volts
#SENSE    : Low
#DWAKE    : 060 Seconds
#DSHUTD   : 300 Seconds
#DLOWBATT : 10 Minutes
#LOTRANS  : 176.0 Volts
#HITRANS  : 264.0 Volts
#RETPCT   : 000.0 Percent
#ITEMP    : 17.0 C Internal
#ALARMDEL : 30 seconds
#LINEFREQ : 50.0 Hz
#LASTXFER : Automatic or explicit self test
#NUMXFERS : 0
#TONBATT  : 0 seconds
#CUMONBATT: 0 seconds
#XOFFBATT : N/A
#SELFTEST : NG
#STESTI   : biweekly
#STATFLAG : 0x07000080 Status Flag
#DIPSW    : 0x00 Dip Switch
#REG1     : 0x00 Register 1
#REG2     : 0x00 Register 2
#REG3     : 0x00 Register 3
#MANDATE  : 04/01/97
#SERIALNO : 81012965
#BATTDATE : 04/01/97
#NOMOUTV  : 230
#NOMINV   : 000
#EXTBATTS : 2
#BADBATTS : 0
#FIRMWARE : 5ZI
#APCMODEL : MATRIX 5000
#END APC  : Sat Apr 13 17:39:46 W. Europe Daylight Time 2013

## Smart-UPS 1500 via USB
#root@wiregateXXX:~# apcaccess 
#APC      : 001,042,1046
#DATE     : Tue Apr 23 09:05:24 CEST 2013
#HOSTNAME : wiregate915
#RELEASE  : 3.14.4
#VERSION  : 3.14.4 (18 May 2008) debian
#UPSNAME  : USV_Technik
#CABLE    : Custom Cable Smart
#MODEL    : Smart-UPS 1500 
#UPSMODE  : Stand Alone
#STARTTIME: Tue Apr 23 08:43:50 CEST 2013
#STATUS   : ONLINE 
#LINEV    : 239.0 Volts
#LOADPCT  :   0.0 Percent Load Capacity
#BCHARGE  : 100.0 Percent
#TIMELEFT : 322.0 Minutes
#MBATTCHG : 10 Percent
#MINTIMEL : 5 Minutes
#MAXTIME  : 0 Seconds
#OUTPUTV  : 239.0 Volts
#SENSE    : High
#DWAKE    : -01 Seconds
#DSHUTD   : 180 Seconds
#LOTRANS  : 208.0 Volts
#HITRANS  : 253.0 Volts
#RETPCT   : 015.0 Percent
#ITEMP    : 28.8 C Internal
#ALARMDEL : Always
#BATTV    : 27.5 Volts
#LINEFREQ : 50.0 Hz
#LASTXFER : No transfers since turnon
#NUMXFERS : 0
#TONBATT  : 0 seconds
#CUMONBATT: 0 seconds
#XOFFBATT : N/A
#SELFTEST : NO
#STATFLAG : 0x07000008 Status Flag
#SERIALNO : XXXXYYYYY
#BATTDATE : 2012-02-27
#NOMOUTV  : 230 Volts
#NOMBATTV :  24.0 Volts
#FIRMWARE : 653.13.I USB FW:4.2
#APCMODEL : Smart-UPS 1500 
#END APC  : Tue Apr 23 09:06:01 CEST 2013


### BEISPIELE ### apcupsd.conf
# Seriell (smart-cable), lokal:

#UPSNAME USV1-SU420
#UPSCABLE smart
#UPSTYPE apcsmart
#DEVICE /dev/usbserial-1-4.1
#LOCKFILE /var/lock
#ONBATTERYDELAY 6
#TIMEOUT 0
#ANNOY 300
#ANNOYDELAY 60
#NOLOGON disable
#KILLDELAY 0
#NETSERVER on
#NISIP 0.0.0.0
#NISPORT 3551
#EVENTSFILE /var/log/apcupsd.events
#EVENTSFILEMAX 10
#UPSCLASS standalone
#UPSMODE disable
#STATTIME 0
#STATFILE /var/log/apcupsd.status
#LOGSTATS off
#DATATIME 0
#
#
#apcupsd.conf Netzwerk / via SNMP-Adapter:
#UPSNAME SU700-EDV
#UPSCABLE smart
#UPSTYPE snmp
#DEVICE 172.17.2.66:161:APC:public
#LOCKFILE /var/lock
#SCRIPTDIR /etc/apcupsd
#PWRFAILDIR /etc/apcupsd
#NOLOGINDIR /etc
#ONBATTERYDELAY 6
#TIMEOUT 0
#ANNOY 300
#ANNOYDELAY 60
#NOLOGON disable
#KILLDELAY 0
#NETSERVER on
#NISIP 0.0.0.0
#NISPORT 3551
#EVENTSFILE /var/log/apcupsd.events
#EVENTSFILEMAX 100
#UPSCLASS standalone
#UPSMODE disable
#STATTIME 0
#STATFILE /var/log/apcupsd.status
#LOGSTATS off
#DATATIME 0
#

#apcupsd.conf via USB direkt:
#UPSCABLE smart
#UPSTYPE usb

