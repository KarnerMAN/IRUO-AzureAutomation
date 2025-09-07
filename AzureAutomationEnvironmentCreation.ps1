#---------------DEFINING VARIABLES---------------
$VerbosePreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'

$GeoLocation = "West Europe"
$TagDefault = @{"course"="test"}

$ResourceGroupName = "CloudLearn"
$VnetName = "vnet-CloudLearn"

$CsvPath = Join-Path $PSScriptRoot "Popis_studenata.csv"
$Users = Import-Csv -Path $CsvPath -Delimiter ";"

$VnetTemplatePath = Join-Path $PSScriptRoot "TemplateFiles\vnet-cl.bicep"
$InstructorVmJumpHostTemplatePath = Join-Path $PSScriptRoot "TemplateFiles\VM-InstructorJumpHost.bicep"
$InstructorVmWordPressTemplatePath = Join-Path $PSScriptRoot "TemplateFiles\VM-InstructorWordPress.bicep"
$LoadBalancerTemplatePath = Join-Path $PSScriptRoot "TemplateFiles\LoadBalancer.bicep"
$PublicSSHKeyPath = Join-Path $PSScriptRoot "SSHKeyFolder\CloudLearnSSH-JumpHost.pub"
$PublicSSHKeyValue = Get-Content -Path $PublicSSHKeyPath -Raw
$ScriptDiskSSH = "https://raw.githubusercontent.com/KarnerMAN/AzureScripts/refs/heads/main/DiskAndSSHScript.sh"
$ScriptDiskWordPressWithInjectionSSH = "https://raw.githubusercontent.com/KarnerMAN/AzureScripts/refs/heads/main/DiskAndWordPress.sh"

$NumberOfWordpressVMs = 1

#---------------DEFINING VARIABLES FINISHED---------------

#---------------SETTING UP CONNECTION BEFORE CREATING ENVIRONMENT---------------

Write-Host "Checking if Az module is installed...`n" -ForegroundColor Yellow
if (Get-InstalledModule -Name Az -ErrorAction SilentlyContinue) {
    
    Write-Host "`nAz Module already installed, skipping installation...`n" -ForegroundColor Green
    } else {
        
        Write-Host "No Az Module found, installing the module verbosely...`n" -ForegroundColor Yellow
        Install-Module -Name Az -Force -AllowClobber -Verbose -ErrorAction SilentlyContinue
        }


Write-Host "Checking if bicep CLI is installed...`n" -ForegroundColor Yellow
if (Get-Command bicep -ErrorAction SilentlyContinue) {
    
    Write-Host "`nAz Bicep CLI alreaday installed, skipping installation...`n" -ForegroundColor Green
    } else {
        
        Write-Host "No Bicep CLI found, installing...`n" -ForegroundColor Yellow
        
        # Using Microsofts oficial way of installing bicep in Powershell manually
        # Create the install folder
        $installPath = "$env:USERPROFILE\.bicep"
        $installDir = New-Item -ItemType Directory -Path $installPath -Force
        $installDir.Attributes += 'Hidden'
        # Fetch the latest Bicep CLI binary
        (New-Object Net.WebClient).DownloadFile("https://github.com/Azure/bicep/releases/latest/download/bicep-win-x64.exe", "$installPath\bicep.exe")
        # Add bicep to your PATH
        $currentPath = (Get-Item -path "HKCU:\Environment" ).GetValue('Path', '', 'DoNotExpandEnvironmentNames')
        if (-not $currentPath.Contains("%USERPROFILE%\.bicep")) { setx PATH ($currentPath + ";%USERPROFILE%\.bicep") }
        if (-not $env:path.Contains($installPath)) { $env:path += ";$installPath" }

        }



Write-Host "Importing Module into current session...`n" -ForegroundColor Yellow
Import-Module Az -Verbose


Write-Host "Connecting to Azure with provided ID's...`n" -ForegroundColor Blue
if (Connect-AzAccount -TenantId "d974b4df-eec2-433e-a918-3fe18412735f" -SubscriptionId "60f6a44e-6b56-4f2c-90fd-fbd61ba6998b") {

    Write-Host "`nConnection successfull!`n" -ForegroundColor Green
    } else {
 
        Write-Host "`nCould not connect, check provided TenantID and SubscriptionID`n" -ForegroundColor Red
        }


#---------------SETTING UP CONNECTION BEFORE CREATING ENVIRONMENT FINISHED---------------

#---------------RESOURCE GROUP CREATION---------------

Write-Host "`nChecking if resource group exists...`n" -ForegroundColor Blue

if ( Get-AzResourceGroup -Name $ResourceGroupName -Location $GeoLocation -ErrorAction SilentlyContinue ) {

    Write-Host "Resource group '$ResourceGroupName' already exists!" -ForegroundColor Green
    } else {

        Write-Host "Resource group does not exist.`n Creating new resource group...`n" -ForegroundColor Blue
        New-AzResourceGroup -Name $ResourceGroupName -Location $GeoLocation -Tag $TagDefault | Out-Null
        Write-Host "Resource group '$ResourceGroupName' successfully created!`n" -ForegroundColor Green
        }

#---------------RESOURCE GROUP CREATION FINISHED---------------

#---------------VIRTUAL NETWORK CREATION---------------

Write-Host "Checking if Virtual Network with name '$VnetName' exists...`n" -ForegroundColor Blue

if (Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue) {

    Write-Host "Virtual network with name '$VnetName' already exists!`n" -ForegroundColor Green
    } else {
    
        Write-Host "Virtual network with name '$VnetName' does not exist!`n Creating...`n" -ForegroundColor Blue
        New-AzResourceGroupDeployment `
            -Name $VnetName `
            -ResourceGroupName $ResourceGroupName `
            -TemplateFile $VnetTemplatePath `
            -TemplateParameterObject @{
                name = $VnetName
                location = $GeoLocation
                vnetTags = $TagDefault
                } | Out-Null
        }

$VnetData = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroupName

#---------------VIRTUAL NETWORK CREATION FINISHED---------------

#---------------INSTRUCTOR SUBNET CREATION---------------

Write-Host "Checking if the Instructor's subnet already exists...`n" -ForegroundColor Blue

if (Get-AzVirtualNetworkSubnetConfig -Name "Instructor-Subnet" -VirtualNetwork $VnetData -ErrorAction SilentlyContinue) {
    
    Write-Host "Subnet for Instructor already exists!`n" -ForegroundColor Green
    } else {

        Write-Host "Subnet for Instructor does not exist. Creating...`n" -ForegroundColor Blue
        Add-AzVirtualNetworkSubnetConfig -Name "Instructor-Subnet" -AddressPrefix "192.168.1.0/24" -VirtualNetwork $VnetData | Out-Null
        $VnetData | Set-AzVirtualNetwork | Out-Null
        $VnetData = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroupName
        
        Write-Host "Subnet for Instructor created successfully!`n" -ForegroundColor Green
        }

#---------------INSTRUCTOR SUBNET CREATION FINISHED---------------

#---------------INSTRUCTOR JUMPHOSTVM CREATION---------------

$Instructors = @($Users |  Where-Object { $_.rola -eq "instruktor"})

foreach ( $Instructor in $Instructors) {

    $InstructorShortName = ($Instructor.ime.Substring(0,1) + $Instructor.prezime).ToLower() -replace '[^a-z0-9]', ''
    $InstructorStorageAccountName = "st$InstructorShortName"
    
    # Checking if its 3-24 chars and only lowercase letters and numbers
    $InstructorStorageAccountName = $InstructorStorageAccountName.Substring(0, [Math]::Min($InstructorStorageAccountName.Length, 24))

    if (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $InstructorStorageAccountName -ErrorAction SilentlyContinue) {
        
        Write-Host "Storage account for instructor $($Instructor.ime) $($Instructor.prezime) already exists!`n Continuing..." -ForegroundColor Green
        } else {
            
            Write-Host "Creating new storage account for instructor $($Instructor.ime) $($Instructor.prezime)...`n" -ForegroundColor Blue
            New-AzStorageAccount -ResourceGroupName $ResourceGroupName `
                -Name $InstructorStorageAccountName `
                -Location $GeoLocation `
                -SkuName Standard_LRS `
                -Kind StorageV2 `
                -Tag $TagDefault `
                -Verbose
            Write-Host "Storage account for instructor $($Instructor.ime) $($Instructor.prezime) created successfully!`n" -ForegroundColor Green
            }

    $StorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $InstructorStorageAccountName)[0].Value 

    Write-Host "Creating JumpHost VM for instructor $($Instructor.ime) $($Instructor.prezime)...`n" -ForegroundColor Blue
    Write-Host "Admin Username for instructor is '$InstructorShortName'`n" -ForegroundColor Green

    # Has to be initialised outside of New-AzResourceGroupDeployment
    $virtualMachineName = "vm-$InstructorShortName" 

        New-AzResourceGroupDeployment `
        -Name "VM-JumpHost-$InstructorShortName" `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $InstructorVmJumpHostTemplatePath `
        -TemplateParameterObject @{
            adminUsername = $InstructorShortName
            location = $GeoLocation
            virtualMachineName = $virtualMachineName
            virtualMachineSize = "Standard_B1s"
            networkInterfaceName = "nic-$InstructorShortName-$virtualMachineName"
            networkSecurityGroupName = "nsg-$InstructorShortName-$virtualMachineName"
            subnetName = "Instructor-Subnet"
            virtualNetworkId = $VnetData.Id
            storageAccountName = $InstructorStorageAccountName
            storageAccountKey = $StorageAccountKey
            scriptDiskSSH = $ScriptDiskSSH
            containerName = "blob$InstructorShortName"
            publicSSHKeyValue = $PublicSSHKeyValue
            vmTags = $TagDefault
        } -Verbose | Out-Null
}

    Write-Host "VM for instructor $($Instructor.ime) $($Instructor.prezime) created successfully." -ForegroundColor Green

# Set the output path
$InstructorPubKeyPath = Join-Path -Path (Split-Path $PublicSSHKeyPath -Parent) -ChildPath "$InstructorShortName-jumphost.pub"

Write-Host "Extracting public SSH key from Instructor VM, be patient this takes some tries... `n" -ForegroundColor Blue

for ($Attempt = 1; $Attempt -le 15; $Attempt++) {
    $InstructorPubKey = Invoke-AzVMRunCommand `
        -ResourceGroupName $ResourceGroupName `
        -VMName "vm-$InstructorShortName" `
        -CommandId 'RunShellScript' `
        -ScriptString "cat /home/${InstructorShortName}/.ssh/id_rsa.pub" `
        -ErrorAction SilentlyContinue `
        -Verbose 

# Save all lines from the command output to the file
$InstructorPubKey.Value | ForEach-Object { $_.Message } | Out-File $InstructorPubKeyPath -Encoding utf8

$AllLines = Get-Content $InstructorPubKeyPath

$SshKeyLine = $AllLines | Where-Object { $_ -like "ssh-*" }

if ($SshKeyLine) {
    Write-Host "SSH key found!`n Saving..." -ForegroundColor Green    
    break
    } else {
        Write-Host "SSH key not found, retrying in 5 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

# Overwrite the file with only the SSH key line
$SshKeyLine | Out-File $InstructorPubKeyPath -Encoding utf8 -NoNewline

$InstructorVmJumpHostSshKeyValue = Get-Content -Path $InstructorPubKeyPath -Raw
#---------------INSTRUCTOR JUMPHOSTVM CREATION FINISHED---------------

#---------------INSTRUCTOR WORDPRESS VM CREATION---------------

Write-Host "Creating $NumberOfWordpressVMs WordPress VMs for instructor $($Instructor.ime) $($Instructor.prezime)...`n" -ForegroundColor Blue

for ($i = 1; $i -le $NumberOfWordpressVMs; $i++) {
    $WpVmName = "wp-$InstructorShortName-${i}"
    Write-Host "Creating WordPress VM '$WpVmName' for instructor $($Instructor.ime) $($Instructor.prezime)...`n" -ForegroundColor Blue

    New-AzResourceGroupDeployment `
        -Name "VM-$InstructorShortName-$WpVmName" `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $InstructorVmWordPressTemplatePath `
        -TemplateParameterObject @{
            adminUsername = $InstructorShortName
            location = $GeoLocation
            virtualMachineName = $WpVmName
            virtualMachineSize = "Standard_B1s"
            networkInterfaceName = "nic-$InstructorShortName-$WpVmName"
            networkSecurityGroupName = "nsg-$InstructorShortName-$WpVmName"
            subnetName = "Instructor-Subnet"
            virtualNetworkId = $VnetData.Id
            storageAccountName = $InstructorStorageAccountName
            storageAccountKey = $StorageAccountKey
            scriptDiskWordPressWithInjectionSSH = $ScriptDiskWordPressWithInjectionSSH
            containerName = "blob$InstructorShortName"
            jumpHostSshKeyValue = $InstructorVmJumpHostSshKeyValue
            vmTags = $TagDefault
        } -Verbose | Out-Null

    Write-Host "WordPress VM '$WpVmName' for instructor $($Instructor.ime) $($Instructor.prezime) created successfully.`n" -ForegroundColor Green
    }

#---------------INSTRUCTOR WORDPRESS VM CREATION FINISHED---------------

#---------------INSTRUCTOR LOAD BALANCER CREATION---------------

Write-Host "Creating Load Balancer for instructor $($Instructor.ime) $($Instructor.prezime)...`n" -ForegroundColor Blue

# Create a public IP for the Load Balancer
$InstructorLoadBalancerPublicIp = New-AzPublicIpAddress `
    -ResourceGroupName $ResourceGroupName `
    -Name "pip-WordPress-$InstructorShortName-LB" `
    -Location $GeoLocation `
    -AllocationMethod Static `
    -Sku Standard

$LoadBalancerPublicIpId = $InstructorLoadBalancerPublicIp.Id



# Create the Load Balancer and associating the WordPress VMs
New-AzResourceGroupDeployment `
    -Name "LB-WordPress-$InstructorShortName" `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile $LoadBalancerTemplatePath `
    -TemplateParameterObject @{
        location = $GeoLocation
        loadBalancerName = "lb-WordPress-$InstructorShortName"
        publicIpResourceId = $LoadBalancerPublicIpId
        backendPoolJumpHostName = "jhBackendPool-$InstructorShortName"
        backendPoolWordPressName = "wpBackendPool-$InstructorShortName"
        loadBalancerFrontendName = "wpFrontend-$InstructorShortName"
        loadBalancerTags = $TagDefault
    } `
    -Verbose | Out-Null

# Collect the NIC IDs of the WordPress VMs
$WpNicIds = @()
for ($i = 1; $i -le $NumberOfWordpressVMs; $i++) {
    $WpVmName = "wp-$InstructorShortName-${i}"
    $NicName = "nic-$InstructorShortName-$WpVmName"
    $Nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $NicName
    $WpNicIds += $Nic.Id
}

# Get the JumpHost NIC ID
$JumpHostNicName = "nic-$InstructorShortName-vm-$InstructorShortName"
$JumpHostNic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $JumpHostNicName

# Getting the Load Balancer's backend pool
$LoadBalancer = Get-AzLoadBalancer `
    -ResourceGroupName $ResourceGroupName `
    -Name "LB-WordPress-$InstructorShortName" `
    -Verbose

$JumpHostBackendPool = $LoadBalancer.BackendAddressPools | Where-Object { $_.Name -eq "jhBackendPool-$InstructorShortName" }
$BackendPool = $LoadBalancer.BackendAddressPools | Where-Object { $_.Name -eq "wpBackendPool-$InstructorShortName" }

# Associate JumpHost NIC with JumpHost backend pool
$JumpHostNic.IpConfigurations[0].LoadBalancerBackendAddressPools = $JumpHostBackendPool
Set-AzNetworkInterface -NetworkInterface $JumpHostNic

# Associate the NICs with the Load Balancer's backend pool
foreach ($NicId in $WpNicIds) {
    $NicName = ($NicId -split "/")[-1]
    $Nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $NicName
    $Nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $BackendPool
    Set-AzNetworkInterface -NetworkInterface $Nic
}

Write-Host "Load Balancer for instructor $($Instructor.ime) $($Instructor.prezime) created successfully.`n" -ForegroundColor Green

#---------------INSTRUCTOR LOAD BALANCER CREATION FINISHED---------------

#---------------STUDENT ENVIRONMENT CREATION---------------

$Students = @($Users |  Where-Object { $_.rola -eq "student"})
$StudentNumber = 1
$VnetData = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroupName

$StudentVmJumpHostTemplatePath = Join-Path $PSScriptRoot "TemplateFiles\VM-StudentJumpHost.bicep"
$StudentVmWordPressTemplatePath = Join-Path $PSScriptRoot "TemplateFiles\VM-StudentWordPress.bicep"

foreach ($Student in $Students){
    $StudentShortName = ($Student.ime.Substring(0,1) + $Student.prezime).ToLower() -replace '[^a-z0-9]', ''
    $StudentStorageAccountName = "st$StudentShortName"
    $StudentStorageAccountName = $StudentStorageAccountName.Substring(0, [Math]::Min($StudentStorageAccountName.Length, 24))
    $StudentSubnetName = "Student-Subnet-$StudentShortName"
    $StudentVmName = "vm-$StudentShortName"

    # Student subnet creation started

    Write-Host "Checking if subnet for student $($Student.ime) $($Student.prezime) exists...`n" -ForegroundColor Blue
    
    if (Get-AzVirtualNetworkSubnetConfig -Name $StudentSubnetName -VirtualNetwork $VnetData -ErrorAction SilentlyContinue){
        Write-Host "Subnet exists, continuing...`n" -ForegroundColor Green
    } else {
        Write-Host "Subnet does not exist.`n Creating new subnet...`n" -ForegroundColor Blue
        Add-AzVirtualNetworkSubnetConfig -Name $StudentSubnetName -AddressPrefix "192.168.$($StudentNumber + 10).0/24" -VirtualNetwork $VnetData | Out-Null
        $VnetData | Set-AzVirtualNetwork | Out-Null
        $VnetData = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroupName
        Write-Host "Subnet for student $($Student.ime) $($Student.prezime) created successfully!`n" -ForegroundColor Green
    }

    # Student subnet creation ended

    # Student storage account creation started

    if (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StudentStorageAccountName -ErrorAction SilentlyContinue) {
        Write-Host "Storage account for student $($Student.ime) $($Student.prezime) already exists!`n Continuing..." -ForegroundColor Green
    } else {
        Write-Host "Creating storage account for student $($Student.ime) $($Student.prezime)...`n"
        New-AzStorageAccount `
        -Name $StudentStorageAccountName `
        -ResourceGroupName $ResourceGroupName `
        -Location $GeoLocation `
        -SkuName Standard_LRS `
        -Kind StorageV2 `
        -Tag $TagDefault | Out-Null
    }

    $StudentStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StudentStorageAccountName)[0].Value

    # Student storage account creation ended

    # Student Jump Host VM creation started

    Write-Host "Creating Jump Host VM for student $($Student.ime) $($Student.prezime)...`n"
    New-AzResourceGroupDeployment `
        -Name "VM-JumpHost-$StudentShortName" `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $StudentVmJumpHostTemplatePath `
        -TemplateParameterObject @{
            adminUsername = $StudentShortName
            location = $GeoLocation
            virtualMachineName = $StudentVmName
            virtualMachineSize = "Standard_B1s"
            networkInterfaceName = "nic-$StudentShortName-$StudentVmName"
            networkSecurityGroupName = "nsg-$StudentShortName-$StudentVmName"
            subnetName = $StudentSubnetName
            virtualNetworkId = $VnetData.Id
            storageAccountName = $StudentStorageAccountName
            storageAccountKey = $StorageAccountKey
            scriptDiskSSH = $ScriptDiskSSH
            containerName = "blob$StudentShortName"
            publicSshKeyValue = $PublicSSHKeyValue
            instructorJumpHostSshKeyValue = $InstructorVmJumpHostSshKeyValue
            vmTags = $TagDefault
        } | Out-Null

    Write-Host "VM for student $($Student.ime) $($Student.prezime) created successfully.`n" -ForegroundColor Green

    $StudentPubKeyPath = Join-Path -Path (Split-Path $PublicSSHKeyPath -Parent) -ChildPath "$StudentShortName-jumphost.pub"

    Write-Host "Extracting public SSH key from Student VM, be patient this takes some tries... `n" -ForegroundColor Blue

    for ($Attempt = 1; $Attempt -le 15; $Attempt++) {
        $StudentPubKey = Invoke-AzVMRunCommand `
            -ResourceGroupName $ResourceGroupName `
            -VMName "vm-$StudentShortName" `
            -CommandId 'RunShellScript' `
            -ScriptString "cat /home/${StudentShortName}/.ssh/id_rsa.pub" `
            -ErrorAction SilentlyContinue `
            -Verbose 

    $StudentPubKey.Value | ForEach-Object { $_.Message } | Out-File $StudentPubKeyPath -Encoding utf8

    $AllLines = Get-Content $StudentPubKeyPath

    $SshKeyLine = $AllLines | Where-Object { $_ -like "ssh-*" }

    if ($SshKeyLine) {
        Write-Host "SSH key found!`n Saving..." -ForegroundColor Green    
        break
        } else {
            Write-Host "SSH key not found, retrying in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
    }

    $SshKeyLine | Out-File $StudentPubKeyPath -Encoding utf8 -NoNewline

    $StudentVmJumpHostSshKeyValue = Get-Content -Path $StudentPubKeyPath -Raw

    # Student Jump Host VM creation ended

    # Student WordPress VM creation started

    Write-Host "Creating $NumberOfWordPressVMs WordPress VMs for student $($Student.ime) $($Student.prezime)...`n"

    for ($i = 1; $i -le $NumberOfWordpressVMs; $i++) {
        $WpVmName = "wp-$StudentShortName-${i}"
        Write-Host "Creating WordPress VM '$WpVmName' for student $($Student.ime) $($Student.prezime)...`n" -ForegroundColor Blue

        New-AzResourceGroupDeployment `
            -Name "VM-$StudentShortName-$WpVmName" `
            -ResourceGroupName $ResourceGroupName `
            -TemplateFile $StudentVmWordPressTemplatePath `
            -TemplateParameterObject @{
                adminUsername = $StudentShortName
                location = $GeoLocation
                virtualMachineName = $WpVmName
                virtualMachineSize = "Standard_B1s"
                networkInterfaceName = "nic-$StudentShortName-$WpVmName"
                networkSecurityGroupName = "nsg-$StudentShortName-$WpVmName"
                subnetName = $StudentSubnetName
                virtualNetworkId = $VnetData.Id
                storageAccountName = $StudentStorageAccountName
                storageAccountKey = $StudentStorageAccountKey
                scriptDiskWordPressWithInjectionSSH = $ScriptDiskWordPressWithInjectionSSH
                containerName = "blob$StudentShortName"
                jumpHostSshKeyValue = $StudentVmJumpHostSshKeyValue
                instructorJumpHostSshKeyValue = $InstructorVmJumpHostSshKeyValue
                studentNumber = $StudentNumber
                vmTags = $TagDefault
            } -Verbose | Out-Null

        Write-Host "WordPress VM '$WpVmName' for student $($Student.ime) $($Student.prezime) created successfully.`n" -ForegroundColor Green
    }

    # Student WordPress VM creation ended
    
    # Student Load Balancer creation started

    Write-Host "Creating Load Balancer for student $($Student.ime) $($Student.prezime)...`n" -ForegroundColor Blue

    $StudentLoadBalancerPublicIp = New-AzPublicIpAddress `
        -ResourceGroupName $ResourceGroupName `
        -Name "pip-WordPress-$StudentShortName-LB" `
        -Location $GeoLocation `
        -AllocationMethod Static `
        -Sku Standard
    
    $LoadBalancerPublicIpId = $StudentLoadBalancerPublicIp.Id

    New-AzResourceGroupDeployment `
        -Name "LB-WordPress-$StudentShortName" `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $LoadBalancerTemplatePath `
        -TemplateParameterObject @{
            location = $GeoLocation
            loadBalancerName = "lb-WordPress-$StudentShortName"
            publicIpResourceId = $LoadBalancerPublicIpId
            backendPoolJumpHostName = "jhBackendPool-$StudentShortName"
            backendPoolWordPressName = "wpBackendPool-$StudentShortName"
            loadBalancerFrontendName = "wpFrontend-$StudentShortName"
            loadBalancerTags = $TagDefault
        } `
        -Verbose | Out-Null

    $WpNicIds = @()
    for ($i = 1; $i -le $NumberOfWordpressVMs; $i++) {
        $WpVmName = "wp-$StudentShortName-${i}"
        $NicName = "nic-$StudentShortName-$WpVmName"
        $Nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $NicName
        $WpNicIds += $Nic.Id
    }

    $JumpHostNicName = "nic-$StudentShortName-vm-$StudentShortName"
    $JumpHostNic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $JumpHostNicName


    $LoadBalancer = Get-AzLoadBalancer `
        -ResourceGroupName $ResourceGroupName `
        -Name "LB-WordPress-$StudentShortName" `
        -Verbose

    $JumpHostBackendPool = $LoadBalancer.BackendAddressPools | Where-Object { $_.Name -eq "jhBackendPool-$StudentShortName" }
    $BackendPool = $LoadBalancer.BackendAddressPools | Where-Object { $_.Name -eq "wpBackendPool-$StudentShortName" }

    $JumpHostNic.IpConfigurations[0].LoadBalancerBackendAddressPools = $JumpHostBackendPool
    Set-AzNetworkInterface -NetworkInterface $JumpHostNic

    foreach ($NicId in $WpNicIds) {
        $NicName = ($NicId -split "/")[-1]
        $Nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $NicName
        $Nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $BackendPool
        Set-AzNetworkInterface -NetworkInterface $Nic
    }

    Write-Host "Load Balancer for student $($Student.ime) $($Student.prezime) created successfully.`n" -ForegroundColor Green

    # Student Load Balancer creation ended

    $StudentNumber++
}

#---------------STUDENT ENVIRONMENT CREATION ENDED---------------

Write-Host "Script finished. Environment creation for instructor and students completed successfully!" -ForegroundColor Green
