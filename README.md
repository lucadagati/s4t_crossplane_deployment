# Stack4Things with Crossplane Deployment

This repository contains the complete deployment of Stack4Things (S4T) integrated with Crossplane for declarative IoT board management on Kubernetes.

## Repository Structure

```
s4t-crossplane-deployment/
├── README.md                          # This file - main documentation
├── stack4things-improved/             # Main deployment directory
│   ├── README.md                      # Detailed deployment guide
│   ├── deploy-complete-improved.sh    # Automated deployment script (includes Crossplane)
│   ├── scripts/                       # Helper scripts for board management
│   ├── yaml_file/                     # Kubernetes manifests for S4T services
│   ├── conf_*/                        # Configuration files
│   └── ...
├── crossplane-provider/               # Crossplane Provider for Stack4Things
│   ├── README.md                      # Provider documentation
│   ├── examples/                      # Example Device/Plugin/Service resources
│   └── ...
└── stack4things/                      # Legacy deployment (deprecated)
    └── ...                            # Old deployment files
```

## Quick Start

1. **Prerequisites**: Install K3s, Helm, MetalLB, and Istio (see `stack4things-improved/README.md`)

2. **Deploy Stack4Things with Crossplane**:
   ```bash
   cd stack4things-improved
   ./deploy-complete-improved.sh
   ```

   This script automatically:
   - Deploys all Stack4Things services
   - Installs Crossplane
   - Builds and installs the Crossplane Provider S4T
   - Configures ProviderConfig
   - Fixes common issues automatically

3. **Create boards using Crossplane**:
   ```bash
   cd stack4things-improved
   ./scripts/create-all-boards.sh 5
   ```

## Documentation

- **Main Deployment Guide**: `stack4things-improved/README.md`
- **Crossplane Provider**: `crossplane-provider/README.md`
- **Board Management**: See "Creating and Managing Boards" section in `stack4things-improved/README.md`

## Components

### Stack4Things Services
- IoTronic Conductor (API server)
- IoTronic Wagent (WAMP agent)
- Crossbar (WAMP router)
- Lightning Rod (board agent)
- IoTronic UI (Horizon dashboard)
- Keystone (authentication)
- RabbitMQ (message broker)
- MariaDB (database)

### Crossplane Integration
- Crossplane core (installed automatically)
- Crossplane Provider S4T (custom provider)
- Device CRD (for managing boards)
- Plugin CRD (for managing plugins)
- Service CRD (for managing services)
- BoardPluginInjection CRD (for injecting plugins into boards) ✅ Tested
- BoardServiceInjection CRD (for exposing services on boards) ✅ Tested

## Notes

- The `stack4things/` directory contains the legacy deployment and is kept for reference
- The `stack4things-improved/` directory is the active deployment with Crossplane integration
- All deployment scripts include Crossplane installation and configuration
