#!/bin/sh
# the order of execution of post-installation scripts is either alphabetic or numerical. whiteboard would be executed after onlyoffice, but in case of self-hosted CAs onlyoffice is missing the CA trust during install and crashes the entire post-installation procedure, resulting in whiteboard not being installed at all. therefor the name board instead of whiteboard ...
# tl;dr there's reasons why this is here
set -eu

OCC="php -f /var/www/html/occ"

$OCC app:install whiteboard

$OCC config:app:set whiteboard collabBackendUrl --value="https://nextcloud.domain.tld/whiteboard"
#$OCC config:app:set whiteboard jwt_secret_key --value="SECRET"

$OCC app:enable whiteboard

