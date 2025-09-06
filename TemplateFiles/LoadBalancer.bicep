param location string
param loadBalancerName string
param publicIpResourceId string
param backendPoolJumpHostName string
param backendPoolWordPressName string
param loadBalancerFrontendName string
param loadBalancerTags object

resource loadBalancer 'Microsoft.Network/loadBalancers@2024-07-01' = {
  name: loadBalancerName
  location: location
  sku: {
    name: 'Standard'
  }
  tags: loadBalancerTags
  properties: {
    frontendIPConfigurations: [
      {
        name: loadBalancerFrontendName
        properties: {
          publicIPAddress: {
            id: publicIpResourceId
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: backendPoolJumpHostName
      }
      {
        name: backendPoolWordPressName
      }
    ]

   
    loadBalancingRules: [
      {
        name: 'sshRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, loadBalancerFrontendName)
          }

          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, backendPoolJumpHostName)
          }
          protocol: 'Tcp'
          frontendPort: 22
          backendPort: 22
          enableFloatingIP: false
          idleTimeoutInMinutes: 15
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'sshProbe')
          }
        }
      }
      {
        name: 'httpRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, loadBalancerFrontendName)
          }

          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, backendPoolWordPressName)
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 15
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'httpProbe')
          }
        }
      }
    ]
    probes: [
      {
        name: 'httpProbe'
        properties: {
          protocol: 'Http'
          port: 80
          requestPath: '/'
        }
      }
      {
        name: 'sshProbe'
        properties: {
          protocol: 'Tcp'
          port: 22
        }
      }
    ]
  }
}
