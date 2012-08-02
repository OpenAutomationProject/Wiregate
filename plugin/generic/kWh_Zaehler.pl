# Errechnet die kWhs aus dem Aktor-Strom. 
# Jedesmal wenn ein neuer Stromwert auf der GA gesendet wird
# wird eine neue Rechnung durchgeführt,
# gerechnet wird nach dieser Formel
# kWh = I(mA)/1000*230V* cos_phi * Delta_Zeit s/3600 * 1/1000
# by NetFritz 07/2012
# http://knx-user-forum.de/wiregate/21343-kwh-zaehler-aus-dem-aktor-strom.html
#
my $cos_phi = 0.95;
my $Volt = 230;
my @Zaehler_config;
$plugin_info{$plugname.'_cycle'} = 0;
# Konfigurationsfile einlesen
my $conf=$plugname; $conf=~s/\.pl$/.conf/;
$conf="/etc/wiregate/plugin/generic/conf.d/$conf";
my %zaehler=();
my $err=read_from_config();
return $err if $err;
#------------------------------------------------------
# Alle I_GAs aus der config abonnieren
for my $r (grep ref($zaehler{$_}), keys %zaehler)
   {
      $plugin_subscribe{$zaehler{$r}{I_GA}}{$plugname}=1;
   } 
# BUS ueberwachen 
if ($msg{'apci'} eq "A_GroupValue_Write") {            # A_GroupValue_Write Telegramm eingetroffen
   for my $r (grep ref($zaehler{$_}), keys %zaehler){  # Ueberwachte GAs durchlaufen
      if ($msg{'dst'} eq $zaehler{$r}{I_GA}){          # GAs vergleichen
        my $time_delta = time() - $plugin_info{$plugname.$zaehler{$r}{name} . '_time'};
        my $I = $plugin_info{$plugname.$zaehler{$r}{name} . '_I'};
        my $kWh = $plugin_info{$plugname.$zaehler{$r}{name} . '_kWh'} + (($I/1000) * $Volt * $cos_phi * ($time_delta/3600));
        $plugin_info{$plugname. $zaehler{$r}{name} . '_I'} = $msg{'value'}/1000; # I mA ablegen 
        $plugin_info{$plugname. $zaehler{$r}{name} . '_time'} = time();          # Timestamp ablegen
        $plugin_info{$plugname. $zaehler{$r}{name} . '_kWh'} = $kWh;             # kWh ablegen
        knx_write($zaehler{$r}{kWh_GA},$kWh*1000,$zaehler{$r}{kWh_DPT});
        return($zaehler{$r}{kWh_GA} . "=" . $kWh);
      }
   }    
}else{
   for my $r (grep ref($zaehler{$_}), keys %zaehler){  # Ueberwachte GAs durchlaufen
      # knx_write($zaehler{$r}{kWh_GA},$plugin_info{$plugname.$zaehler{$r}{name} . '_kWh'},$zaehler{$r}{kWh_DPT});
   }
}
# 
return;  
# ------------- config einlesen ----------------------
sub read_from_config
  {
  open CONFIG, "<$conf" || return "no config found";
     my @lines = <CONFIG>;
  close CONFIG;
  eval("@lines");
  return "config error" if $@;
}

