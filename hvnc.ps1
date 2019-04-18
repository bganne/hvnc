# HyperV VM name
# you can get them using eg. 'hvc list'
param([string]$VM="*")

# HyperV socket endpoint
# https://docs.microsoft.com/en-us/dotnet/api/system.net.endpoint?view=netframework-4.7.2
# https://github.com/PowerShell/PowerShell/blob/master/src/System.Management.Automation/engine/remoting/common/RemoteSessionHyperVSocket.cs
class HyperVEndPoint : System.Net.EndPoint
{
    $vmId
    $serviceId

    HyperVEndPoint($vmId, $serviceId)
    {
        $this.vmId = $vmId
        $this.serviceId = $serviceId
    }

    [System.Net.SocketAddress] Serialize()
    {
        $saddr = [System.Net.SocketAddress]::new(34, 36); # AF_HYPERV, 36-bytes
        $vid = $this.vmId.ToByteArray()
        $sid = $this.serviceId.ToByteArray()
        $saddr[2] = 0 # reserved1
        $saddr[3] = 0 # reserved1
        for ($i=0; $i -lt 16; $i++) {
            $saddr[$i+ 4] = $vid[$i] # copy VM id
            $saddr[$i+20] = $sid[$i] # copy service id
        }
        return $saddr
    }
}

class SocketPair : System.Net.Sockets.Socket
{
    $buffer
    $peer

    SocketPair($socket) : base($socket.DuplicateAndClose([System.Diagnostics.Process]::GetCurrentProcess().Id)) {}
    SocketPair($family, $type, $protocol) : base($family, $type, $protocol) {}

    static [Array] Pair($s1, $s2, $buffer)
    {
        $s1.buffer = $s2.buffer = $buffer
        $s1.peer = $s2
        $s2.peer = $s1
        return $s1, $s2
    }

    [bool] ProcessEvent()
    {
        $len  = $this.Receive($this.buffer)
        if ($len -le 0) {
            return 0
        }
        $len2 = $this.peer.Send($this.buffer, $len, 0)
        return ($len2 -eq $len)
    }
}

class SocketServer : System.Net.Sockets.Socket
{
    $buf
    $slist
    $vep

    SocketServer($socket) : base($socket) {}

    static [SocketServer] Create($tep, $vep)
    {
        $s = [System.Net.Sockets.Socket]::new($tep.AddressFamily,
                                              [System.Net.Sockets.SocketType]::Stream,
                                              [System.Net.Sockets.ProtocolType]::Tcp)
        $s.Bind($tep)
        $s.Listen(32)
        $s = [SocketServer]::new($s.DuplicateAndClose([System.Diagnostics.Process]::GetCurrentProcess().Id))
        $s.buf = New-Object byte[] 65536
        $s.vep = $vep
        $s.slist = [System.Collections.ArrayList]::new()
        $s.slist.Add($s)
        return $s
    }

    [bool] ProcessEvent()
    {
        $ts = [SocketPair]::new($this.Accept())
        $vs = [SocketPair]::new(34, 1, 1) # AF_HYPERV, SOCK_STREAM, HV_PROTOCOL_RAW
        $vs.Connect($this.vep)
        $ts, $vs = [SocketPair]::Pair($ts, $vs, $this.buf)
        $this.slist.Add($ts)
        $this.slist.Add($vs)
        return 1
    }

    [void] Run()
    {
        while (1) {
            $rlist = $this.slist.Clone()
            [System.Net.Sockets.Socket]::Select($rlist, $null, $null, -1)
            foreach ($s in $rlist) {
                if (!$s.ProcessEvent()) {
                    $this.slist.Remove($s)
                    $this.slist.Remove($s.peer)
                    $s.Close()
                    $s.peer.Close()
                }
            }
        }
    }
}

#
# Connect to the VM vsock
# On Linux you can use eg. sudo socat SOCKET-LISTEN:40:0:x0000x16000000xffffffffx00000000,reuseaddr,fork TCP:localhost:22
# to redirect to local ssh
#
# get VM GUID from name
$vid =  [GUID](Get-VM -Name $VM).Id
# Service GUID
# See https://docs.microsoft.com/en-us/virtualization/hyper-v-on-windows/user-guide/make-integration-service
# We use port 22 here (0x16)
$sid=[GUID]"00000016-facb-11e6-bd58-64006a7986d3"
$vep = [HyperVEndPoint]::new($vid, $sid)
$tep = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse("127.0.0.1"), 2222)
[SocketServer]::Create($tep, $vep).Run()
