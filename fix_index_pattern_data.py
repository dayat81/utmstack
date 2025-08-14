#!/usr/bin/env python3
"""
Fix utm_index_pattern and utm_visualization INSERT statements to use UUIDs
"""

import re
import uuid

# Create a mapping of old integer IDs to new UUIDs
id_to_uuid = {}
# Generate UUIDs for each ID
for i in [1, 2, 4, 8, 10, 11, 12, 13, 14, 15, 17, 18, 19, 21, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 56, 57, 58, 59, 60, 61]:
    id_to_uuid[i] = str(uuid.uuid4())

# Read the file
with open('/home/hidayat/utmstack/backend/src/main/resources/config/liquibase/scripts/data.sql', 'r') as f:
    content = f.read()

# Fix utm_index_pattern INSERT statement
pattern_content = """		INSERT INTO utm_index_pattern (id, pattern, pattern_module, pattern_system, is_active) VALUES
			(1, 'log-*', NULL, true, true),
			(2, 'alert-*', NULL, true, true),
			(4, 'log-netflow-*', 'NETFLOW', true, false), 
			(8, 'log-wineventlog-*', 'WINDOWS_AGENT', true, true),
			(10, 'log-aws-*', 'AWS_IAM_USER', true, false), 
			(11, 'log-azure-*', 'AZURE', true, false), 
			(12, 'log-o365-*', 'O365', true, false), 
			(13, 'log-firewall-meraki-*', 'MERAKI', true, false), 
			(14, 'log-firewall-*', 'MERAKI,SOPHOS_XG,CISCO,FORTIGATE,FIRE_POWER,UFW,MIKROTIK,PALO_ALTO,SONIC_WALL', true, false), 
			(15, 'log-firewall-cisco-asa-*', 'CISCO', true, false), 
			(17, 'log-firewall-sophos-xg-*', 'SOPHOS_XG', true, false),
			(18, 'log-iis-*', 'IIS', true, false), 
			(19, 'log-generic-*', NULL, true, true),
			(21, 'log-firewall-fortigate-traffic-*', 'FORTIGATE', true, false),
			(24, 'log-vmware-esxi-*', 'VMWARE', true, false), 
			(25, 'log-google-*', 'GCP', true, false), 
			(26, 'log-firewall-cisco-firepower-*', 'FIRE_POWER', true, false),
			(27, 'log-redis-*', 'REDIS', true, false), 
			(28, 'log-postgresql-*', 'POSTGRESQL', true, false), 
			(29, 'log-osquery-*', 'OSQUERY', true, false), 
			(30, 'log-nginx-*', 'NGINX', true, false), 
			(31, 'log-mysql-*', 'MYSQL', true, false), 
			(32, 'log-mongodb-*', 'MONGODB', true, false),
			(33, 'log-logstash-*', 'LOGSTASH', true, false),
			(34, 'log-kibana-*', 'KIBANA', true, false), 
			(35, 'log-kafka-*', 'KAFKA', true, false), 
			(36, 'log-elasticsearch-*', 'ELASTICSEARCH', true, false),
			(37, 'log-auditd-*', 'AUDITD', true, false),
			(38, 'log-apache*', 'APACHE', true, false),
			(39, 'log-linux-*', 'LINUX_AGENT', true, true),
			(40, 'log-antivirus-*', 'ESET,SENTINEL_ONE,KASPERSKY', true, false),
			(41, 'log-antivirus-esmc-eset-*', 'ESET', true, false), 
			(42, 'log-antivirus-kaspersky-*', 'KASPERSKY', true, false),
			(43, 'log-antivirus-sentinel-one-*', 'SENTINEL_ONE', true, false), 
			(44, 'log-sophos-central-*', 'SOPHOS', true, false), 
			(45, 'log-github-*', 'GITHUB', true, false),
			(46, 'log-firewall-ufw-*', 'UFW', true, false),
			(47, 'log-macos-*', 'MACOS', true, false), 
			(48, 'log-firewall-mikrotik-*', 'MIKROTIK', true, false),
			(49, 'log-firewall-paloalto-*', 'PALO_ALTO', true, false),
			(50, 'log-cisco-switch-*', 'CISCO_SWITCH', true, false),
			(51, 'log-firewall-sonicwall-*', 'SONIC_WALL', true, false),
			(52, 'log-deceptive-bytes-*', 'DECEPTIVE_BYTES', true, false),
			(53, 'log-antivirus-bitdefender-gz-*', 'BITDEFENDER', true, false),
			(56, 'soc-ai', 'SOC_AI', true, false),
			(57, 'log-haproxy-*', 'HAPROXY', true, false), 
			(58, 'log-nats-*', 'NATS', true, false),
			(59, 'log-traefik-*', 'TRAEFIK', true, false), 
			(60, 'log-json-input-*', 'JSON', true, true), 
			(61, 'log-rsyslog-linux-*', 'LINUX_LOGS', true, true)"""

# Create new UUID-based content
new_pattern_content = "\t\tINSERT INTO utm_index_pattern (id, pattern, pattern_module, pattern_system, is_active) VALUES\n"
lines = []
for i in [1, 2, 4, 8, 10, 11, 12, 13, 14, 15, 17, 18, 19, 21, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 56, 57, 58, 59, 60, 61]:
    # Find the original pattern info
    for line in pattern_content.split('\n'):
        if f'({i},' in line:
            # Extract pattern info
            parts = line.strip().split("'")
            if len(parts) >= 3:
                pattern = parts[1]
                module = parts[3] if len(parts) > 3 and parts[3] != ", NULL, " else "NULL"
                if "NULL, true" in line:
                    module = "NULL"
                    system = "true"
                else:
                    system = "true" if "true, " in line else "false"
                active = "true" if line.endswith("true),") or line.endswith("true)") else "false"
                
                # Build the new line
                module_str = f"'{module}'" if module != "NULL" else "NULL"
                new_line = f"\t\t\t('{id_to_uuid[i]}', '{pattern}', {module_str}, {system}, {active})"
                if i != 61:  # Not the last one
                    new_line += ","
                lines.append(new_line)
            break

new_pattern_content += '\n'.join(lines)

# Replace the old pattern content with the new one
content = re.sub(
    r"INSERT INTO utm_index_pattern \(id, pattern, pattern_module, pattern_system, is_active\) VALUES.*?ON CONFLICT \(id\) DO UPDATE SET pattern=EXCLUDED\.pattern, pattern_module=EXCLUDED\.pattern_module;",
    new_pattern_content + "\n\t\tON CONFLICT (id) DO UPDATE SET pattern=EXCLUDED.pattern, pattern_module=EXCLUDED.pattern_module;",
    content,
    flags=re.DOTALL
)

# Now fix utm_visualization INSERT statements to use the proper UUIDs
def fix_visualization_insert(match):
    line = match.group(0)
    # Find the id_pattern value (12th field after removing extra NULL)
    parts = line.split(', ')
    for i, part in enumerate(parts):
        if part.strip().isdigit() and int(part.strip()) in id_to_uuid:
            parts[i] = f"'{id_to_uuid[int(part.strip())]}'"
            break
    return ', '.join(parts)

# Apply the fix to utm_visualization statements
content = re.sub(
    r"INSERT INTO public\.utm_visualization VALUES \([^)]+\);",
    fix_visualization_insert,
    content
)

# Write the fixed content back
with open('/home/hidayat/utmstack/backend/src/main/resources/config/liquibase/scripts/data.sql', 'w') as f:
    f.write(content)

print("Fixed utm_index_pattern and utm_visualization INSERT statements")
print(f"UUID mappings created: {len(id_to_uuid)} entries")
