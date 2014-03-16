<?php
 
define('DATABASE_NAME', "/tmp/wiregate_plugin.db");
define('RECORD_KEY', $_GET["name"]);
 
$dbID = dba_open(DATABASE_NAME, "rlt", "db4");
 
if (!$dbID) {
    echo "{} dba_open failed";
    exit;
} else {
header('Content-type: application/json; charset=utf-8');
}

if (dba_exists(RECORD_KEY, $dbID)) {
    $result = dba_fetch(RECORD_KEY, $dbID);
    $data = array (RECORD_KEY=>$result);
    echo json_encode($data);
}
 
dba_close($dbID);
