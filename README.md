# Poor man's HyperV netcat

Simple PowerShell script to create a TCP-to-HyperV VMBus socket proxy.
The main usecase is to ssh to a Linux HyperV VM from Windows through HyperV VMBus socket.

## TL;DR

On the Linux VM, use `socat` to forward VMBus socket to sshd TCP socket:

    socat SOCKET-LISTEN:40:0:x0000x16000000xffffffffx00000000,reuseaddr,fork TCP:localhost:22

On the Windows host, run this script in the background (do not forget to update the 1st line with the name of the VM you want to connect to):

    powershell.exe -command 'start-process -windowstyle hidden -verb runas "powershell.exe" -argumentlist "-executionpolicy remotesigned -F hvnc.ps1"'

You can now ssh to your guest Linux VM from Windows by connecting to localhost:2222:

    ssh -p2222 user@locahost

## Why?

HyperV and WSL are an interesting platform for Linux development in a corporate environment (understand: IT supports Windows only), but there are some rough edges.
The main issue I had to solve was to consistently access my VM through SSH from WSL.
My corporate VPN client (that I have to use when not in the office) breaks all networking (hence breaking ssh-to-VM when using the VPN) and HyperV requires Windows admin rights (which you cannot get from WSL).
The VMBus socket is not impacted by the VPN network configuration and I can ssh to localhost from WSL through TCP.

## Performance

It seems that performance is higher than plain TCP over hvnet (HyperV para-virtualized networking interface): my simple non-representative benchmark gave me ~30GB/s using TCP-VMBus-TCP vs ~20GB/s for plain TCP.
