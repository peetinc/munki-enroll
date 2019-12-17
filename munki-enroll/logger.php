<?php

//LOGGER
function logger($result, $recordname, $displayname, $catalog, $manifest1, $manifest2, $manifest3, $manifest4) {   
	$log  = date("Y.m.j h:i:s") . " - " . $result . " - " . "IP:" . $_SERVER['REMOTE_ADDR'] . " RECORDNAME:" . $recordname . PHP_EOL.
	"           DISPLAYNAME:" . $displayname . " CATALOG:" . $catalog . " MANIFEST1:" . $manifest1 . " MANIFEST2:" . $manifest2 . " MANIFEST3:" . $manifest3 . " MANIFEST4:" . $manifest4 . PHP_EOL;
	file_put_contents('./log/munki-enroll.log', $log, FILE_APPEND);
}  

?>
