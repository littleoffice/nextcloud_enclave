#!/bin/sh
set -eu

cat /etc/ssl/certs/ca-certificates.crt > /var/www/html/resources/config/ca-bundle.crt

cat > /var/www/html/config/ca.config.php <<'EOF'
<?php
$CONFIG = [
  'cert_path' => '/etc/ssl/certs/ca-certificates.crt',
];
EOF

chown 33:33 /var/www/html/config/ca.config.php
chmod 640   /var/www/html/config/ca.config.php
