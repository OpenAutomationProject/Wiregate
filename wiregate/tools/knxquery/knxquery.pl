#!/usr/bin/perl -w
# $Id$
# 
# knx bus value query script
#
# Copyright (C) 2011 Edgar <emax> Hermanns, <emax at berlios punkt de>
# All Rights Reserved
#
# This work is derived from the wiregated.pl script by Michael Markstaller
# Parts of the script Copyright Michael Markstaller and others 
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 2 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA

use strict;
use Getopt::Long;
use Config::Std { def_sep => '=', read_config => 'my_read_cfg' };
use Switch;
use EIBConnection;

# use Data::Dumper;

my $debug=0;
my %eibgaconf;
my $eib_url = "local:/tmp/eib";

my ($dump_arg, $read_arg, $ga_arg, $age_arg, $dpt_arg, $help);

sub usage
{
    system "perldoc $0";
    print "\n@_\n" if ( @_ );
    exit;
} # usage

sub dumpGa
{
    # koennte man mit dem Dumper machen ... 
    #    print Dumper(%eibgaconf), "\n";
    # ... soll aber schoener aussehen:
    &printGaInfo($_) foreach (sort keys %eibgaconf);
} # dumpGa

sub printGaInfo
{
    my $ga = shift || die "\n\n fehlender GA-paramater in printGaInfo()\n\n";
    my ($dptid, $dptsubid, $dptname, $gaName) = ('','','');

    if (!exists $eibgaconf{$ga})
    {
	$gaName = "!!! GA ist nicht konfiguriert !!!\n";
	$dptid = $dptname = $dptsubid = '?' ;		
    }
    else
    {	
	$dptid    = $eibgaconf{$ga}{DPTId};
	$dptsubid = $eibgaconf{$ga}{DPTSubId};
	$dptname  = $eibgaconf{$ga}{DPT_SubTypeName};
	$gaName   = $eibgaconf{$ga}{name};
    }
    printf "%-15s%-9s%-16s%-25s%s\n",
    "GA[$ga]",
    "DPTId[$dptid]",
    "DPTSubID[$dptsubid]",
    "DPTName[$dptname]",
    "$gaName";
} # printGaInfo


# sub addr2str {
#     my $a = $_[0];
#     my $b = $_[1] || 0;  # 1 if local (group) address, else physical address
#     my $str ;
#     if ($b == 1) { # logical address used
#         $str = sprintf "%d/%d/%d", ($a >> 11) & 0xf, ($a >> 8) & 0x7, $a & 0xff;
#     }
#     else { # physical address used
#         $str = sprintf "%d.%d.%d", $a >> 12, ($a >> 8) & 0xf, $a & 0xff;
#     }
#     return $str;
# }

# str2addr: Convert an EIB address string in the form "1/2/3" or "1.2.3" to an integer
sub str2addr {
    my $str = $_[0];
    if ($str =~ /(\d+)\/(\d+)\/(\d+)/) { # logical address
        return ($1 << 11) | ($2 << 8) | $3;
    } elsif ($str =~ /(\d+)\.(\d+)\.(\d+)/) { # physical address
        return ($1 << 12) | ($2 << 8) | $3;
    } else {
    	#bad
    	return;
    }
} # str2addr

sub decode_dpt9 {
    my @data = @_;
#     print "\n";
#     print "D: $_\n" foreach (@data);
    my $res;

    unless ($#data == 2) {
    	($data[1],$data[2]) = split(' ',$data[0]);
    	$data[1] = hex $data[1];
    	$data[2] = hex $data[2];
        unless (defined $data[2]) {
            return;
        }
    }
    my $sign = $data[1] & 0x80;
    my $exp = ($data[1] & 0x78) >> 3;
    my $mant = (($data[1] & 0x7) << 8) | $data[2];

    $mant = -(~($mant - 1) & 0x7ff) if $sign != 0;
    $res = (1 << $exp) * 0.01 * $mant;
    return $res;
} # decode_dpt9 

sub decode_dpt4 { #1byte char
    return sprintf("%c", hex(shift));
}

sub decode_dpt5 { #1byte unsigned percent
    return sprintf("%.1f", hex(shift) * 100 / 255);
}

sub decode_dpt510 { #1byte unsigned UChar
    return hex(shift);
}

sub decode_dpt6 { #1byte signed 
    my $val = hex(shift);
    return $val > 127 ? $val-256 : $val;
}

sub decode_dpt7 { #2byte unsigned 
    my @val = split(" ",shift);
    return (hex($val[0])<<8) + hex($val[1]);
}

sub decode_dpt8 { #2byte signed 
    my @val = split(" ",shift);
    my $val2 = (hex($val[0])<<8) + hex($val[1]);
    return $val2 > 32767 ? $val2-65536 : $val2;
}

sub decode_dpt10 { #3byte time
    my @val = split(" ",shift);
    my @wd = qw(Null Mo Di Mi Do Fr Sa So);
    $val[0] = hex($val[0]);
    $val[1] = hex($val[1]);
    $val[2] = hex($val[2]);
    unless ($val[2]) { return; }
    my $day = ($val[0] & 0xE0) >> 5;
    my $hour    = $val[0] & 0x1F;
    my $minute  = $val[1];
    my $second  = $val[2];
    return sprintf("%s %02i:%02i:%02i",$wd[$day],$hour,$minute,$second);
}

sub decode_dpt11 { #3byte date
    my @val = split(" ",shift);
    my @wd = qw(Null Mo Di Mi Do Fr Sa So);
    $val[0] = hex($val[0]);
    $val[1] = hex($val[1]);
    $val[2] = hex($val[2]);
    unless ($val[2]) { return; }
    my $mday    = $val[0] & 0x1F;
    my $mon     = $val[1] & 0x0F;
    my $year    = $val[2] & 0x7F;
    $year = $year < 90 ? $year+2000 : $year+1900; # 1990 - 2089
    return sprintf("%04i-%02i-%02i",$year,$mon,$mday);
}

sub decode_dpt12 { #4byte unsigned 
    my @val = split(" ",shift);
    return (hex($val[0])<<24) + (hex($val[1])<<16) + (hex($val[2])<<8) + hex($val[3]);
}

sub decode_dpt13 { #4byte signed 
    my @val = split(" ",shift);
    my $val2 = (hex($val[0])<<24) + (hex($val[1])<<16) + (hex($val[2])<<8) + hex($val[3]);
    return $val2 >  2147483647 ? $val2-4294967296 : $val2;
}

sub decode_dpt14 { #4byte float
    #Perls unpack for float is somehow strange broken
    my @val = split(" ",shift);
    my $val2 = (hex($val[0])<<24) + (hex($val[1])<<16) + (hex($val[2])<<8) + hex($val[3]);
    my $sign = ($val2 & 0x80000000) ? -1 : 1;
    my $expo = (($val2 & 0x7F800000) >> 23) - 127;
    my $mant = ($val2 & 0x007FFFFF | 0x00800000);
    my $num = $sign * (2 ** $expo) * ( $mant / (1 << 23));
    return sprintf("%.4f",$num);
}

sub decode_dpt16 { # 14byte char
    my @val = split(" ",shift);
    my $chars;
    for (my $i=0;$i<14;$i++) {
        $chars .= sprintf("%c", hex($val[$i]));
    }
    return sprintf("%s",$chars);
}

sub encode_dpt5 {
    my $value = shift;
    $value = 100 if ($value > 100);
    $value = 0 if ($value < 0);;
    my $byte = sprintf ("%.0f", $value * 255 / 100);
    return($byte);
}

sub decode_dpt {
    my $dst = shift;
    my $data = shift;
    my $dpt = shift;
    my $value;
    my $dptid = $eibgaconf{$dst}{'DPTSubId'} || $dpt || 0;
    ($debug) and print STDERR "DBG:decode_dpt, dptid[$dptid], data[$data]\n";
    $data  =~ s/\s+$//g;
    switch ($dptid) {
        case /^10/      { $value = decode_dpt10($data) }
        case /^11/      { $value = decode_dpt11($data) }
        case /^12/      { $value = decode_dpt12($data) }
        case /^13/      { $value = decode_dpt13($data) }
        case /^14/      { $value = decode_dpt14($data) }
        case /^16/      { $value = decode_dpt16($data) }
        case /^\d\d/    { return; } # other DPT XX 15 are unhandled
        case /^1/       { $value = int($data) }
        case /^2/       { $value = int($data) } # somehow wrong 2bit
        case /^3/       { $value = int($data) } # somehow wrong 4bit
        case /^4/       { $value = decode_dpt4($data) } 
        case [5,5.001]  { $value = decode_dpt5($data) }
        case [5.004,5.005,5.010] { $value = decode_dpt510($data) }
        case /^6/ { $value = decode_dpt6($data) }
        case /^7/ { $value = decode_dpt7($data) }
        case /^8/ { $value = decode_dpt8($data) }
        case /^9/ { $value = decode_dpt9($data) }
        else   { return; } # nothing
    }
    return $value;
}

sub knx_read {
    my $dst = $_[0];
    my $age = $_[1] || 0; # read hot unless defined
    my $dpt = $_[2];

#    ($debug) and print "1[$dst], 2[$age], 3[$dpt]\n";

    my $src=EIBConnection::EIBAddr();
    my $buf=EIBConnection::EIBBuffer();
    my $hexbytes;
    my $leibcon = EIBConnection->EIBSocketURL($eib_url) or return("Error: $!");
    my $res=$leibcon->EIB_Cache_Read_Sync(str2addr($dst), $src, $buf, $age);
    if (!defined $res) { return; } # ("ReadError: $!");
    $leibcon->EIBClose();
    # $$src contains source PA
    
    my @data = unpack ("C" . bytes::length($$buf), $$buf);
    if ($res == 2) { # 6bit only
        return sprintf("%02X", ($data[1] & 0x3F));
    } else {
        for (my $i=2; $i<= $res-1; $i++) {
            $hexbytes = $hexbytes . sprintf("%02X ", ($data[$i]));
        }
        return decode_dpt($dst,$hexbytes,$dpt);
    } 
}

# ------------- main

usage() if ( ! GetOptions  ('help|h|?' => \$help, 
			    'd|dump'   => \$dump_arg,
			    'r|read'   => \$read_arg,
                            'ga|g=s'   => \$ga_arg,
                            'age|a=i'  => \$age_arg,
                            'dpt|t=s'  => \$dpt_arg
	     )
	     or defined $help );

if (-e '/etc/wiregate/eibga.conf') 
{ 
    my_read_cfg '/etc/wiregate/eibga.conf' => %eibgaconf;
} 
else 
{
    print "WARNUNG: unable to read config[/etc/wiregate/eibga.conf]\n";
}


if ($dump_arg)
{   
    if ($ga_arg) {
	printGaInfo($ga_arg);
    } else {
	dumpGa($ga_arg);
    }

    exit;
}

if ($read_arg)
{
    if (!defined $ga_arg)
    {
	print "FEHLER: Fuer READ bitte die Gruppenadresse angeben (EINGABETASTE druecken ...).";
	getc(STDIN);
	exit;
    }

    if (!defined $dpt_arg && !exists $eibgaconf{$ga_arg})
    {
	print "FEHLER: Unbekannte Gruppenadresse, bitte Datentyp angegeben (EINGABETASTE druecken ...).";
	getc(STDIN);
	exit;
    }

    (!$age_arg) and $age_arg = 1;

    my $res = knx_read($ga_arg, $age_arg, $dpt_arg);
    if ($res)
    {
	print "GELESEN:ga[$ga_arg], res[$res]\n";
    }
    else
    {
	print "FEHLER: READ ga[$ga_arg]\n";
    }
    exit;
}

die "\n\nFEHLER: weder --read noch --dump angegeben\n\n";

=pod

=head1 NAME

B<knxquery.pl> -- Einen Wert vom KNX-Bus lesen

=head1 UEBERSICHT

B<knxquery.pl> -h 

B<knxquery.pl> -r -g GA [-a AGE] [-t DPT]

B<knxquery.pl> -d [-g GA]

 
=head1 BESCHREIBUNG

B<knxquery.pl> liest einen Wert vom  KNX-Bus und gibt diesen auf stdout aus.

=head1 OPTIONEN

=over

=item B<-h | --help>  Anzeige dieser Hilfe.

=item B<-r | --read>  Liest einen Wert vom KNX-Bus. Die Gruppenandresse B<GA> 
muss angegeben werden. Wenn die Gruppenadresse nicht in der Konfiguration 
hinterlegt ist, muss ausserdem der datentyp B<DPT> angegeben werden.

=item B<-d | --dump>  Gibt Informationen zu einer oder zu allen Gruppenadressen
aus.  Wird eine B<GA> angegeben, werden Informationen nur zu dieser Adresse
ausgegeben. Wird keine Gruppenadresse angegeben, werden Informationen zu allen
konfigurierten Adressen ausgegeben. 

=item B<-g | --ga> Angabe der Gruppenadresse B<GA> deren Wert zu lesen ist  
oder zu der Informationen ausgegeben werden sollen. Die Adresse muss im 
Format B<H/M/U>, angegeben werden, wobei B<H> die Hauptgruppe, B<M> die 
Mittelgruppe und B<U> die Untergruppe ist.

=item B<-a | --age> Maximales Cache-Alter B<AGE> des zu lesenden Wertes in Sekunden. 
Unterlassungswert ist 1 Sekunde.

=item B<-t | --dpt>   Angabe des Datentyps B<DPT>. Dieser Wert muss nur 
angegeben werden, wenn die Gruppenadresse nicht in der Konfiguration 
erfasst ist. Es reicht der Haupttyp, also z.B. B<1, 2, 3> ... usw.

=back

=head1 VORAUSSETZUNGEN

Das Script wurde für das B<Wiregate> Gateway geschrieben, und erwartet eine 
diesem Gateway entsprechende Konfiguration. Der Rechner muss an einen KNX-Bus
angeschlossen sein, und Zugriff auf diesen Bus haben, z.B. per EIB-TPUART. 

=head1 MITWIRKENDE

Teile des Scripts sind Copyright Michael Markstaller 

=head1 COPYRIGHT

Copyright (c) 2011 Edgar <emax> Hermanns, <emax at berlios punkt de>

=cut
