## 📂 Purpose
The `configure_stack` role automates a full containerized monitoring environment using:

- Grafana `{{ grafana_version }}`
- Prometheus `{{ prometheus_version }}`
- NGINX `{{ nginx_version }}`
- IDRAC_EXPORTER `{{ idrac_version }}`

It ensures:

- Datasources are provisioned (`prometheus.yml`, `idrac.yml`)
- Alert rules are UID corrected for datasource mappings
- Dashboards are cleaned, stripped of embedded datasources, UID rewritten, and safely imported
- Plugins and provisioning files are installed with correct ownership/permissions


## ⚙️ Tasks
- Execute environmental bootstrap and file staging
- Run dashboard regex formatting and cleaning tasks
- Fix final post-cleanup file bounds
- Run standard orchestration environment stack scripts
- Execute Unified API provisioning stack
- Generate README from template

## 📌 Requirements
- Ansible control node
- Target host connectivity

## 📖 Notes
- Generated automatically from tasks.

## 🚀 Usage
```yaml
- hosts: configure_grafana_stack
  roles:
    - configure_grafana_stack
```
