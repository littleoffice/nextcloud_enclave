#!/bin/bash
set -e

APPS=(
  oidc_login
  calendar
  contacts
  tasks
  notes
  mail
)

echo "Installing apps"

installed_apps=$(php occ app:list)

for app in "${APPS[@]}"; do
  echo "Processing $app"

  if ! echo "$installed_apps" | grep -qw "$app"; then
    php occ app:install "$app" || true
  fi

  php occ app:enable "$app" || true
done

echo "Done."
