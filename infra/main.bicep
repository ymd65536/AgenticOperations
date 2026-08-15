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
apt-get update
apt-get install -y nginx
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
mkdir -p /var/www/html /var/www/empty
cat > /var/www/html/index.html <<'EOF'
<html>
  <body>
    <h1>azure-agentic-ops nginx healthy</h1>
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
