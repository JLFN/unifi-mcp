# Installation

## Python dependencies

The module requires `httpx` and `urllib3` python packages to be installed.
You can install them using pip:

```bash
pip install httpx urllib3
```

## Installing the Ansible Collection

You can install the `ubiquiti.unifi_api` Ansible collection by downloading the collection archive and installing it with the following commands:

```bash
curl -L -o ubiquiti-unifi_api-latest.tar.gz https://apidoc-cdn.ui.com/ansible-module/ubiquiti-unifi_api-latest.tar.gz
ansible-galaxy collection install ubiquiti-unifi_api-latest.tar.gz
```

# UniFi Network API – Ansible Usage Guide

Version: v10.4.57

This guide shows how to call each operation using the `ubiquiti.unifi_api.network` Ansible module.

## Quick Start

Here is a basic example of how to use the `ubiquiti.unifi_api.network` module to interact with the API.
Setting module_defaults allows you to avoid repeating common parameters for each task.

```yaml
---
- name: Using ubiquiti.unifi_api.network with this API
  hosts: localhost
  gather_facts: false
  vars:
    site_id: "12341234-5656-7878-9090-123456789012" # Replace with your site ID
  module_defaults:
    group/ubiquiti.unifi_api.common:
      base_url: "https://10.2.0.0" # Replace with your console IP
      token: "{{ lookup('env', 'UBIQUITI_API_TOKEN') }}" # export UBIQUITI_API_TOKEN=... in your shell
```

You can then add tasks to call specific API operations. For example, to retrieve site information, you might add:

```yaml
tasks:
    - name: Get application info
      ubiquiti.unifi_api.network:
        path: "/v1/info"
        method: GET
      register: info

    - debug:
        var: site_info.data
```

## Idempotency

Currently, the `ubiquiti.unifi_api.network` module does not guarantee idempotency for all operations.
When using operations that modify resources (e.g., create, update, delete),
it is recommended to implement additional checks in your playbooks to ensure that the desired state is achieved without
unintended side effects.

Example:

```yaml
tasks:
    - name: Check if vouchers exist
      ubiquiti.unifi_api.network:
        path: "/v1/sites/{{ site_id }}/hotspot/vouchers"
        method: GET
        query:
          filter: "name.eq('test_voucher')"
      register: result

    - name: Create vouchers if none exist
      when: vouchers.data.totalCount == 0
      ubiquiti.unifi_api.network:
        path: "/v1/sites/{{ site_id }}/hotspot/vouchers"
        method: POST
        body:
          timeLimitMinutes: 3600
          name: test_voucher
```
