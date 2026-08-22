@description('Azure region for the VM and supporting resources.')
param location string = resourceGroup().location

@description('Username for the Linux VM administrator account.')
param adminUsername string = 'azureuser'

@description('Public SSH key for Linux VM admin authentication.')
param sshPublicKey string

@description('Prefix applied to resource names in this scenario.')
param namePrefix string = 'vmnginx404'

@description('VM size for the NGINX workload.')
param vmSize string = 'Standard_B1s'

var vmName = '${namePrefix}-vm'
var vnetName = '${namePrefix}-vnet'
var subnetName = '${namePrefix}-subnet'
var nicName = '${namePrefix}-nic'
var nsgName = '${namePrefix}-nsg'
var publicIpName = '${namePrefix}-pip'
var osDiskName = '${vmName}-osdisk'
var nsgRuleName = 'allow-http'
var linuxImagePublisher = 'Canonical'
var linuxImageOffer = '0001-com-ubuntu-server-jammy'
var linuxImageSku = '22_04-lts-gen2'
var linuxImageVersion = 'latest'
var configScript = '''
set -eux
export DEBIAN_FRONTEND=noninteractive
mkdir -p /var/lib/apt/lists/partial
rm -rf /var/lib/apt/lists/*
apt-get clean || true
apt-get update -o Acquire::Retries=3 --fix-missing || apt-get update -o Acquire::Retries=5
apt-get install -y nginx
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
mkdir -p /var/www/html /var/www/empty
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Agent Recovery - NGINX</title>
    <style>
      body {
        font-family: Arial, sans-serif;
        margin: 2rem auto;
        max-width: 880px;
        line-height: 1.6;
        color: #0f172a;
        background: #f8fafc;
      }
      .card {
        background: white;
        border-radius: 12px;
        box-shadow: 0 10px 20px rgba(15, 23, 42, 0.08);
        padding: 2rem;
      }
      h1 {
        color: #0f766e;
      }
      .status {
        display: inline-block;
        background: #dcfce7;
        color: #166534;
        font-weight: bold;
        padding: 0.35rem 0.75rem;
        border-radius: 999px;
      }
      code {
        background: #e2e8f0;
        padding: 0.15rem 0.35rem;
        border-radius: 6px;
      }
      ol {
        padding-left: 1.25rem;
      }
      .note {
        margin-top: 1rem;
        background: #ecfeff;
        border-left: 4px solid #0891b2;
        padding: 1rem;
      }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Service recovery completed</h1>
      <p class="status">HTTP 200 - Healthy</p>

      <p>
        The monitored endpoint previously returned <strong>HTTP 404</strong> because the
        NGINX route for <code>/health</code> was pointing to a missing document root.
        The broken configuration used a path such as <code>/var/www/does-not-exist</code>,
        so NGINX could not resolve the requested health page and returned a routing error.
      </p>

      <h2>How the Hosted Agent recovered the service</h2>
      <ol>
        <li>Confirmed the HTTP 404 on the target URL.</li>
        <li>Checked the NGINX service status and access/error logs.</li>
        <li>Inspected the active configuration to find the incorrect root path.</li>
        <li>Replaced the broken route with a valid health mapping to <code>/var/www/html</code>.</li>
        <li>Validated the NGINX config with <code>nginx -t</code>.</li>
        <li>Reloaded NGINX and re-probed the URL.</li>
      </ol>

      <div class="note">
        <strong>Root cause:</strong> the config for <code>location = /health</code>
        was pointing to a non-existent filesystem path, not that the VM or NGINX service itself was down.
      </div>

      <h2>Result</h2>
      <p>
        The recovery was successful. The health endpoint now resolves correctly and serves this page,
        which documents the exact recovery procedure and verifies that the service is back to a healthy state.
      </p>
    </div>
  </body>
</html>
EOF
mkdir -p /etc/nginx/conf.d
cat > /etc/nginx/conf.d/agentic-ops.conf <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html;

    location = /health {
        default_type text/plain;
        try_files /index.html =404;
    }

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF
nginx -t
systemctl enable nginx
systemctl restart nginx
'''

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.10.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: nsgRuleName
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow-ssh'
        properties: {
          priority: 1010
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower('${namePrefix}-${uniqueString(resourceGroup().id)}')
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: linuxImagePublisher
        offer: linuxImageOffer
        sku: linuxImageSku
        version: linuxImageVersion
      }
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource vmCustomScript 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  name: 'install-nginx'
  parent: vm
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: configScript
    }
  }
}

output vmName string = vm.name
output publicIpAddress string = publicIp.properties.ipAddress
output monitoredUrl string = 'http://${publicIp.properties.ipAddress}/health'
output resourceGroupName string = resourceGroup().name
