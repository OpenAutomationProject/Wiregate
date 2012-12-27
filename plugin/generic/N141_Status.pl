# Siemens DALI Gateway N 141 (5WG1 141-1AB01) Dimmwertstatus EVG auswerten
# V1.0 2012-12-27
# Diego Clavadetscher (Fechter65)

### Definitionen 
### Hier werden die Werte/Gruppenadressen definiert
my $dimwertStatus_ga = "1/7/13"; #Dimmwert-Rückmelde-GA der DALI-Schnittstelle (KO 6)
my $dimwertStatus_wert = "1/7/13"; #Dimmwert-Rückmelde Wert
my @EVGs = #EVG gemäss der Parametereinstellung in der ETS

    ( 
      {Nr=>'1',  Name=> '4-Attika 40-Essen L403 Halo 1a',     GAeinausStatus=>'1/2/46', GAdimwertStatus=>'1/6/46'},
      {Nr=>'4',  Name=> '3-2.Stock 31-Büro L313/4',         GAeinausStatus=>'1/2/23', GAdimwertStatus=>'1/6/23'},
      {Nr=>'5',  Name=> '3-2.Stock 34-Korridor lks.',         GAeinausStatus=>'1/2/29', GAdimwertStatus=>'1/6/29'},
      {Nr=>'7',  Name=> '3-2.Stock 34-Korridor rts.',         GAeinausStatus=>'1/2/31', GAdimwertStatus=>'1/6/31'},
      {Nr=>'8',  Name=> '3-2.Stock 34-Treppe RGB gruen',     GAeinausStatus=>'1/2/35', GAdimwertStatus=>'1/6/35'},
      {Nr=>'9',  Name=> '3-2.Stock 34-Treppe RGB rot',         GAeinausStatus=>'1/2/36', GAdimwertStatus=>'1/6/36'},
      {Nr=>'10', Name=> '3-2.Stock 34-Treppe RGB blau',     GAeinausStatus=>'1/2/34', GAdimwertStatus=>'1/6/34'},
      {Nr=>'11', Name=> '3-2.Stock 36-Bad Kinder L362',     GAeinausStatus=>'1/2/40', GAdimwertStatus=>'1/6/40'},
      {Nr=>'12', Name=> '3-2.Stock 37-Bad Eltern L372Wa',     GAeinausStatus=>'1/2/42', GAdimwertStatus=>'1/6/42'},
      {Nr=>'13', Name=> '3-2.Stock 37-Bad Eltern L374WC',     GAeinausStatus=>'1/2/43', GAdimwertStatus=>'1/6/43'},
      {Nr=>'14', Name=> '4-Attika 40-Essen L403 Halo 2a',     GAeinausStatus=>'1/2/47', GAdimwertStatus=>'1/6/47'},
      {Nr=>'15', Name=> '4-Attika 40-Essen L403 Halo 3a',     GAeinausStatus=>'1/2/48', GAdimwertStatus=>'1/6/48'},
      {Nr=>'16', Name=> '4-Attika 40-Essen L403 Halo 4a',     GAeinausStatus=>'1/2/49', GAdimwertStatus=>'1/6/49'},
      {Nr=>'17', Name=> '4-Attika 40-Essen L403 Halo 5a',     GAeinausStatus=>'1/2/51', GAdimwertStatus=>'1/6/51'},
      {Nr=>'18', Name=> '4-Attika 40-Essen L403 Halo 7a',     GAeinausStatus=>'1/2/52', GAdimwertStatus=>'1/6/52'},
      {Nr=>'19', Name=> '4-Attika 40-Essen L403 Halo 8a',     GAeinausStatus=>'1/2/53', GAdimwertStatus=>'1/6/53'},
      {Nr=>'20', Name=> '4-Attika 41-Kueche L412 Durchgang',GAeinausStatus=>'1/2/57', GAdimwertStatus=>'1/6/57'},
      {Nr=>'21', Name=> '4-Attika 41-Kueche L414 Kochen',     GAeinausStatus=>'1/2/58', GAdimwertStatus=>'1/6/58'},
      {Nr=>'22', Name=> '4-Attika 41-Kueche L412 Vorbereitung', GAeinausStatus=>'1/2/59', GAdimwertStatus=>'1/6/59'},
      {Nr=>'24', Name=> '4-Attika 40-Essen L403 Halo 6a',     GAeinausStatus=>'1/2/50', GAdimwertStatus=>'1/6/50'},
      {Nr=>'25', Name=> '4-Attika 40-Essen L403 Halo 9a',     GAeinausStatus=>'1/2/74', GAdimwertStatus=>'1/6/74'},
      {Nr=>'27', Name=> '3-1.Stock 28-WhgEingang L281Tuer', GAeinausStatus=>'1/2/75', GAdimwertStatus=>'1/6/75'},
      {Nr=>'28', Name=> '3-1.Stock 28-WhgEingang L283hinten',GAeinausStatus=>'1/2/76', GAdimwertStatus=>'1/6/76'},
      {Nr=>'29', Name=> '3-1.Stock 28-WhgEingang L285Seite', GAeinausStatus=>'1/2/77', GAdimwertStatus=>'1/6/77'}
    );
my $element;
    
    
### Ende Definitionen
# Eigenen Aufruf-Zyklus auf 1T setzen
$plugin_info{$plugname.'_cycle'} = 86400; 
# Zyklischer Aufruf nach restart und alle 86400 sek., dient dem Anmelden an die Gruppenadresse

if ($msg{'apci'} eq "A_GroupValue_Write" ){
    if ($msg{'dst'} eq $dimwertStatus_ga){
        my $Variable= ($msg{'data'});
        my @EinzelBytes = split(/ /,$Variable);
        my $Dimmwert = hex($EinzelBytes[1]);
        my $EAStatus = 0;
        my $EVGroh = hex($EinzelBytes[0]);
        if ($EVGroh > 63) {
            $EAStatus = 1; 
            $EVGroh = ($EVGroh-64);
        }
        my $EVG = ($EVGroh+1);
#        plugin_log($plugname,'Variable: ' . $Variable );
#        plugin_log($plugname,'Links: ' . $EinzelBytes[0] );
#        plugin_log($plugname,'Rechts: ' . $EinzelBytes[1] );
#        plugin_log($plugname,'EVGroh: ' . $EVGroh );
#        plugin_log($plugname,'EVG: ' . $EVG );
#        plugin_log($plugname,'Status: ' . $EAStatus );
#        plugin_log($plugname,'Dimmwert: ' . $Dimmwert );
        foreach my $element (@EVGs) {
            if ($element->{Nr}==$EVG) {
                #Wert auf Bus schreiben
                knx_write($element->{GAeinausStatus}, $EAStatus,1);
                knx_write($element->{GAdimwertStatus}, $Dimmwert,5);
                last;
            }
        }
    }

} else { # zyklischer Aufruf
   # Plugin an Gruppenadresse "anmelden", hierdurch wird das Plugin im folgenden bei jedem eintreffen eines Telegramms auf die GA aufgerufen und der obere Teil dieser if-Schleife durchlaufen
   $plugin_subscribe{$dimwertStatus_ga}{$plugname} = 1;
}
return;

