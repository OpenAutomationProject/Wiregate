## Dieses Plugin steuert die Rolläden
# http://knx-user-forum.de/wiregate/16384-plugin-rolladen-lueftungsposition.html
## Rolladen unten + Fenster auf >> Rolladen in Lüftungsposition fahren 
## Globale Definitionen ##
my $zustand_geschlossen = 00;              # Wert Fensterstatus geschlossen
my $zustand_offen = 01;                    # Wert Fensterstatus geöffnet
my $GA_Gesamt_SperreAuto = '3/0/4';        # Gruppenadresse, die die Lüftungsautomatik sperrt
#Definition aller Rolläden über ein Array von Hashes, wobei jeder Hash ein Rollladen/Fenster ist.
my @AlleRolllaeden;
# Name               = Name des Rolladen
# GA_Fensterstatus   = Gruppenadresse für Öffnungsüberwachung des Fensters
# GA_RolloUnten      = Gruppenadresse für Meldung, daß Rolladen ganz runter gefahren wurde
# GA_RolloPos        = Gruppenadresse zum Anfahren einer Position
# GA_RolloAufAb      = Gruppenadresse zu Auf/Abfahren des Rollos 
# GA_RolloPosInfo    = Gruppenadresse auf der die Rückmeldung der Position erfolgt 
# PosRolloLuft       = Position des Rolladen im % für Lüftungsposition
push @AlleRolllaeden, { Name => "Schlafzimmer", GA_Fensterstatus => "6/2/50", GA_RolloUnten => "3/2/57", GA_RolloPos => "3/2/52",
                        GA_RolloAufAb => "3/2/50", GA_RolloPosInfo => "3/2/55", PosRolloLuft => 70};
push @AlleRolllaeden, { Name => "Bad", GA_Fensterstatus => "6/2/90", GA_RolloUnten => "3/2/97", GA_RolloPos => "3/2/92",
                        GA_RolloAufAb => "3/2/90", GA_RolloPosInfo => "3/2/95", PosRolloLuft => 85}; 
push @AlleRolllaeden, { Name => "Kind A", GA_Fensterstatus => "6/2/130", GA_RolloUnten => "3/2/137", GA_RolloPos => "3/2/132",
                        GA_RolloAufAb => "3/2/130", GA_RolloPosInfo => "3/2/135", PosRolloLuft => 85};
push @AlleRolllaeden, { Name => "Kind B", GA_Fensterstatus => "6/2/170", GA_RolloUnten => "3/2/177", GA_RolloPos => "3/2/172",
                        GA_RolloAufAb => "3/2/170", GA_RolloPosInfo => "3/2/175", PosRolloLuft => 96};
push @AlleRolllaeden, { Name => "Arbeitszimmer Fenster", GA_Fensterstatus => "6/2/220", GA_RolloUnten => "3/2/227", GA_RolloPos => "3/2/222",
                        GA_RolloAufAb => "3/2/220", GA_RolloPosInfo => "3/2/225", PosRolloLuft => 70};
push @AlleRolllaeden, { Name => "Arbeitszimmer Tuer", GA_Fensterstatus => "6/2/230", GA_RolloUnten => "3/2/237", GA_RolloPos => "3/2/232",
                        GA_RolloAufAb => "3/2/230", GA_RolloPosInfo => "3/2/235", PosRolloLuft => 80};
 
## Plugin nur bei Telegramm aufrufen
$plugin_info{$plugname.'_cycle'} = 0; # nur bei Telegramm aufrufen
 
## Rolladensperre beachten
#Anmeldung an Gruppenadresse für Rolladensperre
$plugin_subscribe{$GA_Gesamt_SperreAuto}{$plugname} = 1; 
#Sperrkennzeichen setzen, wenn Telegramm eintrifft
if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $GA_Gesamt_SperreAuto) {
    $plugin_info{$plugname.'_sperre'} = knx_read($GA_Gesamt_SperreAuto,0,1);  
    }
#Wenn Sperrkennzeichen gesetzt ist, dann soll der Code beendet werden
if ($plugin_info{$plugname.'_sperre'} == 1) {
    return "Sperre";   
    }
 
##Ausführen des Codes je definiereten Rolladen
foreach my $element (@AlleRolllaeden) {
 
    #Anmeldung an Gruppenadresse für Fensterstatus
    $plugin_subscribe{$element->{GA_Fensterstatus}}{$plugname} = 1;    
 
    #Anmeldung an Gruppenadresse für Status, daß Rolladen unten 
    $plugin_subscribe{$element->{GA_RolloUnten}}{$plugname} = 1;       
 
    #Wenn Telegramm für Fensterstatus, Rollo unten oder Sperre eintrifft, dann soll das Rollo ggf. bewegt werden
    if ($msg{'apci'} eq "A_GroupValue_Write" and 
       ($msg{'dst'} eq $element->{GA_Fensterstatus} or $msg{'dst'} eq $element->{GA_RolloUnten}) or $msg{'dst'} eq $GA_Gesamt_SperreAuto) {
 
      my $Fensterstatus = knx_read($element->{GA_Fensterstatus}, 300, 1);   #Lesen Fensterstatus
      my $RolloUnten = knx_read($element->{GA_RolloUnten} ,300, 1);         #Lesen ob Rolladen unten
      my $RolloPosInfo = knx_read($element->{GA_RolloPosInfo}, 300, 5.001); #Lesen der aktuellen Rolladenpositon in %  
 
      #Wenn Fenster=zu und Rolladen innerhalb Lüftung, dann soll der Rollo komplett runter gefahren werden
      if (($Fensterstatus==$zustand_geschlossen ) && ($RolloPosInfo >= $element->{PosRolloLuft}) && ($msg{'dst'} eq $element->{GA_Fensterstatus} )) {
        knx_write($element->{GA_RolloAufAb} , 1, 1);
        return "Ab";
        }
 
      #Wenn Fenster=offen und Rolladen komplet unten, dann soll der Rollo in die Lüftungsposition gefahren werden
      if (($Fensterstatus==$zustand_offen) && ($RolloUnten==1)) {
        knx_write($element->{GA_RolloPos}, $element->{PosRolloLuft}, 5.001);
        return "Lüftung";  
        }
      }
    }      
 
#Rückgabewert falls noch kein Telegramm eingetroffen ist
return "Warte";
