#!/bin/bash

# Skip if OIDC is not configured
if [ -z "${OIDC_PROVIDER_URL:-}" ] || [ -z "${OIDC_CLIENT_ID:-}" ] || [ -z "${OIDC_CLIENT_SECRET:-}" ]; then
    echo "OIDC env vars not set — skipping OIDC configuration."
    exit 0
fi

cat > /var/www/html/config/oidc.config.php <<EOF
<?php
\$CONFIG = [
  'oidc_login_disable_registration' => false,
  'oidc_login_end_session_redirect' => true,
  'oidc_login_logout_url'           => getenv('OIDC_LOGOUT_URL'),
  'oidc_login_provider_url'     => getenv('OIDC_PROVIDER_URL'),
  'oidc_login_client_id'        => getenv('OIDC_CLIENT_ID'),
  'oidc_login_client_secret'    => getenv('OIDC_CLIENT_SECRET'),
  'oidc_login_scope'            =>  getenv('OIDC_LOGIN_SCOPE'),
  'oidc_login_code_challenge_method' => 'S256',
  'oidc_login_attributes' => [
    'id'     => 'sub',
    'name'   => 'name',
    'mail'   => 'email',
    'groups' => 'groups',
    'quota'  => 'quota',
  ],
  'oidc_login_auto_redirect'      => false,
  'oidc_login_redir_fallback'     => true,
  'oidc_login_button_text'        => 'Log in with Authentik',
  'oidc_login_hide_password_form' => false,
  'oidc_login_tls_verify'         => true,
  'oidc_login_default_quota'      => '5368709120',
];
EOF

chown 33:33 /var/www/html/config/oidc.config.php
chmod 640   /var/www/html/config/oidc.config.php
