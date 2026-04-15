#!/bin/sh
set -eu

OCC="php -f /var/www/html/occ"

$OCC app:install onlyoffice 

$OCC config:app:set onlyoffice DocumentServerUrl --value="https://onlyoffice.domain.tld/"
#$OCC config:app:set onlyoffice jwt_secret        --value="ONLYOFFICE_JWT_SECRET"
$OCC config:app:set onlyoffice defFormats  --value='{"odg":true,"odt":true,"ods":true,"odp":true,"doc":true,"xls":true,"ppt":true,"rtf":true,"txt":true,"csv":true}'
$OCC config:app:set onlyoffice editFormats --value='{"odt":true,"ods":true,"odp":true,"rtf":true,"txt":true,"csv":true}'

$OCC app:enable onlyoffice