#!/bin/sh
set -eu

OCC="php -f /var/www/html/occ"

$OCC app:install eurooffice 

$OCC config:app:set eurooffice DocumentServerUrl --value="https://office.domain.tld/"
#$OCC config:app:set eurooffice jwt_secret        --value="EUROOFFICE_JWT_SECRET"
$OCC config:app:set eurooffice defFormats  --value='{"odg":true,"odt":true,"ods":true,"odp":true,"doc":true,"xls":true,"ppt":true,"rtf":true,"txt":true,"csv":true}'
$OCC config:app:set eurooffice editFormats --value='{"odt":true,"ods":true,"odp":true,"rtf":true,"txt":true,"csv":true}'

$OCC app:enable eurooffice