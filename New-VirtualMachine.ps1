function New-VirtualMachine {
    <#
    .SYNOPSIS
        Creates a new virtual machine in the specified cluster.

    .EXAMPLE
        New-VirtualMachine -Name TestVM2 -ClusterNumber 1 -HypervisorNumber 1 -ProcessorCount 2 -MemoryStartup 1024MB -MemoryMaximum 2048MB -DiskSize 30GB -VlanID 1001 -OperatingSystem 'Server 2019' -Path "\\fs1\Perf1\Testing"
        Creates a new VM named "TestVM2" in the FC1 cluster on hypervisor FC11 with the specified specs. It also uses the default memory minimum value of 512MB, the default generation value of 2, and the default switch name "SETswitch1". Prompts for credentials.

        New-VirtualMachine -Name TestVM3 -ClusterNumber 1 -HypervisorNumber 3 -ProcessorCount 2 -MemoryStartup 2048MB -MemoryMinimum 1024MB -MemoryMaximum 4096MB -DiskSize 30GB -VlanID 1001 -OperatingSystem 'Server 2019' -Credentials $creds
        Creates a new VM named "TestVM3" in the FC1 cluster on FC13. Uses the credentials stored in $creds (this must be a PSCredntial object).

    .NOTES
        Author: Eric Claus
        Last ModifiedL: 3/10/2021
    #>

    [CmdletBinding(DefaultParameterSetName="None")]

    Param(
        [Parameter(Mandatory=$true)]
            [string]$Name,

        [int]$ClusterNumber = 1,
        
        [int]$HypervisorNumber = 1,

        [Parameter(Mandatory=$true)]
            [int]$ProcessorCount,

        [Parameter(Mandatory=$true)]
            [Int64]$MemoryStartup,

        [Int64]$MemoryMinimum = 512MB,

        [Int64]$MemoryMaximum = 8192MB,

        [Int64]$DiskSize = 40GB,

        [string]$Path = "\\fs$ClusterNumber\Perf1",

        [string]$SwitchName = "SETswitch1",

        [Parameter(Mandatory=$true)]
            [int]$VlanID,

        [int]$Generation = 2,

        [switch]$FixedMemory,

        [Parameter(Mandatory=$true)]
            [ValidateSet('Server 2019', 'CentOS 7')]
            [string]$OperatingSystem,

        [pscredential]$Credentials = (Get-Credential),

        [Parameter(ParameterSetName="Disks",Mandatory=$false)]
            [switch]$AddExtraDisks,


        [Parameter(ParameterSetName="Disks",Mandatory=$true)]
            [Int64[]]$ExtraDiskSIzes
    )

    $ClusterName = "FC$ClusterNumber"

    #Create a new Remote Powershell session

    # Thanks to Keith Hill for this solution at https://stackoverflow.com/a/3705824
    $session = New-PSSession -ComputerName "$ClusterName$HypervisorNumber" -Credential $Credentials -Authentication Credssp

    $scriptBlock = {

        # This is horrible code that I wrote - Eric 
        $Name, $ClusterNumber, $HypervisorNumber, $ProcessorCount, $MemoryStartup, $MemoryMinimum, $MemoryMaximum, $DiskSize, $SwitchName, $VlanID, $Generation, $FixedMemory, $OperatingSystem, $AddExtraDisks, $ExtraDiskSIzes, $ClusterName, $Credentials, $Path = 
        $args[0], $args[1], $args[2], $args[3], $args[4], $args[5], $args[6], $args[7], $args[8], $args[9], $args[10], $args[11], $args[12], $args[13], $args[14], $args[15], $args[16], $args[17]

        #Create the New VM. Change variables such as VM Name, Path, VHD Path, disk size, etc. By default the disk will be dynamic.

        New-VM -Name $Name -Path "$Path\" -NewVHDPath "$Path\$Name\Disk1.vhdx" -NewVHDSizeBytes $DiskSize -Generation $Generation -MemoryStartupBytes $MemoryStartup -SwitchName $SwitchName

        #Set the VLAN ID of the virtual switch that was just created

        Set-VMNetworkAdapterVlan -VMName $Name -Access -VlanId $VlanID

        #With the VM created, configure CPU, memory, etc.

        Set-VM -Name $Name -ProcessorCount $ProcessorCount -DynamicMemory -MemoryMinimumBytes $MemoryMinimum -MemoryMaximumBytes $MemoryMaximum

        #If you want to create a second (or third, etc.) hard drive. If you want a Fixed disk, then change -dynamic to -fixed

        if ($AddExtraDisks) {
            $DiskCount = 1

            foreach ($DiskSize in $ExtraDiskSIzes) {
                $DiskCount ++

                $DiskPath = "$Path\$Name\Disk$DiskCount.vhdx"

                New-VHD -Path $DiskPath -SizeBytes $Disksize -Dynamic

                #IF you need to add a second disk...

                Add-VMHardDiskDrive -VMName $Name -Path $DiskPath
            }
        }
    
        $IsoRootDir = "\\FS1\ISO"

        Switch ($OperatingSystem)
        {
            "Server 2019" {$ISO = "$IsoRootDir\SW_DVD9_Win_Server_STD_CORE_2019_64Bit_English_DC_STD_MLF_X21-96581.iso"}
            "CentOS 7" {$ISO = "$IsoRootDir\CentOS-7-x86_64-DVD-1810.iso"; Set-VMFirmware -VMName $Name -EnableSecureBoot Off}
        }
    
        #Add a DVD drive and map the ISO to drive

        Add-VMDvdDrive -VMName $Name -Path $ISO

        #Now we need to set the DVD drive as the primary boot device.

        Set-VMFirmware -VMName $Name -FirstBootDevice $(Get-VMDvdDrive -VMName $Name)

        #Finally, we need to add the VM to Failover Cluster Manager

        Add-ClusterVirtualMachineRole -VMName $Name -Cluster $ClusterName

        #to start the VM...

        Start-VM -Name $Name
    }
 
    # This is horrible code that I wrote - Eric 
    $params = ($Name, $ClusterNumber, $HypervisorNumber, $ProcessorCount, $MemoryStartup, $MemoryMinimum, $MemoryMaximum, $DiskSize, $SwitchName, $VlanID, $Generation, $FixedMemory, $OperatingSystem, $AddExtraDisks, $ExtraDiskSIzes, $ClusterName, $Credentials, $Path)
    
    ## Invoke the above commands (contained in the $scriptBlock) on the remote computer
    Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $params

    Remove-PSSession -Session $session

    #Notes: As a best practice, once Windows or Linux is installed, remove the ISO from the DVD drive. 
}
