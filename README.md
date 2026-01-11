# Stack4Things with Crossplane Deployment

This repository contains the complete deployment of Stack4Things (S4T) integrated with Crossplane for declarative IoT board management on Kubernetes.

## Table of Contents

- [Repository Structure](#repository-structure)
- [Architecture Overview](#architecture-overview)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [Components](#components)
- [Deployment Flow](#deployment-flow)
- [Board Management Flow](#board-management-flow)
- [Plugin and Service Injection Flow](#plugin-and-service-injection-flow)

## Repository Structure

```
s4t-crossplane-deployment/
├── README.md                          # This file - main documentation
├── stack4things-improved/             # Main deployment directory
│   ├── README.md                      # Detailed deployment guide
│   ├── deploy-complete-improved.sh    # Automated deployment script (includes Crossplane)
│   ├── scripts/                       # Helper scripts for board management
│   │   ├── create-all-boards.sh      # Create multiple boards
│   │   ├── cleanup-all-boards.sh      # Clean up all boards
│   │   ├── create-plugin.sh          # Create plugin via Crossplane
│   │   ├── inject-plugin-using-crd.sh # Inject plugin into board
│   │   └── ...
│   ├── examples/                      # Example resources
│   │   ├── plugin-simple-logger.yaml  # Simple plugin example
│   │   └── ...
│   ├── yaml_file/                     # Kubernetes manifests for S4T services
│   ├── conf_*/                        # Configuration files
│   └── ...
├── crossplane-provider/               # Crossplane Provider for Stack4Things
│   ├── README.md                      # Provider documentation
│   ├── API_DOCUMENTATION.md           # Complete API reference
│   ├── API_REVIEW.md                  # Provider implementation review
│   ├── openapi.yaml                   # OpenAPI 3.0 specification
│   ├── examples/                      # Example Device/Plugin/Service resources
│   └── ...
└── stack4things/                      # Legacy deployment (deprecated)
    └── ...                            # Old deployment files
```

## Architecture Overview

The following diagram shows the complete architecture of Stack4Things with Crossplane, Keycloak, Keystone, and RBAC Operator integration:

```mermaid
flowchart TD
    subgraph "User Authentication & Authorization"
        A[User/Operator] -->|OIDC JWT Token| B[Kubernetes API Server]
        B -->|Validates JWT| C[Keycloak OIDC Provider]
        C -->|Issues JWT| D[User Identity + Groups]
        D -->|Federated Identity| E[Keystone Federation]
        E -->|Group Mapping| F[Keystone Groups]
    end
    
    subgraph "Kubernetes RBAC & Project Management"
        B -->|Authenticated Request| G[RBAC Operator]
        G -->|Watches| H[Project CRD]
        H -->|Creates| I[Project Namespace]
        I -->|Creates| J[Project Roles]
        J -->|Binds| K[RoleBindings]
        K -->|Uses| L[OIDC Groups]
        L -->|s4t:owner-project:role| M[Project Isolation]
    end
    
    subgraph "Crossplane Resource Management"
        B -->|kubectl apply| N[Crossplane CRDs]
        N -->|Device CRD| O[Crossplane Provider S4T]
        N -->|Plugin CRD| O
        N -->|Service CRD| O
        N -->|BoardPluginInjection CRD| O
        N -->|BoardServiceInjection CRD| O
        N -->|Project CRD| P[Project Controller]
        P -->|Manages| Q[Stack4Things Projects]
    end
    
    subgraph "Stack4Things Core Services"
        O -->|REST API| R[IoTronic Conductor]
        O -->|Keystone Auth| E
        R -->|RPC via| S[RabbitMQ]
        R -->|SQL| T[MariaDB]
        S -->|RPC| U[IoTronic Wagent]
        U -->|WAMP| V[Crossbar WAMP Router]
        W[Lightning Rod] -->|WSS| V
        V -->|WAMP| U
        R -->|API| X[IoTronic UI Dashboard]
    end
    
    subgraph "Board Lifecycle"
        O -->|Creates Board| Y[Board in Database]
        Y -->|Triggers| Z[Lightning Rod Deployment]
        Z -->|Configures| AA[settings.json]
        AA -->|Connects| V
        V -->|Registers| U
        U -->|Updates| Y
        Y -->|Status: online| AB[Board Ready]
    end
    
    subgraph "Plugin & Service Management"
        O -->|Creates Plugin| AC[Plugin in Database]
        O -->|Injects Plugin| AD[BoardPluginInjection]
        AD -->|Updates| Y
        O -->|Exposes Service| AE[BoardServiceInjection]
        AE -->|Updates| Y
    end
    
    subgraph "Infrastructure Layer"
        AF[Kubernetes k3s] -->|Orchestrates| AG[All Services]
        AG -->|Network| AH[MetalLB LoadBalancer]
        AG -->|Service Mesh| AI[Istio Gateway]
        AI -->|Routes| X
    end
    
    style A fill:#e1f5ff
    style C fill:#fff4e1
    style E fill:#ffe1f5
    style G fill:#e1ffe1
    style O fill:#f5e1ff
    style R fill:#ffe1e1
    style V fill:#e1f5ff
    style W fill:#fff4e1
    style X fill:#ffe1f5
```

## Quick Start

1. **Prerequisites**: Install K3s, Helm, MetalLB, and Istio (see [Deployment Guide](stack4things-improved/README.md))

2. **Deploy Stack4Things with Crossplane**:
   ```bash
   cd stack4things-improved
   ./deploy-complete-improved.sh
   ```

   This script automatically:
   - Deploys all Stack4Things services
   - Installs Crossplane
   - Builds and installs the Crossplane Provider S4T
   - Deploys Keycloak and Keystone for authentication
   - Deploys RBAC Operator for project management
   - Configures ProviderConfig
   - Fixes common issues automatically

3. **Configure k3s for OIDC authentication** (optional, for Keycloak integration):
   ```bash
   cd stack4things-improved
   sudo ./scripts/configure-k3s-oidc.sh
   ```

4. **Create S4T Projects** (for multi-tenant isolation):
   ```bash
   kubectl apply -f stack4things-improved/examples/project-example.yaml
   ```

5. **Create boards using Crossplane**:
   ```bash
   cd stack4things-improved
   ./scripts/create-all-boards.sh 5
   ```

## Documentation

### Main Documentation Files

- **[Deployment Guide](stack4things-improved/README.md)** - Complete deployment instructions with troubleshooting
- **[API Documentation](crossplane-provider/API_DOCUMENTATION.md)** - Complete reference of all IoTronic API endpoints
- **[API Review](crossplane-provider/API_REVIEW.md)** - Review of Crossplane Provider implementation
- **[OpenAPI Specification](crossplane-provider/openapi.yaml)** - OpenAPI 3.0 spec for Stack4Things API
- **[Crossplane Provider README](crossplane-provider/README.md)** - Provider-specific documentation

### Key Sections in Deployment Guide

- Architecture diagrams and sequence diagrams
- Step-by-step deployment instructions
- Board creation and management
- Plugin and service management
- Troubleshooting guide
- Common issues and fixes

## Components

### Stack4Things Services
- **IoTronic Conductor** - API server and orchestration
- **IoTronic Wagent** - WAMP agent for board communication
- **Crossbar** - WAMP router for real-time messaging
- **Lightning Rod** - Agent running on IoT boards
- **IoTronic UI** - Horizon dashboard for management
- **Keystone** - Authentication service
- **RabbitMQ** - Message broker for RPC
- **MariaDB** - Database for persistent storage

### Crossplane Integration
- **Crossplane core** - Installed automatically
- **Crossplane Provider S4T** - Custom provider for Stack4Things
- **Device CRD** - For managing boards
- **Plugin CRD** - For managing plugins
- **Service CRD** - For managing services
- **BoardPluginInjection CRD** - For injecting plugins into boards Tested
- **BoardServiceInjection CRD** - For exposing services on boards Tested

### Authentication & Authorization
- **Keycloak** - OIDC Identity Provider for Kubernetes authentication
- **Keystone** - OpenStack identity service, federated with Keycloak
- **RBAC Operator** - Kubernetes operator for managing S4T Projects with namespace isolation
- **Project CRD** - Custom resource for creating isolated project environments
- **OIDC Groups** - Group-based RBAC following `s4t:owner-project:role` convention

## Deployment Flow

The following diagram shows the complete deployment sequence:

```mermaid
flowchart TD
    A[Start Deployment] --> B[Install K3s]
    B --> C[Install Helm]
    C --> D[Install MetalLB]
    D --> E[Install Istio]
    E --> F[Deploy Stack4Things Services]
    
    F --> G[Wait for Database]
    G --> H[Wait for Keystone]
    H --> I[Wait for RabbitMQ]
    I --> J[Deploy IoTronic Services]
    
    J --> K[Install Crossplane]
    K --> L[Build Provider S4T]
    L --> M[Install Provider S4T]
    M --> N[Configure ProviderConfig]
    
    N --> O[Fix Common Issues]
    O --> P[Verify Deployment]
    P --> Q[Deployment Complete]
    
    style A fill:#e1f5ff
    style Q fill:#e1ffe1
    style F fill:#fff4e1
    style K fill:#ffe1f5
```

## Board Management Flow

The following diagram shows how boards are created and managed:

```mermaid
flowchart TD
    A[User creates Device CRD] --> B[Crossplane Provider receives request]
    B --> C[Authenticate with Keystone]
    C --> D[Call IoTronic API POST /v1/boards]
    D --> E[Board created in database]
    E --> F[UUID returned to Provider]
    F --> G[Provider updates Device status]
    
    G --> H[Create Lightning Rod Deployment]
    H --> I[Configure settings.json]
    I --> J[Lightning Rod connects to Crossbar]
    J --> K[Board registers with Wagent]
    K --> L[Board status: online]
    
    L --> M[Board ready for plugins/services]
    
    style A fill:#e1f5ff
    style L fill:#e1ffe1
    style D fill:#fff4e1
    style J fill:#ffe1f5
```

## Plugin and Service Injection Flow

The following diagram shows how plugins and services are injected into boards:

```mermaid
flowchart TD
    A[User creates Plugin CRD] --> B[Crossplane Provider creates plugin]
    B --> C[Plugin stored in database]
    
    D[User creates BoardPluginInjection CRD] --> E[Provider calls PUT /v1/boards/{uuid}/plugins/]
    E --> F{Board online?}
    F -->|Yes| G[Plugin injected successfully]
    F -->|No| H[Injection fails - board offline]
    
    G --> I[Plugin appears in dashboard]
    I --> J[User can start plugin]
    
    K[User creates Service CRD] --> L[Crossplane Provider creates service]
    L --> M[Service stored in database]
    
    N[User creates BoardServiceInjection CRD] --> O[Provider calls POST /v1/boards/{uuid}/services/{uuid}/action]
    O --> P{Board online?}
    P -->|Yes| Q[Service exposed with public port]
    P -->|No| R[Exposure fails - board offline]
    
    Q --> S[Service accessible via public port]
    
    style A fill:#e1f5ff
    style D fill:#e1f5ff
    style K fill:#e1f5ff
    style N fill:#e1f5ff
    style G fill:#e1ffe1
    style Q fill:#e1ffe1
    style H fill:#ffe1e1
    style R fill:#ffe1e1
```

## Communication Protocols

### WAMP (WebSocket Application Messaging Protocol)
- Used for real-time communication between Lightning Rod and Crossbar
- Protocol: WSS (WebSocket Secure)
- Realm: `s4t`
- Port: 8181

### RPC (Remote Procedure Call)
- Used for communication between Wagent and Conductor
- Transport: RabbitMQ (AMQP)
- Pattern: Request-Reply
- Topics: `iotronic.conductor_manager` (Conductor) and `s4t` (Wagent)

### REST API
- Used by Crossplane Provider to interact with IoTronic
- Endpoint: `http://iotronic-conductor:8812/v1`
- Authentication: Keystone tokens

## Notes

- The `stack4things/` directory contains the legacy deployment and is kept for reference
- The `stack4things-improved/` directory is the active deployment with Crossplane integration
- All deployment scripts include Crossplane installation and configuration
- Plugin and service injection require boards to be **online** (Lightning Rod connected)

## Getting Help

- Check the [Deployment Guide](stack4things-improved/README.md) for detailed instructions
- Review [API Documentation](crossplane-provider/API_DOCUMENTATION.md) for API reference
- See [API Review](crossplane-provider/API_REVIEW.md) for implementation details
- Check logs: `kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-s4t`
