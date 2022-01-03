<?php
//LOGGER
function logger($result, $recordname, $displayname, $uuid, $catalog1, $catalog2, $catalog3, $manifest1, $manifest2, $manifest3, $manifest4) {   
	$log  = date("Y.m.d h:i:s") . " - " . $result . " - " . "IP:" . $_SERVER['REMOTE_ADDR'] . " RECORDNAME:" . $recordname . " UUID:" . $uuid . " DISPLAYNAME:" . $displayname . " CATALOG1:" . $catalog1 . " CATALOG2:" . $catalog2 . " CATALOG3:" . $catalog3 . " MANIFEST1:" . $manifest1 . " MANIFEST2:" . $manifest2 . " MANIFEST3:" . $manifest3 . " MANIFEST4:" . $manifest4 . PHP_EOL;
	file_put_contents('./log/munki-enroll.log', $log, FILE_APPEND);
}  
?>