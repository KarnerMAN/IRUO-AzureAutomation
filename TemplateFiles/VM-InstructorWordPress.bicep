param adminUsername string
param location string
param virtualMachineName string
param virtualMachineSize string
param networkInterfaceName string
param networkSecurityGroupName string
param subnetName string
param virtualNetworkId string
param storageAccountName string
param storageAccountKey string
param scriptDiskWordPressWithInjectionSSH string
param containerName string
param jumpHostSshKeyValue string
param vmTags object

var nsgId = resourceId(resourceGroup().name, 'Microsoft.Network/networkSecurityGroups', networkSecurityGroupName)
var subnetRef = '${virtualNetworkId}/subnets/${subnetName}'

var networkSecurityGroupRules = [
  {
    name: 'SSH-From-JumpHost-Allow'
    properties: {
      priority: 1000
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '22'
      sourceAddressPrefix: '192.168.1.4/32'
      destinationAddressPrefix: '*'
      description: 'Allow SSH From Jump Host'
    }
  }
  
  {
    name: 'HTTP-Inbound-Allow'
    properties: {
      priority: 1010
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '80'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      description: 'Allow HTTP Inbound'
    }
  }

  {
    name: 'HTTPS-Inbound-Allow'
    properties: {
      priority: 1020
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '443'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
      description: 'Allow HTTPS Inbound'
    }
  }
  ]

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: networkSecurityGroupName
  location: location
  tags: vmTags
  properties: {
    securityRules: networkSecurityGroupRules
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2024-07-01' = {
  name: networkInterfaceName
  location: location
  tags: vmTags
  properties: {
    ipConfigurations: [
      {
        name: '${networkInterfaceName}-ipconfig'
        properties: {
          subnet: {
            id: subnetRef
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
    networkSecurityGroup: {
      id: nsgId
    }
  }
  dependsOn: [
    networkSecurityGroup
  ]
}

resource dataDisk1 'Microsoft.Compute/disks@2025-01-02' = {
  name: 'datadisk1-${virtualMachineName}'
  location: location
  tags: vmTags
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    diskSizeGB: 16
    creationData: {
      createOption: 'Empty'
    }
  }
}

resource dataDisk2 'Microsoft.Compute/disks@2025-01-02' = {
  name: 'datadisk2-${virtualMachineName}'
  location: location
  tags: vmTags
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    diskSizeGB: 16
    creationData: {
      createOption: 'Empty'
    }
  }
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  name: '${storageAccountName}/default/${containerName}'
  properties: {
    publicAccess: 'None'
  }
}

resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: virtualMachineName
  location: location
  tags: vmTags
  properties: {
    hardwareProfile: {
      vmSize: virtualMachineSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'fromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        deleteOption: 'Delete'
      }
      imageReference: {
        publisher: 'canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      dataDisks: [
        {
          name: dataDisk1.name
          lun: 0
          createOption: 'Attach'
          managedDisk: {
            id: dataDisk1.id
            storageAccountType: 'Standard_LRS'
          }
          deleteOption: 'Delete'
          caching: 'None'
          writeAcceleratorEnabled: false
        }
        {
          name: dataDisk2.name
          lun: 1
          createOption: 'Attach'
          managedDisk: {
            id: dataDisk2.id
            storageAccountType: 'Standard_LRS'
          }
          deleteOption: 'Delete'
          caching: 'None'
          writeAcceleratorEnabled: false
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: {}
    additionalCapabilities: {
      hibernationEnabled: false
    }
    osProfile: {
      computerName: virtualMachineName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: jumpHostSshKeyValue
            }
          ]
        }
        patchSettings: {
          assessmentMode: 'ImageDefault'
          patchMode: 'ImageDefault'
        }
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
  dependsOn: [
    networkInterface
    dataDisk1
    dataDisk2
    blobContainer
  ]
}

resource customScript 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  name: '${virtualMachine.name}/mountdisks'
  location: location
  tags: vmTags
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        scriptDiskWordPressWithInjectionSSH
      ]
      commandToExecute: 'bash DiskAndWordPress.sh ${storageAccountName} ${containerName} ${storageAccountKey} ${adminUsername}'
    }
  }
  dependsOn: [
    virtualMachine
    blobContainer
  ]
}
