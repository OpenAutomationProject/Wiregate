# Buswerte in RRD speichern
# V2.0 2012-08-16
# Info und Konfiguration in /etc/wiregate/plugin/generic/conf.d/RRD_creator.conf_sample
# Eigene Konfiguration speichern unter /etc/wiregate/plugin/generic/conf.d/RRD_creator.conf
# Alternativ über Webmin -> Plugins -> Pluginname -> config

# Variablen deklarieren
my @rrds;
# conf einlsen
&readConf;
# Aufrufzyklus = Heartbeat RRD
$plugin_info{$plugname.'_cycle'} = 300;

# MAIN

foreach my $rrd (@rrds) {
update_rrd($rrd->{name},"",knx_read($rrd->{ga},300,$rrd->{dpt}));
#plugin_log($plugname, "triggered $rrd->{name}");
}

return;

# SUBS
sub readConf
{
 my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
 if (! -f $confFile) {
   
 } else {
  #plugin_log($plugname, "reading conf file [$confFile]."); 
  open(CONF, $confFile);
  my @lines = <CONF>;
  close($confFile);
  my $result = eval("@lines");
  #($result) and plugin_log($plugname, "conf file [$confFile] returned result[$result]");
  if ($@) {
   plugin_log($plugname, "ERR: conf file [$confFile] returned:");
   my @parts = split(/\n/, $@);
   plugin_log($plugname, "--> $_") foreach (@parts);
  }
 }
}