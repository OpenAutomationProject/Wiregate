# Wind Mittelwert
# V1.00 2011-02-02
# by Robert_Mini@knxuf

### Definitionen 
### Hier werden die Werte/Gruppenadressen definiert
## ------- Suntracer Daten ------- ##
my $Wind_aktuell_ga = "10/1/6";                  # 10/1/9 Gruppenadresse für Wind Max., Reset nach RRD schreiben
my $w_Intervall=30;                              # Zeitraum für gleitenden Mittelwert in Minuten
my $Wind_Mittelwert_senden_ga = "10/1/30";       # GA zum auf den Bus senden
### Ende Definitionen

$plugin_info{$plugname.'_cycle'} = 30;
my $w_max= $w_Intervall*60/$plugin_info{$plugname.'_cycle'}; 

my $Wind_aktuell=knx_read($Wind_aktuell_ga,10,9);
my $w = $plugin_info{$plugname.'_w_last'};         # Letzte Position im array lesen

# Array abrufen
my @Wind_History = unpack("(w/a*)*", $plugin_info{$plugname.'_Wind_History1'});

$Wind_History[$w]=$Wind_aktuell;
$w++;
if ($w > ($w_max-1)) {$w=0}
$plugin_info{$plugname.'_w_last'} = $w;                 # Naechste Position merken

# Array speichern
$plugin_info{$plugname.'_Wind_History1'} = pack("(w/a*)*", @Wind_History);  

# Mittelwert ermitteln
my $Summe = 0;
for my $i (0 .. ($w_max-1))  
  {
  $Summe = $Summe + $Wind_History[$i];
  }
my $Wind_Mittelwert = (1.0* $Summe / $w_max);

$Wind_Mittelwert = nearest(.2,$Wind_Mittelwert);

# Aktuellen Mittelwerrt auf den Bus schreiben
knx_write($Wind_Mittelwert_senden_ga,$Wind_Mittelwert,9);  

return;
# "Wind_Mittelwert $Wind_Mittelwert w ";

