param name string
param location string
param vnetTags object

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: name
  tags: vnetTags
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '192.168.0.0/16'
      ]
    }
    subnets: [] //Will be created later
  }
}
