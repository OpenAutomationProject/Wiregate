######################################################################################
# Plugin StiebelEltron-LWZ-x04
# V0.2 2015-01-11
# Lizenz: GPLv2
# Autor: krumboeck (http://knx-user-forum.de/members/krumboeck.html)
#
# Benötigt:
# * CAN Bus Adapter
# * Kernel Update für CAN Bus
# * iproute2 für CAN Bus Konfiguration
#
# ACHTUNG: Es handelt sich hier um ein experimentelles Plugin!!
# Es wird keine Haftung für Beschädigungen aller Art übernommen!
#
# Die verwendeten Variablen basieren auf Reverse Engineering und
# sind weder geprüft noch ausreichend getestet.
#
# TIPP: Bevor sie eine Variable beschreiben, lesen sie diese bitte
# ein und überprüfen sie die Korrektheit des Wertes.
#
# Changelog:
# 2014-09-13  0.1  Initiale Version veröffentlicht
# 2015-01-11  0.2  Unterstützung von negativen Temperatur Werten
#                  Unterstützung von Gruppierten Werten
#
#
######################################################################################


use warnings;
use strict;
use Socket qw(SOCK_RAW);
use Convert::Binary::C;

######################
# Startevent ermitteln
######################
my $event=undef;
if (!$plugin_initflag) {
	$event = 'restart';
} elsif ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'}) {
	$event = 'modified'; # Plugin modifiziert
} elsif (%msg) {
	$event = 'knx'; # KNX/EIB Bustraffic
} elsif ($fh) {
	$event = 'socket'; # Netzwerktraffic
} else {
	$event = 'cycle'; # Zyklus
}

#########################
### BEGINN DEFINITION ###
#########################

my $socknum = 500; # Eindeutige Nummer des Sockets

use constant {
        PF_CAN                  => 29,
        AF_CAN                  => 29,
        CAN_RAW                 => 1,
        SOL_CAN_BASE            => 100,
        SOL_CAN_RAW             => 101,
        CAN_RAW_FILTER          => 1,
        CAN_RAW_ERR_FILTER      => 2,
        CAN_RAW_LOOPBACK        => 3,
        CAN_RAW_RECV_OWN_MSGS   => 4,
        # special address description flags for the CAN_ID
        CAN_EFF_FLAG            => 0x80000000, # EFF/SFF is set in the MSB
        CAN_RTR_FLAG            => 0x40000000, # remote transmission request
        CAN_ERR_FLAG            => 0x20000000, # error frame
        # valid bits in CAN ID for frame formats
        CAN_SFF_MASK            => 0x000007FF, # standard frame format (SFF)
        CAN_EFF_MASK            => 0x1FFFFFFF, # extended frame format (EFF)
        CAN_ERR_MASK            => 0x1FFFFFFF, # omit EFF, RTR, ERR flags
        # bits/ioctls.h
        SIOCGIFINDEX            => 0x8933,
        # LWZ protocol
        TARGET_SYSTEM			=> 0x03,
        TARGET_HEIZKREIS		=> 0x06,
        TARGET_SENSOR			=> 0x08,
        TARGET_DISPLAY			=> 0x0D,
        SOURCE_SYSTEM			=> 0x01,
        SOURCE_HEIZKREIS		=> 0x03,
        SOURCE_SENSOR			=> 0x04,
        SOURCE_DISPLAY			=> 0x06,
        HEIZKREIS_1				=> 0x01,
        HEIZKREIS_2				=> 0x02,
        TYPE_WRITE				=> 0x00,
        TYPE_REQUEST			=> 0x01,
        TYPE_RESPONSE			=> 0x02,
        TYPE_REGISTER			=> 0x06,
};

my $cstruct = "
typedef unsigned long canid_t;

#define ifr_name       ifr_ifrn.ifrn_name      /* interface name  */
#define ifr_ifindex    ifr_ifru.ifru_ivalue    /* interface index */
struct ifreq {
        union {
                char ifrn_name[16];
        } ifr_ifrn;
        union {
                int ifru_ivalue;
        } ifr_ifru;
};

struct can_frame {
        canid_t can_id;
        unsigned char can_dlc;
        unsigned char align[3];
        unsigned char data[8];
};

struct sockaddr_can {
        int can_family;
        int can_ifindex;
        union {
                struct { canid_t rx_id, tx_id; } tp;
        } can_addr;
};

struct can_filter {
        canid_t can_id;
        canid_t can_mask;
};

";

my @definitions;
push @definitions, { name => 'Warmwasser_Solltemperatur', valueId => 00, valueSubId => 0x03,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Heizkreis_Solltemperatur', valueId => 0x00, valueSubId => 0x04,
			writeTarget => undef, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Heizen_Raumtemperatur_Tag', valueId => 0x00, valueSubId => 0x05,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Heizen_Raumtemperatur_Nacht', valueId => 0x00, valueSubId => 0x08,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Außentemperatur', valueId => 0x00, valueSubId => 0x0C,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Vorlauftemperatur', valueId => 0x00, valueSubId => 0x0D,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Warmwasser_Temperatur', valueId => 0x00, valueSubId => 0x0E,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Heizkreis_Temperatur', valueId => 0x00, valueSubId => 0x0F,
			writeTarget => undef, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Raumtemperatur', valueId => 0x00, valueSubId => 0x11,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Raum-Solltemperatur', valueId => 0x00, valueSubId => 0x12,
			writeTarget => undef, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Warmwasser_Solltemperatur_Tag', valueId => 0x00, valueSubId => 0x13,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Verdampfertemperatur', valueId => 0x00, valueSubId => 0x14,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Rücklauftemperatur', valueId => 0x00, valueSubId => 0x16,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Kollektortemperatur', valueId => 0x00, valueSubId => 0x1A,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Maximale_Vorlauftemperatur_Heizkreis', valueId => 0x00, valueSubId => 0x27,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Heizkurfe_Maximaler_Sollwert', valueId => 0x00, valueSubId => 0x28,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Abtauen_Verdamper', valueId => 0x00, valueSubId => 0x60,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => undef, format => 'boolean', knxTyp => '1.002' };
push @definitions, { name => 'Luftfeuchtigkeit', valueId => 0x00, valueSubId => 0x75,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthPercent', knxTyp => '9.007' };
push @definitions, { name => 'Luftfeuchtigkeit_Hysterese', valueId => 0x00, valueSubId => 0x8E,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'percent', knxTyp => '8.010' };
push @definitions, { name => 'Dämpfung_Außentemperatur', valueId => 0x01, valueSubId => 0x0C,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'hour_byte', knxTyp => '7' };
push @definitions, { name => 'Heizkurve_Steigung', valueId => 0x01, valueSubId => 0x0E,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 1, format => 'percent', knxTyp => '8.010' };
push @definitions, { name => 'Raumeinfluss', valueId => 0x01, valueSubId => 0x0F,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Betriebsart', valueId => 0x01, valueSubId => 0x12,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Sommerbetrieb_Heizgrundeinstellung', valueId => 0x01, valueSubId => 0x16,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Ferienbeginn_Tag', valueId => 0x01, valueSubId => 0x1B,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'day_byte', knxTyp => '7' };
push @definitions, { name => 'Ferienbeginn_Monat', valueId => 0x01, valueSubId => 0x1C,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'month_byte', knxTyp => '7' };
push @definitions, { name => 'Ferienbeginn_Jahr', valueId => 0x01, valueSubId => 0x1D,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'year_byte', knxTyp => '7' };
push @definitions, { name => 'Ferienende_Tag', valueId => 0x01, valueSubId => 0x1E,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'day_byte', knxTyp => '7' };
push @definitions, { name => 'Ferienende_Monat', valueId => 0x01, valueSubId => 0x1F,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'month_byte', knxTyp => '7' };
push @definitions, { name => 'Ferienende_Jahr', valueId => 0x01, valueSubId => 0x20,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'year_byte', knxTyp => '7' };
push @definitions, { name => 'Wochentag', valueId => 0x01, valueSubId => 0x21,
			writeTarget => 0x0D, requestTarget => undef, responseTarget => undef,
			decimalFactor => 1, format => 'weekday_byte', knxTyp => '7' };
push @definitions, { name => 'Datum_Tag', valueId => 0x01, valueSubId => 0x22,
			writeTarget => 0x0D, requestTarget => undef, responseTarget => undef,
			decimalFactor => 1, format => 'day_byte', knxTyp => '7' };
push @definitions, { name => 'Datum_Monat', valueId => 0x01, valueSubId => 0x23,
			writeTarget => 0x0D, requestTarget => undef, responseTarget => undef,
			decimalFactor => 1, format => 'month_byte', knxTyp => '7' };
push @definitions, { name => 'Datum_Jahr', valueId => 0x01, valueSubId => 0x24,
			writeTarget => 0x0D, requestTarget => undef, responseTarget => undef,
			decimalFactor => 1, format => 'year_byte', knxTyp => '7' };
push @definitions, { name => 'Zeit_Stunde', valueId => 0x01, valueSubId => 0x25,
			writeTarget => 0x0D, requestTarget => undef, responseTarget => undef,
			decimalFactor => 1, format => 'hour_byte', knxTyp => '7' };
push @definitions, { name => 'Zeit_Minute', valueId => 0x01, valueSubId => 0x26,
			writeTarget => 0x0D, requestTarget => undef, responseTarget => undef,
			decimalFactor => 1, format => 'minute_byte', knxTyp => '7' };
push @definitions, { name => 'Heizen_Soll_Handbetrieb', valueId => 0x01, valueSubId => 0x29,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Heizkurfe_Sollwert_Min', valueId => 0x01, valueSubId => 0x2B,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Heizen_Raumtemperatur_Bereitschaft', valueId => 0x01, valueSubId => 0x3D,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Warmwasser_Hysterese', valueId => 0x01, valueSubId => 0x40,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthKelvin', knxTyp => '9.002' };
push @definitions, { name => 'Integralanteil_Heizgrundeinstellung', valueId => 0x01, valueSubId => 0x62,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 60, format => 'kelvinPerMinute', knxTyp => '9.003' };
push @definitions, { name => 'Display_Symbole', valueId => 0x01, valueSubId => 0x76,
			writeTarget => 0x0D, requestTarget => undef, responseTarget => undef,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Maximaldauer_Warmwasser_Erzeugung', valueId => 0x01, valueSubId => 0x80,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'hour', knxTyp => '7.007' };
push @definitions, { name => 'Volumenstrom', valueId => 0x01, valueSubId => 0xDA,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 600, format => 'tenthLiterPerMinute', knxTyp => '9.025' };
push @definitions, { name => 'Tautemperatur', valueId => 0x02, valueSubId => 0x64,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Heissgastemperatur', valueId => 0x02, valueSubId => 0x65,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Solar_Kollektorschutz', valueId => 0x02, valueSubId => 0xF5,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => undef, format => 'boolean', knxTyp => '1.002' };
push @definitions, { name => 'Solar_Kollektorgrenztemperatur', valueId => 0x02, valueSubId => 0xF6,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Wärmemenge_Wärmerückgewinnung_Tag_Wh', valueId => 0x03, valueSubId => 0xAE,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'wattHour', knxTyp => '13.010' };
push @definitions, { name => 'Wärmemenge_Wärmerückgewinnung_Tag_KWh', valueId => 0x03, valueSubId => 0xAF,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Wärmerückgewinnung_Summe_KWh', valueId => 0x03, valueSubId => 0xB0,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Wärmerückgewinnung_Summe_MWh', valueId => 0x03, valueSubId => 0xB1,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'megaWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Lüftung_Filter_Reset', valueId => 0x03, valueSubId => 0x3B,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => undef, format => 'boolean', knxTyp => '1.002' };
push @definitions, { name => 'Lüftung_Filter_Laufzeit', valueId => 0x03, valueSubId => 0x41,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'day', knxTyp => '7' };
push @definitions, { name => 'Solar_Kollektorschutztemperatur', valueId => 0x02, valueSubId => 0xB8,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Solar_Kollektorsperrtemperatur', valueId => 0x02, valueSubId => 0xBB,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Kühlen_Raumtemperatur_Tag', valueId => 0x05, valueSubId => 0x69,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Kühlen_Raumtemperatur_Bereitschaft', valueId => 0x05, valueSubId => 0x6A,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Kühlen_Raumtemperatur_Nacht', valueId => 0x05, valueSubId => 0x6B,
			writeTarget => 0x06, requestTarget => 0x06, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Lüftung_Stufe_Tag', valueId => 0x05, valueSubId => 0x6C,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Lüftung_Stufe_Nacht', valueId => 0x05, valueSubId => 0x6D,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Lüftung_Stufe_Bereitschaft', valueId => 0x05, valueSubId => 0x6F,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Lüftung_Stufe_Party', valueId => 0x05, valueSubId => 0x70,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Lüftung_Außerordentlich_Stufe_0', valueId => 0x05, valueSubId => 0x71,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'minute', knxTyp => '7.006' };
push @definitions, { name => 'Lüftung_Außerordentlich_Stufe_1', valueId => 0x05, valueSubId => 0x72,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'minute', knxTyp => '7.006' };
push @definitions, { name => 'Lüftung_Außerordentlich_Stufe_2', valueId => 0x05, valueSubId => 0x73,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'minute', knxTyp => '7.006' };
push @definitions, { name => 'Lüftung_Außerordentlich_Stufe_3', valueId => 0x05, valueSubId => 0x74,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'minute', knxTyp => '7.006' };
push @definitions, { name => 'Passivkühlung', valueId => 0x05, valueSubId => 0x75,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Lüfterstufe_Zuluft_1', valueId => 0x05, valueSubId => 0x76,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'cubicmeterPerHour', knxTyp => '9.025' };
push @definitions, { name => 'Lüfterstufe_Zuluft_2', valueId => 0x05, valueSubId => 0x77,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'cubicmeterPerHour', knxTyp => '9.025' };
push @definitions, { name => 'Lüfterstufe_Zuluft_3', valueId => 0x05, valueSubId => 0x78,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'cubicmeterPerHour', knxTyp => '9.025' };
push @definitions, { name => 'Lüfterstufe_Abluft_1', valueId => 0x05, valueSubId => 0x79,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'cubicmeterPerHour', knxTyp => '9.025' };
push @definitions, { name => 'Lüfterstufe_Abluft_2', valueId => 0x05, valueSubId => 0x7A,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'cubicmeterPerHour', knxTyp => '9.025' };
push @definitions, { name => 'Lüfterstufe_Abluft_3', valueId => 0x05, valueSubId => 0x7B,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'cubicmeterPerHour', knxTyp => '9.025' };
push @definitions, { name => 'Ofen_Kamin', valueId => 0x05, valueSubId => 0x7C,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => undef, format => 'boolean', knxTyp => '1.002' };
push @definitions, { name => 'LL_Wärmetauscher_Max_Abtaudauer', valueId => 0x05, valueSubId => 0x7D,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'minute', knxTyp => '7.006' };
push @definitions, { name => 'LL_Wärmetauscher_Abtaubeginnschwelle', valueId => 0x05, valueSubId => 0x7E,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'percent', knxTyp => '8.010' };
push @definitions, { name => 'LL_Wärmetauscher_Drehzahl_Filter', valueId => 0x05, valueSubId => 0x7F,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'percent', knxTyp => '8.010' };
push @definitions, { name => 'Warmwasser_Solltemperatur_Handbetrieb', valueId => 0x05, valueSubId => 0x80,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Warmwasser_Solltemperatur_Bereitschaft', valueId => 0x05, valueSubId => 0x81,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Kühlen_Temperatur_Heizkreis', valueId => 0x05, valueSubId => 0x82,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Kühlen_Vorlauftemperatur_Hysterese_Unbekannt', valueId => 0x05, valueSubId => 0x83,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthKelvin', knxTyp => '9.002' };
push @definitions, { name => 'Kühlen_Raumtemperatur_Hysterese', valueId => 0x05, valueSubId => 0x84,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthKelvin', knxTyp => '9.002' };
push @definitions, { name => 'Antilegionellen', valueId => 0x05, valueSubId => 0x85,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'day', knxTyp => '7' };
push @definitions, { name => 'Warmwasser_Temperatur_Legionellen', valueId => 0x05, valueSubId => 0x86,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Zeitsperre_Nacherwärmung', valueId => 0x05, valueSubId => 0x88,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'minute', knxTyp => '7.006' };
push @definitions, { name => 'Temperaturfreigabe_Nacherwärmung', valueId => 0x05, valueSubId => 0x89,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Nacherwärmung_Stufe_Warmwasser', valueId => 0x05, valueSubId => 0x8A,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Warmwasser_Pufferbetrieb', valueId => 0x05, valueSubId => 0x8B,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => undef, format => 'boolean', knxTyp => '1.002' };
push @definitions, { name => 'Warmwasser_Max_Vorlauftemperatur', valueId => 0x05, valueSubId => 0x8C,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Warmwasser_ECO_Modus', valueId => 0x05, valueSubId => 0x8D,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => undef, format => 'boolean', knxTyp => '1.002' };
push @definitions, { name => 'Solar_Hysterese', valueId => 0x05, valueSubId => 0x8F,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthKelvin', knxTyp => '9.002' };
push @definitions, { name => 'Zuluft_Soll', valueId => 0x05, valueSubId => 0x96,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'cubicmeterPerHour', knxTyp => '9.025' };
push @definitions, { name => 'Zuluft_Ist', valueId => 0x05, valueSubId => 0x97,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'herz', knxTyp => '14.033' };
push @definitions, { name => 'Abluft_Soll', valueId => 0x05, valueSubId => 0x98,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'cubicmeterPerHour', knxTyp => '9.025' };
push @definitions, { name => 'Abluft_Ist', valueId => 0x05, valueSubId => 0x99,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'herz', knxTyp => '14.033' };
push @definitions, { name => 'Fortluft_Soll', valueId => 0x05, valueSubId => 0x9A,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'percent', knxTyp => '8.010' };
push @definitions, { name => 'Fortluft_Ist', valueId => 0x05, valueSubId => 0x9B,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'herz', knxTyp => '14.033' };
push @definitions, { name => 'Verflüssiger_Temperatur', valueId => 0x05, valueSubId => 0x9C,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Heizkurve_Anteil_Vorlauf', valueId => 0x05, valueSubId => 0x9D,
			writeTarget => 0x06, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Heizkurve_Fußpunkt', valueId => 0x05, valueSubId => 0x9E,
			writeTarget => 0x06, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Heizgrundeinstellung_Nacherwärmung_Maximale_Stufe', valueId => 0x05, valueSubId => 0x9F,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Heizgrundeinstellung_Zeitsperre_Nacherwärmung', valueId => 0x05, valueSubId => 0xA0,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'minute', knxTyp => '7.006' };
push @definitions, { name => 'Heizgrundeinstellung_Heizleistung_Nacherwärmung_1', valueId => 0x05, valueSubId => 0xA1,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 100, format => 'hundrethKiloWatt', knxTyp => '9.024' };
push @definitions, { name => 'Heizgrundeinstellung_Hysterese_Sommerbetrieb', valueId => 0x05, valueSubId => 0xA2,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthKelvin', knxTyp => '9.002' };
push @definitions, { name => 'Heizgrundeinstellung_Korrektur_Außentemperatur', valueId => 0x05, valueSubId => 0xA3,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Heizstufe', valueId => 0x05, valueSubId => 0xBB,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'LL_Wärmetauscher_Abtauen', valueId => 0x05, valueSubId => 0xBC,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => undef, format => 'boolean', knxTyp => '1.002' };
push @definitions, { name => 'Warmwasser_Solltemperatur_Nacht', valueId => 0x05, valueSubId => 0xBF,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };
push @definitions, { name => 'Hysterese_1', valueId => 0x05, valueSubId => 0xC0,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthKelvin', knxTyp => '9.002' };
push @definitions, { name => 'Hysterese_2', valueId => 0x05, valueSubId => 0xC1,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthKelvin', knxTyp => '9.002' };
push @definitions, { name => 'Hysterese_3', valueId => 0x05, valueSubId => 0xC2,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthKelvin', knxTyp => '9.002' };
push @definitions, { name => 'Hysterese_4', valueId => 0x05, valueSubId => 0xC3,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthKelvin', knxTyp => '9.002' };
push @definitions, { name => 'Hysterese_5', valueId => 0x05, valueSubId => 0xC4,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthKelvin', knxTyp => '9.002' };
push @definitions, { name => 'Hysterese_Asymmetrie', valueId => 0x05, valueSubId => 0xC5,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Ferienbeginn_Uhrzeit_Unbekannt', valueId => 0x05, valueSubId => 0xD3,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Ferienende_Uhrzeit_Unbekannt', valueId => 0x05, valueSubId => 0xD4,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Passivkühlung_Fortluft', valueId => 0x05, valueSubId => 0xDB,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => undef, format => 'boolean', knxTyp => '1.002' };
push @definitions, { name => 'Heizgrundeinstellung_Unterdrücke_Temperaturmessung', valueId => 0x06, valueSubId => 0x11,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Lüftung_Stufe_Handbetrieb', valueId => 0x06, valueSubId => 0x12,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Wärmemenge_Solar_Heizung_Tag_Wh', valueId => 0x06, valueSubId => 0x40,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'wattHour', knxTyp => '13.010' };
push @definitions, { name => 'Wärmemenge_Solar_Heizung_Tag_KWh', valueId => 0x06, valueSubId => 0x41,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Solar_Heizung_Summe_KWh', valueId => 0x06, valueSubId => 0x42,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Solar_Heizung_Summe_MWh', valueId => 0x06, valueSubId => 0x43,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'megaWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Solar_Warmwasser_Tag_Wh', valueId => 0x06, valueSubId => 0x44,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'wattHour', knxTyp => '13.010' };
push @definitions, { name => 'Wärmemenge_Solar_Warmwasser_Tag_KWh', valueId => 0x06, valueSubId => 0x45,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Solar_Warmwasser_Summe_KWh', valueId => 0x06, valueSubId => 0x46,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Solar_Warmwasser_Summe_MWh', valueId => 0x06, valueSubId => 0x47,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'megaWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Kühlen_Summe_KWh', valueId => 0x06, valueSubId => 0x48,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Kühlen_Summe_MWh', valueId => 0x06, valueSubId => 0x49,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'megaWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Solar_Kühlzeit_Von_Unbekannt', valueId => 0x06, valueSubId => 0x4C,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Solar_Kühlzeit_Bis_Unbekannt', valueId => 0x06, valueSubId => 0x4D,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'none', knxTyp => '7' };
push @definitions, { name => 'Feuchte_Maskierzeit', valueId => 0x06, valueSubId => 0x4F,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'minute', knxTyp => '7.006' };
push @definitions, { name => 'Feuchte_Schwellwert', valueId => 0x06, valueSubId => 0x50,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'percent', knxTyp => '8.010' };
push @definitions, { name => 'Lüftung_Leistungsreduktion', valueId => 0x06, valueSubId => 0xA4,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'percent', knxTyp => '8.010' };
push @definitions, { name => 'Lüftung_Leistungserhöhung', valueId => 0x06, valueSubId => 0xA5,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'percent', knxTyp => '8.010' };
push @definitions, { name => 'Wärmemenge_Nacherwärmung_Warmwasser_Summe_KWh', valueId => 0x09, valueSubId => 0x24,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Nacherwärmung_Warmwasser_Summe_MWh', valueId => 0x09, valueSubId => 0x25,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'megaWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Nacherwärmung_Heizen_Summe_KWh', valueId => 0x09, valueSubId => 0x28,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Nacherwärmung_Heizen_Summe_MWh', valueId => 0x09, valueSubId => 0x29,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'megaWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Warmwasser_Tag_Wh', valueId => 0x09, valueSubId => 0x2A,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'wattHour', knxTyp => '13.010' };
push @definitions, { name => 'Wärmemenge_Warmwasser_Tag_KWh', valueId => 0x09, valueSubId => 0x2B,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Warmwasser_Summe_KWh', valueId => 0x09, valueSubId => 0x2C,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Warmwasser_Summe_MWh', valueId => 0x09, valueSubId => 0x2D,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'megaWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Heizen_Tag_Wh', valueId => 0x09, valueSubId => 0x2E,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'wattHour', knxTyp => '13.010' };
push @definitions, { name => 'Wärmemenge_Heizen_Tag_KWh', valueId => 0x09, valueSubId => 0x2F,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Heizen_Summe_KWh', valueId => 0x09, valueSubId => 0x30,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'kiloWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Wärmemenge_Heizen_Summe_MWh', valueId => 0x09, valueSubId => 0x31,
			writeTarget => undef, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 0.001, format => 'megaWattHour', knxTyp => '13.013' };
push @definitions, { name => 'Feuchte_Soll_Minimum', valueId => 0x09, valueSubId => 0xD2,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'percent', knxTyp => '8.010' };
push @definitions, { name => 'Feuchte_Soll_Maximum', valueId => 0x09, valueSubId => 0xD3,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 1, format => 'percent', knxTyp => '8.010' };
push @definitions, { name => 'Heizgrundeinstellung_Bivalenzpunkt', valueId => 0x11, valueSubId => 0xAC,
			writeTarget => 0x03, requestTarget => 0x03, responseTarget => 0x0D,
			decimalFactor => 10, format => 'tenthDegree', knxTyp => '9.001' };


my @combinations;
push @combinations, { name => 'Wärmemenge_Heizen_Summe', def1 => 'Wärmemenge_Heizen_Summe_MWh', def2 => 'Wärmemenge_Heizen_Summe_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Solar_Heizung_Summe', def1 => 'Wärmemenge_Solar_Heizung_Summe_MWh', def2 => 'Wärmemenge_Solar_Heizung_Summe_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Nacherwärmung_Heizen_Summe', def1 => 'Wärmemenge_Nacherwärmung_Heizen_Summe_MWh', def2 => 'Wärmemenge_Nacherwärmung_Heizen_Summe_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Warmwasser_Summe', def1 => 'Wärmemenge_Warmwasser_Summe_MWh', def2 => 'Wärmemenge_Warmwasser_Summe_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Solar_Warmwasser_Summe', def1 => 'Wärmemenge_Solar_Warmwasser_Summe_MWh', def2 => 'Wärmemenge_Solar_Warmwasser_Summe_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Nacherwärmung_Warmwasser_Summe', def1 => 'Wärmemenge_Nacherwärmung_Warmwasser_Summe_MWh', def2 => 'Wärmemenge_Nacherwärmung_Warmwasser_Summe_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Kühlen_Summe', def1 => 'Wärmemenge_Kühlen_Summe_MWh', def2 => 'Wärmemenge_Kühlen_Summe_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Wärmerückgewinnung_Summe', def1 => 'Wärmemenge_Wärmerückgewinnung_Summe_MWh', def2 => 'Wärmemenge_Wärmerückgewinnung_Summe_KWh', knxTyp => '13.013' };

push @combinations, { name => 'Wärmemenge_Heizen_Tag', def1 => 'Wärmemenge_Heizen_Tag_MWh', def2 => 'Wärmemenge_Heizen_Tag_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Solar_Heizung_Tag', def1 => 'Wärmemenge_Solar_Heizung_Tag_MWh', def2 => 'Wärmemenge_Solar_Heizung_Tag_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Nacherwärmung_Heizen_Tag', def1 => 'Wärmemenge_Nacherwärmung_Heizen_Tag_MWh', def2 => 'Wärmemenge_Nacherwärmung_Heizen_Tag_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Warmwasser_Tag', def1 => 'Wärmemenge_Warmwasser_Tag_MWh', def2 => 'Wärmemenge_Warmwasser_Tag_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Solar_Warmwasser_Tag', def1 => 'Wärmemenge_Solar_Warmwasser_Tag_MWh', def2 => 'Wärmemenge_Solar_Warmwasser_Tag_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Nacherwärmung_Warmwasser_Tag', def1 => 'Wärmemenge_Nacherwärmung_Warmwasser_Tag_MWh', def2 => 'Wärmemenge_Nacherwärmung_Warmwasser_Tag_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Kühlen_Tag', def1 => 'Wärmemenge_Kühlen_Tag_MWh', def2 => 'Wärmemenge_Kühlen_Tag_KWh', knxTyp => '13.013' };
push @combinations, { name => 'Wärmemenge_Wärmerückgewinnung_Tag', def1 => 'Wärmemenge_Wärmerückgewinnung_Tag_MWh', def2 => 'Wärmemenge_Wärmerückgewinnung_Tag_KWh', knxTyp => '13.013' };


my @mapped;
my $interface = 'can0';
my @display = (0x1E, 0x1F, 0x20, 0x21, 0x22);
my $displaynum = 2;

###############################
# Lesen der Konfigurationsdatei
###############################

# Read config file in conf.d
my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
if (! -f $confFile) {
	plugin_log($plugname, " no conf file [$confFile] found.");
	return "no conf file [$confFile] found.";
} else {
	open(CONF, $confFile);
	my @lines = <CONF>;
	close($confFile);
	my $result = eval("@lines");
	if ($@) {
		plugin_log($plugname, "conf file [$confFile] returned:");
		my @parts = split(/\n/, $@);
		plugin_log($plugname, "--> $_") foreach (@parts);
	}
}

# Festlegen, dass das Plugin alle 5 Minuten laufen soll
#$plugin_info{$plugname.'_cycle'} = 300;
$plugin_info{$plugname.'_cycle'} = 60;

my $debug = 0;

############
### MAIN ###
############

my $displayId = $display[$displaynum];
my $canId = 0x0680 + $displayId;
my $sc;

my $c = Convert::Binary::C->new();
$c->parse($cstruct);

if (!$socket[$socknum]) {
    socket($sc, PF_CAN, SOCK_RAW, CAN_RAW)
                 or die "Can't open socket $!\n";
	my $if_idx = can_if_idx($sc, $c, $interface);
    bind($sc, $c->pack('sockaddr_can', {can_family => AF_CAN, can_ifindex => $if_idx}))
                 or die "Can't bind to can $!\n";

	$socket[$socknum] = $sc;
    $socksel->add($socket[$socknum]); # add socket to select
    $plugin_socket_subscribe{$socket[$socknum]} = $plugname;
    plugin_log($plugname, 'Socket verbunden. Socketnummer: ' . $socknum);

    return "opened socket $socknum";
}

$sc = $socket[$socknum];

if ($event =~ /socket/) {
	my $frame_len = $c->sizeof('can_frame');
    recv($sc, my $frame, $frame_len, 0) or die "Recv failed $!\n";
    my $f = $c->unpack('can_frame', $frame);
    @{$f->{data}}[$f->{can_dlc} .. $#{$f->{data}}] = (0,0,0,0,0,0,0,0);

	handle_response($displayId, $f->{can_id}, $f->{can_dlc}, $f->{data});
} elsif ($event =~ /knx/) {
	if ($msg{apci} eq "A_GroupValue_Write") {
		my $ga = $msg{dst};
		my ($entry, $definition) = find_mapping_ga($ga);
		if (!defined $entry) {
			delete $plugin_subscribe{$ga}{$plugname};
			plugin_log($plugname, 'Unbekannte Gruppenadresse: ' . $ga . ' -> abgemeldet');
			return;
		}
		my $value = undef;
		if (defined $msg{value}) {
			$value = $msg{value};
		} else {
			my @typArray = split(/\./, $definition->{knxTyp});
			my $majorTyp = $typArray[0];
			if ($majorTyp eq "9") {
				$value = decode_dpt9($msg{data});
			} else {
				plugin_log($plugname, 'Kann KNX Wert für ' . $entry->{name} . ' nicht lesen: ' . $definition->{knxTyp});
			}
		}
		if (defined $value) {
			plugin_log($plugname, 'Empfange KNX Wert für ' . $entry->{name} . ': ' . $value);
			send_lwz_write($sc, $c, $canId, $entry, $definition, $value);
		}
	}
} elsif ($event =~ /cycle/) {
	foreach my $entry (@mapped) {
		if ($entry->{cycle}) {
			send_lwz_request($sc, $c, $canId, $entry->{name}, $entry->{target});
		}
	}
} elsif ($event =~ /restart|modified/) {
    plugin_log($plugname, 'Registriere Display: ' . $displaynum);
	register_display($sc, $c, $canId, $displayId);
	foreach my $entry (@mapped) {
		if (defined $entry->{knxWriteGA}) {
			my $ga = $entry->{knxWriteGA};
			$plugin_subscribe{$ga}{$plugname} = 1;
			plugin_log($plugname, 'Registriere Gruppenadresse: ' . $ga);
		}
	}
}

return;

sub register_display {
	my ($sock, $c, $id, $displayId) = @_;
	can_send($sock, $c, $id, [TARGET_DISPLAY, $displayId, 0xFD, 0x01, 0x00, 0x00, 0x00]);
}

sub can_send {
	my ($sock, $c, $id, $data) = @_;
	my $frame = $c->pack('can_frame', {
			can_id => $id,
			can_dlc => scalar @$data,
			data => $data
	});
	syswrite($sock, $frame) or die "Send failed $!\n";
}

sub can_if_idx {
	my ($sock, $c, $if_name) = @_;
	my @if = map { ord($_) } split(//, $if_name);
	my $ifreq = $c->pack('ifreq', {ifr_ifrn => {ifrn_name => \@if}});
	ioctl($sock, SIOCGIFINDEX, $ifreq) or die "Ioctl call failed $!\n";
	my $res = $c->unpack('ifreq', $ifreq);
	return $res->{ifr_ifru}{ifru_ivalue};
}

sub send_lwz_request {
	my ($sock, $c, $id, $name, $target) = @_;
	my $definition = get_definition($name);

	if (! defined $definition) {
		my $combination = get_combination_definition($name);
		if (defined $combination) {
			send_lwz_request($sock, $c, $id, $combination->{def1}, $target);
			send_lwz_request($sock, $c, $id, $combination->{def2}, $target);
			return;
		}
		plugin_log($plugname, 'Kann Definition nicht finden: ' . $name);
		return;
	}

	plugin_log($plugname, 'Bearbeite: ' . $definition->{name});
	if ($definition->{requestTarget} == TARGET_SYSTEM) {
		can_send($sock, $c, $id, [(TARGET_SYSTEM<<4) | TYPE_REQUEST, 0x00, 0xFA, $definition->{valueId}, $definition->{valueSubId}, 0x00, 0x00]);
	} elsif ($definition->{requestTarget} == TARGET_HEIZKREIS) {
		if (defined $target) {
			if ($target == HEIZKREIS_1 || $target == HEIZKREIS_2) {
				can_send($sock, $c, $id, [(TARGET_HEIZKREIS<<4) | TYPE_REQUEST, $target, 0xFA, $definition->{valueId}, $definition->{valueSubId}, 0x00, 0x00]);
			} else {
				plugin_log($plugname, $name . ': Attribut "target" enthält einen ungültigen Wert');
			}
		} else {
			plugin_log($plugname, $name . ': Attribut "target" wird benötigt');
		}
	} else {
		plugin_log($plugname, $name . ': Request type noch nicht implementiert');
	}
}

sub send_lwz_write {
	my ($sock, $c, $id, $entry, $definition, $value) = @_;
	if (defined $definition->{writeTarget}) {
		my ($value1, $value2) = convert_to_lwz_value($definition, $value);
		if (defined $value1) {
			can_send($sock, $c, $id, [($definition->{writeTarget}<<4) | TYPE_WRITE, $entry->{target}, 0xFA, $definition->{valueId}, $definition->{valueSubId}, $value1, $value2]);
		}
	} else {
		plugin_log($plugname, $entry->{name} . ': Readonly-Wert kann nicht geschrieben werden');
	}
}

sub handle_response {
	my ($displayId, $id, $dlc, $dataRef) = @_;
	my @data = @{$dataRef};
	if ($dlc == 7) {
		my $target = ($data[0] & 0xF0) >> 4;
		my $type = $data[0] & 0x0F;
		my $subTarget = $data[1];
		if ($type == TYPE_RESPONSE || $type == TYPE_WRITE) {
			if ($target == TARGET_DISPLAY && ($subTarget == $displayId || $subTarget == 0x3C)) {
				my $source = ($id & 0xFF00) >> 8;
				my $subSource = $id & 0x00FF;
				my $fix = $data[2];
				my $valueId = $data[3];
				my $valueSubId = $data[4];
				if (($source == SOURCE_SYSTEM || $source == SOURCE_HEIZKREIS) && $fix == 0xFA) {
					my ($entry, $combination, $definition) = find_combination_mapping($source, $subSource, $valueId, $valueSubId);
					if (! defined $entry) {
						($entry, $definition) = find_mapping($source, $subSource, $valueId, $valueSubId);
					}
					if (defined $entry) {
						my $value = ($data[5] << 8) | $data[6];
						my $convertedValue = convert_response_value($definition, $value);
						if (defined $convertedValue) {
							plugin_log($plugname, $entry->{name} . ': ' . $convertedValue);
							if (defined $combination) {
								my $currentTime = time();
								saveCombinationValue($definition->{name}, $convertedValue, $currentTime);
								my ($def1, $def2, $value1, $value2);
								if ($combination->{def1} eq $definition->{name}) {
									$def1 = $definition;
									$value1 = $convertedValue;
									$def2 = get_definition($combination->{def2});
									$value2 = loadCombinationValue($combination->{def2}, $currentTime - 10);
								} else {
									$def2 = $definition;
									$value2 = $convertedValue;
									$def1 = get_definition($combination->{def1});
									$value1 = loadCombinationValue($combination->{def1}, $currentTime - 10);
								}
								if (!defined $def1 || !defined $def2 || !defined $value1 || !defined $value2) {
									return;
								}
								$value1 = convertValueToTargetTyp($value1, $def1->{knxTyp}, $combination->{knxTyp});
								$value2 = convertValueToTargetTyp($value2, $def2->{knxTyp}, $combination->{knxTyp});
								if (!defined $value1 || !defined $value2) {
									dump_can_message('Kombinationswert konnte nicht in das richtige Format umgewandelt werden', $id, $dlc, \@data);
									return;
								}
								$convertedValue = $value1 + $value2;
								knx_write($entry->{knxStatusGA}, $convertedValue, $combination->{knxTyp});
							} else {
								knx_write($entry->{knxStatusGA}, $convertedValue, $definition->{knxTyp});
							}		
						} else {
							dump_can_message('Wert konnte nicht verarbeitet werden', $id, $dlc, \@data);
						}
					} elsif ($target != TARGET_DISPLAY || $subTarget != 0x3C) {
						dump_can_message('Nicht erwarteter Transfer', $id, $dlc, \@data);
					}
				} else {
					dump_can_message('Unbekannter Transfer', $id, $dlc, \@data);
				}
			}
		}
	} else {
		dump_can_message('Fehlerhafte Transferlänge', $id, $dlc, \@data);
	}
}

sub find_mapping {
	my ($source, $subSource, $valueId, $valueSubId) = @_;
	foreach my $entry (@mapped) {
		my $definition = get_definition($entry->{name});
		if ($valueId == $definition->{valueId} && $valueSubId == $definition->{valueSubId}) {
			if ($source == SOURCE_SYSTEM) {
				if ($subSource == 0x80) {
					return ($entry, $definition);
				}
			} else {
				if ($subSource == $entry->{target}) {
					return ($entry, $definition);
				}
			}
		}
	}
	return (undef, undef);
}

sub find_combination_mapping {
	my ($source, $subSource, $valueId, $valueSubId) = @_;
	foreach my $entry (@mapped) {
		my $combination = get_combination_definition($entry->{name});
		
		my $definition = get_definition($combination->{def1});
		if ($valueId == $definition->{valueId} && $valueSubId == $definition->{valueSubId}) {
			if ($source == SOURCE_SYSTEM) {
				if ($subSource == 0x80) {
					return ($entry, $combination, $definition);
				}
			} else {
				if ($subSource == $entry->{target}) {
					return ($entry, $combination, $definition);
				}
			}
		}

		$definition = get_definition($combination->{def2});
		if ($valueId == $definition->{valueId} && $valueSubId == $definition->{valueSubId}) {
			if ($source == SOURCE_SYSTEM) {
				if ($subSource == 0x80) {
					return ($entry, $combination, $definition);
				}
			} else {
				if ($subSource == $entry->{target}) {
					return ($entry, $combination, $definition);
				}
			}
		}

	}
	return (undef, undef, undef);
}

sub convert_response_value {
	my ($definition, $value) = @_;
	if ($definition->{format} eq 'tenthDegree') {
		$value -= 0x10000 if $value >= 0x8000;
	}
	if (defined $definition->{decimalFactor}) {
		return $value / $definition->{decimalFactor};
	} else {
		return $value;
	}
}

sub convert_to_lwz_value {
	my ($definition, $value) = @_;
	if ($definition->{format} eq 'tenthDegree') {
		$value += 0x10000 if $value < 0;
	}
	if (defined $definition->{decimalFactor}) {
		return $value * $definition->{decimalFactor};
		my $value1 = (($value * $definition->{decimalFactor}) >> 8) & 0x00FF;
		my $value2 = ($value * $definition->{decimalFactor}) & 0x00FF;
		return $value1, $value2;
	} else {
		my $value1 = ($value >> 8) & 0x00FF;
		my $value2 = $value & 0x00FF;
		return $value1, $value2;
	}
}

sub dump_can_message {
	my ($msg, $id, $dlc, $dataRef) = @_;
	my @data = @{$dataRef};
	my $dump = sprintf("%4X [%d] %02X %02X %02X %02X %02X %02X %02X %02X", $id, $dlc, @data);
	plugin_log($plugname, $msg . ': ' . $dump);
}

sub find_mapping_ga {
	my ($ga) = @_;
	foreach my $entry (@mapped) {
		if (defined $entry->{knxWriteGA}) {
			if ($ga eq $entry->{knxWriteGA}) {
				my $definition = get_definition($entry->{name});
				return ($entry, $definition);
			}
		}
	}
	return (undef, undef);
}

sub get_definition {
	my ($name) = @_;
	foreach my $definition (@definitions) {
		if ($name eq $definition->{name}) {
			return $definition;
		}
	}
	return undef;
}

sub get_combination_definition {
	my ($name) = @_;
	foreach my $combination (@combinations) {
		if ($name eq $combination->{name}) {
			return $combination;
		}
	}
	return undef;
}

#####################################
# Wert für Wertekombination speichern
#####################################
sub saveCombinationValue {
	my ($name, $value, $time) = @_;
	$plugin_info{$plugname . '_Combination_' . $name} = $time . ':' . $value;
}


#################################
# Wert für Wertekombination laden
#################################
sub loadCombinationValue {
	my ($name, $time) = @_;
	my $loaded = $plugin_info{$plugname . '_Combination_' . $name};
	my ($valueTime, $value) = split(':', $loaded, 2);
	if ($valueTime >= $time) {
		return $value;
	} else {
		return undef;
	}
}

sub convertValueToTargetTyp {
	my ($value, $typ, $targetTyp) = @_;
	if ($typ eq $targetTyp) {
		return $value;
	} elsif ($typ eq '13.010' && $targetTyp eq '13.013') {
		return $value / 1000;
	} elsif ($typ eq '13.013' && $targetTyp eq '13.010') {
		return $value * 1000;
	} else {
		return undef;
	}
}
