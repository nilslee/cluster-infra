#!/bin/bash
set -euo pipefail

# ── Java 21 (Temurin via Adoptium apt repo) ───────────────────────────────────
# Modern approach for 2026
mkdir -p /etc/apt/keyrings
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
  | gpg --dearmor \
  | sudo tee /etc/apt/keyrings/adoptium.gpg \
  > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" \
  | sudo tee /etc/apt/sources.list.d/adoptium.list

apt-get update
apt-get install -y temurin-21-jdk


# ── Jenkins LTS (official apt repository) ─────────────────────────────────────
# 1. Download and save the 2026 GPG key to the recommended keyring directory
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null

# 2. Add the Jenkins stable repository to your sources list
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

apt-get update -q
apt-get install -y jenkins

# ── Stop Jenkins immediately ──────────────────────────────────────────────────
# apt auto-starts Jenkins on install. Stop it before it finishes first-boot
# initialisation so we can configure everything before the first real start.
systemctl stop jenkins

# ── Add jenkins user to docker group ─────────────────────────────────────────
usermod -aG docker jenkins

# ── Install jenkins-plugin-cli ────────────────────────────────────────────────
PLUGIN_CLI_JAR=/usr/local/lib/jenkins-plugin-manager.jar
PLUGIN_CLI_VERSION=$(curl -fsSL \
  https://api.github.com/repos/jenkinsci/plugin-installation-manager-tool/releases/latest \
  | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
wget -qO "${PLUGIN_CLI_JAR}" \
  "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/${PLUGIN_CLI_VERSION}/jenkins-plugin-manager-${PLUGIN_CLI_VERSION#v}.jar"

# ── Install plugins ───────────────────────────────────────────────────────────
JENKINS_WAR=$(find /usr/share -name jenkins.war -print -quit 2>/dev/null \
              || echo /usr/share/java/jenkins.war)
echo "==> Using Jenkins WAR at: ${JENKINS_WAR}"
java -jar "${PLUGIN_CLI_JAR}" \
  --plugin-file /jenkins/plugins.txt \
  --war "${JENKINS_WAR}" \
  --plugin-download-directory /var/lib/jenkins/plugins
chown -R jenkins:jenkins /var/lib/jenkins/plugins

# ── Copy JCasC configuration ──────────────────────────────────────────────────
mkdir -p /var/lib/jenkins/jcasc
cp /jenkins/jcasc.yaml /var/lib/jenkins/jcasc/jcasc.yaml
chown -R jenkins:jenkins /var/lib/jenkins/jcasc

# ── Ensure pipeline files are readable by jenkins user ────────────────────────
chown -R jenkins:jenkins /jenkins

# ── Wipe first-boot state so Jenkins starts clean ─────────────────────────────
# If Jenkins managed to write any first-boot markers before we stopped it,
# remove them so the next start is treated as a fresh (wizard-free) boot.
rm -f /var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion
rm -f /var/lib/jenkins/jenkins.install.UpgradeWizard.state
rm -f /var/lib/jenkins/secret.key.not-so-secret

# ── Systemd override: disable setup wizard, enable JCasC, inject credentials ──
# Discover the Java opts variable name the installed unit actually uses.
# Newer Jenkins packages use JAVA_OPTS; some use JENKINS_JAVA_OPTS.
UNIT_FILE=$(systemctl show jenkins -p FragmentPath --value)
if grep -q 'JENKINS_JAVA_OPTS' "${UNIT_FILE}" 2>/dev/null; then
  OPTS_VAR="JENKINS_JAVA_OPTS"
else
  OPTS_VAR="JAVA_OPTS"
fi
echo "==> Jenkins unit reads JVM flags from \$${OPTS_VAR}"

mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="${OPTS_VAR}=-Djenkins.install.runSetupWizard=false -Dcasc.jenkins.config=/var/lib/jenkins/jcasc/jcasc.yaml"
Environment="JENKINS_ADMIN_PASSWORD=${JENKINS_ADMIN_PASSWORD:-admin}"
Environment="GITHUB_PAT=${GITHUB_PAT:-changeme}"
EOF

# ── DNS for k8s.lab hostnames (needed by the MCP server container) ────────────
# The MCP container uses --network=host so it inherits the VM's /etc/hosts.
# Add MetalLB VIP entries now (as root) so Jenkins pipelines don't need sudo.
HOSTS_LINE="192.168.56.200 prometheus.k8s.lab loki.k8s.lab argocd.k8s.lab grafana.k8s.lab headlamp.k8s.lab"
if ! grep -q "prometheus.k8s.lab" /etc/hosts; then
  echo "${HOSTS_LINE}" >> /etc/hosts
  echo "==> Added k8s.lab host entries to /etc/hosts"
fi

# ── Free port 9000 if an old MCP container is still bound to it ───────────────
# On re-provision of an existing VM, the old mcp-server container (from the
# now-deleted setup-mcp.sh) may have restarted via --restart=unless-stopped.
docker stop mcp-server 2>/dev/null || true
docker rm   mcp-server 2>/dev/null || true

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
