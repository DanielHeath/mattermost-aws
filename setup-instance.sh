#!/bin/bash
set -exuo pipefail

CADDY_VERSION=2.7.6

MM_VERSION="9.4.2"
if [ "$(uname -p)" = 'x86_64' ] ; then
  ARCH="amd64"
else
  ARCH="arm64"
fi
PLAYBOOKS_VERSION="v1.39.1"

export DEBIAN_FRONTEND=noninteractive
apt-get remove -y snapd
apt update
apt-get install --no-install-recommends -y \
  jq \
  unzip \
  poppler-utils \
  postgresql postgresql-client \
  moreutils
apt autoremove -y

cd /tmp
wget "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -p).zip"
unzip "awscli-exe-linux-$(uname -p).zip"
./aws/install
rm -rf aws "awscli-exe-linux-$(uname -p).zip"

wget "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_${ARCH}.deb"
dpkg -i "caddy_${CADDY_VERSION}_linux_${ARCH}.deb"
rm "caddy_${CADDY_VERSION}_linux_${ARCH}.deb"

cat <<-CADDYFILE | sudo tee /etc/caddy/Caddyfile
nerdy.party
reverse_proxy :8065
CADDYFILE

# Enable swap
dd if=/dev/zero of=/swapfile bs=64M count=32
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Install and start Mattermost
cd /tmp || exit 1

# --user-group creates a group named mattermost
useradd --system --no-create-home --user-group mattermost

su postgres -c 'createuser --superuser mattermost'
su postgres -c 'createuser --superuser ubuntu'
su postgres -c 'createuser --superuser root'
su mattermost -c 'createdb mattermost'

wget -q https://releases.mattermost.com/$MM_VERSION/mattermost-$MM_VERSION-linux-${ARCH}.tar.gz
tar -xzf "mattermost-$MM_VERSION-linux-${ARCH}.tar.gz"
rm "mattermost-$MM_VERSION-linux-${ARCH}.tar.gz"

mv mattermost /opt
mkdir /opt/mattermost/data
mkdir /opt/mattermost/plugins
touch /opt/mattermost/logs/mattermost.log

wget -O "/opt/mattermost/prepackaged_plugins/playbooks-$PLAYBOOKS_VERSION.tar.gz" -q "https://github.com/mattermost/mattermost-plugin-playbooks/releases/download/$PLAYBOOKS_VERSION/playbooks-$PLAYBOOKS_VERSION.tar.gz"
(
  cd /opt/mattermost/plugins
  wget -O "mattermost-plugin-focalboard.tar.gz" -q "https://github.com/mattermost/focalboard/releases/download/v7.10.6/mattermost-plugin-focalboard.tar.gz"
  tar -xvzf "mattermost-plugin-focalboard.tar.gz"
  rm "mattermost-plugin-focalboard.tar.gz"
)

(
  cd /opt/mattermost/plugins
  wget -O "mattermost-plugin-remind.tar.gz" -q "https://github.com/scottleedavis/mattermost-plugin-remind/releases/download/v1.0.0/com.github.scottleedavis.mattermost-plugin-remind-1.0.0.tar.gz"
  tar -xvzf "mattermost-plugin-remind.tar.gz"
  rm "mattermost-plugin-remind.tar.gz"

  cd com.github.scottleedavis.mattermost-plugin-remind/
  # Work around https://github.com/scottleedavis/mattermost-plugin-remind/pull/247
  tmp="$(mktemp)"
  jq '.server.executables["linux-arm64"] = "server/dist/plugin-linux-arm64"' plugin.json > "$tmp"
  mv "$tmp" plugin.json
)

cat <<-ENV | tee /opt/mattermost/environment
TZ=UTC
MM_SQLSETTINGS_DRIVERNAME=postgres
MM_SQLSETTINGS_DATASOURCE=postgres:///mattermost?connect_timeout=1&host=/run/postgresql
MM_CONFIG=postgres:///mattermost?connect_timeout=1&host=/run/postgresql
MM_FILESETTINGS_DRIVERNAME=amazons3
MM_EMAILSETTINGS_PUSHNOTIFICATIONSERVER=https://push-test.mattermost.com
MM_EMAILSETTINGS_SENDPUSHNOTIFICATIONS=true
MM_EMAILSETTINGS_ENABLESMTPAUTH=true
ENV

chown -R mattermost:mattermost /opt/mattermost
chmod -R g+w /opt/mattermost

cat <<-SERVICE | tee /etc/systemd/system/mattermost.service
[Unit]
Description=Mattermost

[Service]
User=mattermost
Group=mattermost
WorkingDirectory=/opt/mattermost
ExecStart=/opt/mattermost/bin/mattermost server
# How long we should wait to restart
RestartSec=30s
# Should we restart?
Restart=always
LimitNOFILE=49152
EnvironmentFile=/opt/mattermost/environment
EnvironmentFile=/opt/mattermost/environment-per-stack
[Install]
WantedBy=multi-user.target
SERVICE

export MM_SQLSETTINGS_DATASOURCE='postgres:///mattermost?connect_timeout=1&host=/run/postgresql'
export MM_CONFIG='postgres:///mattermost?connect_timeout=1&host=/run/postgresql'
su mattermost -c '/opt/mattermost/bin/mattermost db init'

cat <<-SQL | su mattermost -c 'psql mattermost'
update configurations
set value = jsonb_set(value::JSONB,'{LogSettings,EnableFile}'::text[], 'false'::jsonb)
where active;
update configurations
set value = jsonb_set(value::JSONB,'{NotificationLogSettings,EnableFile}'::text[], 'false'::jsonb)
where active;
update configurations
set value = jsonb_set(value::JSONB,'{AnnouncementSettings,UserNoticesEnabled}'::text[], 'false'::jsonb)
where active;
update configurations
set value = jsonb_set(value::JSONB,'{ServiceSettings,ListenAddress}'::text[], '":8065"'::jsonb)
where active;
update configurations
set value = jsonb_set(value::JSONB,'{ServiceSettings,EnableTutorial}'::text[], 'false'::jsonb)
where active;
update configurations
set value = jsonb_set(value::JSONB,'{ServiceSettings,EnableOnboardingFlow}'::text[], 'false'::jsonb)
where active;
update configurations
set value = jsonb_set(value::JSONB,'{ServiceSettings,EnableMultifactorAuthentication}'::text[], 'false'::jsonb)
where active;
update configurations
set value = jsonb_set(value::JSONB,'{PluginSettings,PluginStates,com.mattermost.nps,Enable}'::text[], 'false'::jsonb)
where active;
update configurations
set value = jsonb_set(value::JSONB,'{TeamSettings,MaxUsersPerTeam,com.mattermost.nps,Enable}'::text[], '250'::jsonb)
where active;
SQL

cat <<-SQL > /opt/mattermost/backup.sh
#!/bin/bash
set -exuo pipefail
pg_dump mattermost | gzip | aws s3 cp - "s3://\$MM_FILESETTINGS_AMAZONS3BUCKET/pg_dump/latest.pgdump"
SQL
chmod +x /opt/mattermost/backup.sh

cat <<-SERVICE | tee /etc/systemd/system/backup-mattermost.service
[Unit]
Description=Backups

[Service]
Type=oneshot
User=mattermost
Group=mattermost
WorkingDirectory=/opt/mattermost
ExecStart=/opt/mattermost/backup.sh
EnvironmentFile=/opt/mattermost/environment
EnvironmentFile=/opt/mattermost/environment-per-stack
[Install]
WantedBy=default.target
SERVICE

cat <<-SERVICE | tee /etc/systemd/system/backup-mattermost.timer
[Unit]
Description=Run backups hourly

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
SERVICE

cat <<-SQL > /opt/mattermost/restore.sh
#!/bin/bash
set -exuo pipefail
systemctl stop mattermost
dropdb mattermost
createdb mattermost
aws s3 cp "s3://\$MM_FILESETTINGS_AMAZONS3BUCKET/pg_dump/latest.pgdump" - | gunzip | psql mattermost
systemctl enable mattermost
systemctl start mattermost
systemctl enable backup-mattermost.service
systemctl enable backup-mattermost.timer
SQL
chmod +x /opt/mattermost/restore.sh

cat <<-SERVICE | tee /etc/systemd/system/restore-mattermost.service
[Unit]
Description=Restore Backups

[Service]
Type=oneshot
User=root
Group=mattermost
WorkingDirectory=/opt/mattermost
ExecStart=/opt/mattermost/restore.sh
EnvironmentFile=/opt/mattermost/environment
EnvironmentFile=/opt/mattermost/environment-per-stack
SERVICE
