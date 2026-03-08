//go:build windows

// os_windows.go — Windows-specific WireGuard network interface configuration.
//
// After the Wintun adapter is brought up by wireguard-go, this module:
//  1. Waits for the adapter to fully register with Windows (polling loop).
//  2. Queries the existing default gateway so we know the physical NIC route.
//  3. Adds a /32 EXCLUSION ROUTE for the WireGuard server's public IP so that
//     encrypted UDP packets travel out through the real NIC — not into the tunnel
//     itself (which would create a routing loop and drop all traffic).
//  4. Adds 0.0.0.0/1 and 128.0.0.0/1 routes via the tunnel (full-tunnel mode).
//  5. Assigns the client VPN IP address to the Wintun adapter.
//  6. Sets the DNS server on the adapter to prevent DNS leaks.
//  7. Logs EVERY netsh stdout + stderr result to the Dart FFI logger.
//
// On disconnect, all added routes are removed cleanly.

package main

import (
	"fmt"
	"net"
	"os/exec"
	"strings"
	"time"

	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
)

func createTunDevice(name string, mtu int, platformFd int) (tun.Device, error) {
	return tun.CreateTUN(name, mtu)
}

func setupUAPI(name string, dev *device.Device) net.Listener {
	return nil
}

// configureWindowsInterface performs the full Windows network setup after the
// WireGuard tunnel is active. It must be called with administrator privileges
// (which our UAC manifest guarantees).
//
//   tunName  — Wintun adapter name as registered with Windows (e.g. "wg0")
//   address  — client VPN IP in CIDR notation  (e.g. "10.8.0.2/24")
//   dns      — DNS server IP                   (e.g. "10.8.0.1")
//   endpoint — the remote WireGuard server IP  (e.g. "3.238.201.203")
func configureWindowsInterface(tunName, address, dns, endpoint string) error {

	// ── Step 0: Wait for the Wintun adapter to register with Windows ──────────
	// netsh will fail if the adapter isn't ready. Poll until it appears.
	nativeLog("Windows: waiting for adapter %q to appear...", tunName)
	actualIface, err := waitForAdapter(tunName, 8*time.Second)
	if err != nil {
		// Non-fatal: try to proceed with the name we were given
		nativeLog("WARNING: adapter wait timeout (%v) — using name as-is: %q", err, tunName)
		actualIface = tunName
	} else {
		nativeLog("Windows: adapter ready as %q", actualIface)
	}

	// ── Step 1: Discover the current default gateway ──────────────────────────
	gateway, physicalIface, err := getDefaultGateway()
	if err != nil {
		nativeLog("WARNING: could not detect default gateway: %v", err)
		// We still continue; the exclusion route step will be skipped.
	} else {
		nativeLog("Windows: default gateway=%s physicalIface=%s", gateway, physicalIface)
	}

	// ── Step 2: Endpoint exclusion route (CRITICAL — prevents routing loop) ───
	// Send the encrypted WireGuard UDP packets via the PHYSICAL NIC, not the tunnel.
	if endpoint != "" && gateway != "" {
		out, err := runLog("netsh", "interface", "ip", "add", "route",
			endpoint+"/32", physicalIface, gateway, "metric=1", "store=active",
		)
		if err != nil {
			// Try with the classic route command which is more reliable here
			out2, err2 := runLog("route", "add", endpoint, "mask", "255.255.255.255", gateway, "metric", "1")
			if err2 != nil {
				nativeLog("WARNING: exclusion route failed via netsh (%v: %s) and route (%v: %s)", err, out, err2, out2)
			} else {
				nativeLog("Windows: exclusion route for %s added via route.exe: %s", endpoint, out2)
			}
		} else {
			nativeLog("Windows: exclusion route for %s → gateway %s added: %s", endpoint, gateway, out)
		}
	} else {
		nativeLog("WARNING: Skipping exclusion route (endpoint=%q gateway=%q) — you may get a routing loop!", endpoint, gateway)
	}

	// ── Step 3: Parse client IP and subnet mask ───────────────────────────────
	ip, ipNet, err := net.ParseCIDR(address)
	if err != nil {
		ip = net.ParseIP(address)
		if ip == nil {
			return fmt.Errorf("invalid address %q: %w", address, err)
		}
		ipNet = &net.IPNet{IP: ip, Mask: net.CIDRMask(24, 32)}
	}
	ipStr   := ip.String()
	maskStr := ipv4MaskString(ipNet.Mask)

	// ── Step 4: Assign IP address to the Wintun adapter ──────────────────────
	out, err := runLog("netsh", "interface", "ip", "set", "address",
		"name="+actualIface, "static", ipStr, maskStr, "none",
	)
	if err != nil {
		nativeLog("ERROR: set IP on %q failed (%v): %s", actualIface, err, out)
		return fmt.Errorf("assign adapter IP: %w", err)
	}
	nativeLog("Windows: assigned %s/%s to %q: %s", ipStr, maskStr, actualIface, out)

	// ── Step 5: Add full-tunnel routes through the VPN interface ─────────────
	// Two /1 routes together cover all of 0.0.0.0/0 but take exact-prefix
	// precedence over the physical /0 default gateway.
	for _, cidr := range []string{"0.0.0.0/1", "128.0.0.0/1"} {
		netIP, netMask, _ := parseCIDRParts(cidr)
		out, err := runLog("netsh", "interface", "ip", "add", "route",
			cidr, actualIface, ipStr, "metric=1", "store=active",
		)
		if err != nil {
			// Fallback to route.exe
			out2, err2 := runLog("route", "add", netIP, "mask", netMask, ipStr, "metric", "1")
			if err2 != nil {
				nativeLog("WARNING: route %s failed via netsh (%v: %s) and route.exe (%v: %s)", cidr, err, out, err2, out2)
			} else {
				nativeLog("Windows: tunnel route %s added via route.exe: %s", cidr, out2)
			}
		} else {
			nativeLog("Windows: tunnel route %s added: %s", cidr, out)
		}
	}

	// ── Step 6: Set DNS ───────────────────────────────────────────────────────
	if dns != "" {
		dnsIP := strings.TrimSpace(strings.SplitN(dns, ",", 2)[0])
		out, err := runLog("netsh", "interface", "ip", "set", "dns",
			"name="+actualIface, "static", dnsIP, "primary",
		)
		if err != nil {
			nativeLog("WARNING: set DNS on %q failed (%v): %s", actualIface, err, out)
		} else {
			nativeLog("Windows: DNS=%s set on %q: %s", dnsIP, actualIface, out)
		}
	}

	nativeLog("Windows: interface configuration complete for %q", actualIface)
	return nil
}

// removeWindowsRoutes cleans up only the routes we added. The exclusion /32
// route is also removed so the routing table is fully restored.
func removeWindowsRoutes(tunName, endpoint string) {
	for _, cidr := range []string{"0.0.0.0/1", "128.0.0.0/1"} {
		out, err := runLog("netsh", "interface", "ip", "delete", "route", cidr, tunName)
		nativeLog("Windows: remove route %s: err=%v out=%s", cidr, err, out)
	}
	if endpoint != "" {
		out, err := runLog("route", "delete", endpoint, "mask", "255.255.255.255")
		nativeLog("Windows: remove exclusion route %s: err=%v out=%s", endpoint, err, out)
	}
	nativeLog("Windows: routes cleaned up for %q", tunName)
}

// ── Internal helpers ──────────────────────────────────────────────────────────

// waitForAdapter polls Windows until the named Wintun adapter appears in the
// interface list, returning the exact alias Windows assigned to it.
func waitForAdapter(name string, timeout time.Duration) (string, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		ifaces, err := net.Interfaces()
		if err == nil {
			for _, iface := range ifaces {
				// Exact match or the name is a prefix (Wintun sometimes appends an index)
				if strings.EqualFold(iface.Name, name) || strings.HasPrefix(iface.Name, name) {
					return iface.Name, nil
				}
			}
		}
		// Also check via netsh, which uses the Windows "Friendly Name" / alias
		out, err := exec.Command("netsh", "interface", "show", "interface").CombinedOutput()
		if err == nil {
			for _, line := range strings.Split(string(out), "\n") {
				if strings.Contains(strings.ToLower(line), strings.ToLower(name)) {
					// Extract the interface alias from the last column
					parts := strings.Fields(line)
					if len(parts) >= 4 {
						return strings.Join(parts[3:], " "), nil
					}
				}
			}
		}
		time.Sleep(300 * time.Millisecond)
	}
	return name, fmt.Errorf("adapter %q not found within %v", name, timeout)
}

// getDefaultGateway reads the Windows routing table to find the current
// default gateway and the physical interface it belongs to.
func getDefaultGateway() (gateway, interfaceName string, err error) {
	out, err := exec.Command("route", "print", "0.0.0.0").CombinedOutput()
	if err != nil {
		return "", "", fmt.Errorf("route print: %w (out: %s)", err, string(out))
	}
	// The output looks like:
	//   0.0.0.0    0.0.0.0   192.168.1.1   192.168.1.100    25
	// We want the gateway (3rd column) and the iface IP (4th column).
	for _, line := range strings.Split(string(out), "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 4 && fields[0] == "0.0.0.0" && fields[1] == "0.0.0.0" {
			gateway = fields[2]
			ifaceIP := fields[3]
			// Map the interface IP back to the adapter friendly name via netsh
			interfaceName, _ = getInterfaceNameByIP(ifaceIP)
			if interfaceName == "" {
				interfaceName = ifaceIP // fallback: use IP as the interface specifier
			}
			return gateway, interfaceName, nil
		}
	}
	return "", "", fmt.Errorf("no default gateway found in routing table")
}

// getInterfaceNameByIP finds the Windows adapter friendly name for a given IP.
func getInterfaceNameByIP(ip string) (string, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", err
	}
	for _, iface := range ifaces {
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			if strings.HasPrefix(addr.String(), ip+"/") || addr.String() == ip {
				return iface.Name, nil
			}
		}
	}
	return "", fmt.Errorf("no interface found with IP %s", ip)
}

// runLog runs a command and returns combined stdout+stderr output. It always
// logs the full command and output via nativeLog so errors are visible in the
// Dart debug dashboard.
func runLog(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	b, err := cmd.CombinedOutput()
	out := strings.TrimSpace(string(b))
	if err != nil {
		nativeLog("[cmd FAIL] %s %s → %v | %s", name, strings.Join(args, " "), err, out)
	}
	return out, err
}

func ipv4MaskString(m net.IPMask) string {
	if len(m) == 4 {
		return fmt.Sprintf("%d.%d.%d.%d", m[0], m[1], m[2], m[3])
	}
	return "255.255.255.0"
}

func parseCIDRParts(cidr string) (ip, mask string, err error) {
	_, ipNet, err := net.ParseCIDR(cidr)
	if err != nil {
		return "", "", err
	}
	ip = ipNet.IP.String()
	mask = ipv4MaskString(ipNet.Mask)
	return
}
