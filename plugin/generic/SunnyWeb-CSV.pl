# Plugin zur Abfrage einer Sunny Webbox-2 (BT) via FTP/CSV
# V 1.1 2012-05-03
# Aufbau moeglichst so, dass man unterhalb der Definitionen nichts aendern muss!
# Der Abruf des CSV ist recht langsam, daher erledigt das ein Shell-script/Crontab:
# Das CSV wird nicht analysiert sondern nur fixe Positionen angesprungen,
# da unterschiedliche WR unterschiedlich viele Werte liefern

##################
### DEFINITION ###
##################
$plugin_info{$plugname.'_cycle'} = 300; # Eigenen Aufruf-Zyklus setzen 

my @Werte = (
{ Name => "G_Metering.TotWhOut",    GA => "10/1/1",  DPT => "13", Column => 1, Type => "COUNTER"},
{ Name => "G_Operation.GriSwCnt",   GA => "10/1/2",  DPT => "13", Column => 2, Type => "COUNTER"},
{ Name => "G_GridMs.TotW",          GA => "10/1/3",  DPT => "14", Column => 5, Type => "GAUGE"},

{ Name => "210_Metering.TotWhOut",  GA => "10/1/11", DPT => "13", Column => 22, Type => "COUNTER"},
{ Name => "210_Operation.GriSwCnt", GA => "10/1/12", DPT => "13", Column => 23, Type => "COUNTER"},
{ Name => "210_Metering.TotOpTms",  GA => "10/1/13", DPT => "13", Column => 24, Type => "COUNTER"},
{ Name => "210_Metering.TotFeedTms",GA => "10/1/14", DPT => "13", Column => 25, Type => "COUNTER"},
{ Name => "210_GridMs.TotW",        GA => "10/1/15", DPT => "14", Column => 26, Type => "GAUGE"},
{ Name => "210_GridMs.Hz",          GA => "10/1/16", DPT => "14", Column => 27, Type => "GAUGE"},
{ Name => "210_Isolation.FltA",     GA => "10/1/17", DPT => "9",  Column => 28, Type => "GAUGE"},
{ Name => "210_Isolation.LeakRis",  GA => "10/1/18", DPT => "14", Column => 29, Type => "GAUGE"},
{ Name => "210_DcMs.Vol_A",         GA => "10/1/19", DPT => "14", Column => 30, Type => "GAUGE"},
{ Name => "210_DcMs.Amp_A",         GA => "10/1/21", DPT => "14", Column => 31, Type => "GAUGE"},
{ Name => "210_GridMs.PhV.phsA",    GA => "10/1/23", DPT => "14", Column => 32, Type => "GAUGE"},
{ Name => "210_GridMs.A.phsA",      GA => "10/1/26", DPT => "14", Column => 33, Type => "GAUGE"},
{ Name => "210_DcMs.Watt_A",        GA => "10/1/29", DPT => "13", Column => 34, Type => "GAUGE"},

{ Name => "211_Metering.TotWhOut",  GA => "10/1/41", DPT => "13", Column => 39, Type => "COUNTER"},
{ Name => "211_Operation.GriSwCnt", GA => "10/1/42", DPT => "13", Column => 40, Type => "COUNTER"},
{ Name => "211_Metering.TotOpTms",  GA => "10/1/43", DPT => "13", Column => 41, Type => "COUNTER"},
{ Name => "211_Metering.TotFeedTms",GA => "10/1/44", DPT => "13", Column => 42, Type => "COUNTER"},
{ Name => "211_GridMs.TotW",        GA => "10/1/45", DPT => "14", Column => 43, Type => "GAUGE"},
{ Name => "211_GridMs.Hz",          GA => "10/1/46", DPT => "14", Column => 44, Type => "GAUGE"},
{ Name => "211_Isolation.FltA",     GA => "10/1/47", DPT => "9",  Column => 45, Type => "GAUGE"},
{ Name => "211_Isolation.LeakRis",  GA => "10/1/48", DPT => "14", Column => 46, Type => "GAUGE"},
{ Name => "211_DcMs.Vol_A",         GA => "10/1/49", DPT => "14", Column => 47, Type => "GAUGE"},
{ Name => "211_DcMs.Vol_B",         GA => "10/1/10", DPT => "14", Column => 48, Type => "GAUGE"},
{ Name => "211_DcMs.Amp_A",         GA => "10/1/51", DPT => "14", Column => 49, Type => "GAUGE"},
{ Name => "211_DcMs.Amp_B",         GA => "10/1/52", DPT => "14", Column => 50, Type => "GAUGE"},
{ Name => "211_GridMs.PhV.phsA",    GA => "10/1/53", DPT => "14", Column => 51, Type => "GAUGE"},
{ Name => "211_GridMs.PhV.phsB",    GA => "10/1/54", DPT => "14", Column => 52, Type => "GAUGE"},
{ Name => "211_GridMs.PhV.phsC",    GA => "10/1/55", DPT => "14", Column => 53, Type => "GAUGE"},
{ Name => "211_GridMs.A.phsA",      GA => "10/1/56", DPT => "14", Column => 54, Type => "GAUGE"},
{ Name => "211_GridMs.A.phsB",      GA => "10/1/57", DPT => "14", Column => 55, Type => "GAUGE"},
{ Name => "211_GridMs.A.phsC",      GA => "10/1/58", DPT => "14", Column => 56, Type => "GAUGE"},
{ Name => "211_DcMs.Watt_A",        GA => "10/1/59", DPT => "13", Column => 57, Type => "GAUGE"},
{ Name => "211_DcMs.Watt_B",        GA => "10/1/60", DPT => "13", Column => 58, Type => "GAUGE"}
);

#Daten von Referenzanlage/CSV:
#0;1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;18;19;20;21;22;23;24;25;26;27;28;29;30;31;32;33;34;35;36;37;38;39;40;41;42;43;44;45;46;47;48;49;50;51;52;53;54;55;56;57;58;59;60;61;62
#<SN>
#;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;WebBox-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;SB 3000TL-20;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10;STP 12000TL-10
#<SN>
#;Metering.TotWhOut;Operation.GriSwCnt;Metering.TotOpTms;Metering.TotFeedTms;GridMs.TotW;GridMs.Hz;Isolation.FltA;Isolation.LeakRis;DcMs.Vol[A];DcMs.Vol[B];DcMs.Amp[A];DcMs.Amp[B];GridMs.PhV.phsA;GridMs.PhV.phsB;GridMs.PhV.phsC;GridMs.A.phsA;GridMs.A.phsB;GridMs.A.phsC;DcMs.Watt[A];DcMs.Watt[B];Operation.Health;Metering.TotWhOut;Operation.GriSwCnt;Metering.TotOpTms;Metering.TotFeedTms;GridMs.TotW;GridMs.Hz;Isolation.FltA;Isolation.LeakRis;DcMs.Vol[A];DcMs.Amp[A];GridMs.PhV.phsA;GridMs.A.phsA;DcMs.Watt[A];Operation.Health;Operation.Evt.Prio;Operation.Evt.Msg;Operation.Evt.Dsc;Metering.TotWhOut;Operation.GriSwCnt;Metering.TotOpTms;Metering.TotFeedTms;GridMs.TotW;GridMs.Hz;Isolation.FltA;Isolation.LeakRis;DcMs.Vol[A];DcMs.Vol[B];DcMs.Amp[A];DcMs.Amp[B];GridMs.PhV.phsA;GridMs.PhV.phsB;GridMs.PhV.phsC;GridMs.A.phsA;GridMs.A.phsB;GridMs.A.phsC;DcMs.Watt[A];DcMs.Watt[B];Operation.Health;Operation.Evt.Prio;Operation.Evt.Msg;Operation.Evt.Dsc
#;Counter;Counter;Counter;Counter;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Status;Counter;Counter;Counter;Counter;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Status;Status;Status;Status;Counter;Counter;Counter;Counter;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Analog;Status;Status;Status;Status
#dd.MM.yyyy HH:mm;kWh;;h;h;W;Hz;mA;kOhm;V;V;A;A;V;V;V;A;A;A;W;W;;kWh;;h;h;W;Hz;mA;kOhm;V;A;V;A;W;;;;;kWh;;h;h;W;Hz;mA;kOhm;V;V;mA;mA;V;V;V;A;A;A;W;W;;;;
#03.05.2012 14:40;3804,60;407,00;3137,63;2838,07;4594,00;49,96;9,00;3000,00;291,54;527,14;5,54;2,71;232,54;231,42;233,42;4,76;5,11;5,12;3305,00;1434,00;Ok;881,10;221,00;1515,96;1357,44;1038,00;49,96;6,00;3000,00;203,98;5,21;234,31;4,42;1066,00;Ok;NonePrio;None;None;2923,50;186,00;1621,67;1480,63;3556,00;49,96;12,00;3000,00;379,11;527,14;5874,00;2712,00;230,78;231,42;233,42;5,09;5,11;5,12;2239,00;1434,00;Ok;NonePrio;None;None
#root@wiregateXXX:~# cat /usr/local/bin/sunny-getcsv.sh
# #!/bin/sh
#FILE="CSV/$(date +%Y/%m/%Y-%m-%d).csv"
#USER="Installer"
#PASS="1234"
#IP="192.168.0.110"
#curl "ftp://$USER:$PASS@$IP/$FILE" | tail -n 1 > /tmp/sunny.csv
#curl "http://$IP/culture/login?Language=LangDE&Userlevels=$USER&password=$PASS" > /tmp/sunny.xml

#chmod a+x /usr/local/bin/sunny-getcsv.sh
#crontab -l
# m h  dom mon dow   command
#*/6 * * * *  /usr/local/bin/sunny-getcsv.sh >/dev/null 2>&1

# 13.010 DPT_ActiveEnergy [-2 147 483 648 ... 2 147 483 647] Wh - 4 byte signed
# 14.056 DPT_Value_Power W  - 4 byte float

#######################
### ENDE DEFINITION ###
#######################

# Hauptverarbeitung
open (CSV, '/tmp/sunny.csv');
my @line;
while (<CSV>) {
    chomp;
    next unless $_; # protect empty lines
    @line = split /;/, $_;
}
close (CSV); 

foreach ( @Werte ) {
    $line[$_->{Column}] =~ s/\.//g;
    $line[$_->{Column}] =~ s/,/\./;
    knx_write($_->{GA}, $line[$_->{Column}], $_->{DPT});
    $line[$_->{Column}] *= 3600 if ($_->{Type} eq "COUNTER");
    update_rrd($_->{Name},"",$line[$_->{Column}], $_->{Type});
}


@line=();
undef @line;
@Werte=();
undef @Werte;

return "Updated";

