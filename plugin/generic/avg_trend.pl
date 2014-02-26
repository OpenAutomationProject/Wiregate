# Trend Tendenz Average für Gauge
# by NetFritz 02/2014
# Das Plugin wird von den Gradr getriggert, die in die rrd's schreiben.
# (@ga_ins und $ga_in_avg)
# in Gradr @ga_out wird der Trend für Gauge geschrieben
# in Gradr $ga_out_avg wird Average für Windrichtung geschrieben.
$plugin_info{$plugname.'_cycle'} = 0;
my $ga_in;
# die folgenden Array muessen zusammenpassen
# also "temp" mit "0/2/1" und "0/2/11"
my @rrds = ("temp","feuchte","baro","windst");     # rrd die ausgelesen werden
my @ga_ins = ("0/2/1","0/2/2","0/2/3","0/2/6");    # ueberwachte GAs
my @ga_out= ("0/2/11","0/2/12","0/2/13","0/2/16"); # GAs fuer Trend
#
my $ga_in_avg = "0/2/5";  # Ga in Windrichtung
my $ga_out_avg = "0/2/7"; # Ga out Windrichtung
#
$plugin_subscribe{$ga_in_avg}{$plugname} = 1;
foreach $ga_in(@ga_ins)
{
$plugin_subscribe{$ga_in}{$plugname} = 1;        # GAs registrieren
}
my $i = 0;
if ($msg{'apci'} eq "A_GroupValue_Write") {      # A_GroupValue_Write Telegramm eingetroffen
   foreach $ga_in(@ga_ins){                      # Ueberwachte GAs durchlaufen
      if ($msg{'dst'} eq $ga_in){                # GAs vergleichen
          my $gen1 = 'rrdtool graph /dev/null --start -3600 --end now DEF:var1=/var/www/rrd/'.$rrds[$i].'.rrd:value:AVERAGE PRINT:var1:AVERAGE:"%3.4lf"' ;
          my $gen2 = 'rrdtool graph /dev/null --start -300 --end now DEF:var1=/var/www/rrd/'.$rrds[$i].'.rrd:value:AVERAGE PRINT:var1:AVERAGE:"%3.4lf"' ;         
          my @out1 = `$gen1`;
          my @out2 = `$gen2`;
          my $out11 =  sprintf ("%.1f",$out1[1]);
          my $out21 =  sprintf ("%.1f",$out2[1]);
          my $trend = sprintf ("%.1f",$out21-$out11);
          knx_write($ga_out[$i],$trend,"9");
          plugin_log($plugname ,$ga_out[$i]." out=".$out11. " tr=".$trend);
      }
      if ($msg{'dst'} eq $ga_in_avg){   
        # den Std AVG fuer Windrichtung aus rrd holen
        my @output = `rrdtool graph /dev/null --start -3600 --end now DEF:var1=/var/www/rrd/windrich.rrd:value:AVERAGE PRINT:var1:AVERAGE:"%3.4lf"` ;
        my $output1 =  sprintf ("%.1f",$output[1]);
        knx_write("0/2/7",$output1,"9");
      }
      $i++;
    }  
}    
return();