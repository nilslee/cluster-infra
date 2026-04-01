#!/bin/bash
set -euo pipefail

# ── Java 17 (Temurin via Adoptium apt repo) ───────────────────────────────────
# Jenkins LTS requires Java 17+
wget -qO /etc/apt/trusted.gpg.d/adoptium.asc \
  https://packages.adoptium.net/artifactory/api/gpg/key/public
echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" \
  > /etc/apt/sources.list.d/adoptium.list
apt-get update -q
apt-get install -y temurin-17-jdk

# ── Jenkins LTS (official apt repository) ─────────────────────────────────────
wget -qO /etc/apt/trusted.gpg.d/jenkins.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list
apt-get update -q
apt-get install -y jenkins

# ── Add jenkins user to docker group ─────────────────────────────────────────
# Required so pipeline steps can run docker build/push without sudo
usermod -aG docker jenkins

# ── Install plugins via jenkins-plugin-cli ────────────────────────────────────
JENKINS_WAR=/usr/share/java/jenkins.war
jenkins-plugin-cli --plugin-file /jenkins/plugins.txt --war "${JENKINS_WAR}"

# ── Copy JCasC configuration ──────────────────────────────────────────────────
mkdir -p /var/lib/jenkins/jcasc
cp /jenkins/jcasc.yaml /var/lib/jenkins/jcasc/jcasc.yaml
chown -R jenkins:jenkins /var/lib/jenkins/jcasc

# ── Ensure pipeline files are readable by jenkins user ────────────────────────
chown -R jenkins:jenkins /jenkins

# ── Write /etc/default/jenkins with JCasC path and credentials ────────────────
# JENKINS_ADMIN_PASSWORD and GITHUB_PAT are expected as environment variables
# injected by Vagrant (via ENV vars or a secrets file outside the repo).
# Defaults are provided here for lab convenience only -- change before production use.
cat > /etc/default/jenkins <<EOF
CASC_JENKINS_CONFIG=/var/lib/jenkins/jcasc/jcasc.yaml
JENKINS_ADMIN_PASSWORD=${JENKINS_ADMIN_PASSWORD:-admin}
GITHUB_PAT=${GITHUB_PAT:-changeme}
EOF

# systemd reads /etc/default/jenkins, but Jenkins needs the vars as actual env.
# Create a systemd override that injects the /etc/default/jenkins values.
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
EnvironmentFile=-/etc/default/jenkins
EOF

# ── Start Jenkins ─────────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl enable --now jenkins

echo ""
echo "==> Jenkins provisioning complete."
echo "    UI      : http://192.168.56.10:8080"
echo "    Login   : admin / \${JENKINS_ADMIN_PASSWORD:-admin}"
echo ""
echo "    To update credentials post-provision, edit /etc/default/jenkins"
echo "    and run: sudo systemctl restart jenkins"
