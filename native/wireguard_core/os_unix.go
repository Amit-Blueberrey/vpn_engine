//go:build !windows
package main

import (
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/ipc"
	"golang.zx2c4.com/wireguard/tun"
	"net"
	"os"
)

func createTunDevice(name string, mtu int, platformFd int) (tun.Device, error) {
	if platformFd >= 0 {
		return tun.CreateTUNFromFile(os.NewFile(uintptr(platformFd), "vpn"), mtu)
	}
	return tun.CreateTUN(name, mtu)
}

func setupUAPI(name string, dev *device.Device) net.Listener {
	uapiFile, err := ipc.UAPIOpen(name)
	if err != nil {
		return nil
	}
	uapiLn, err := ipc.UAPIListen(name, uapiFile)
	if err != nil {
		return nil
	}
	go func() {
		for {
			conn, err := uapiLn.Accept()
			if err != nil {
				return
			}
			go dev.IpcHandle(conn)
		}
	}()
	return uapiLn
}
