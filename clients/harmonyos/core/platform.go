//go:build openharmony

package main

/*
#cgo LDFLAGS: -lnet_connection
#include <network/netmanager/net_connection.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

static int32_t bindSocket(int32_t fd, int32_t netID) {
	NetConn_NetHandle handle = {0};
	handle.netId = netID;
	return OH_NetConn_BindSocket(fd, &handle);
}

static int32_t interfaceMTU(const char *name) {
	int fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (fd < 0) {
		return 1280;
	}
	struct ifreq request = {0};
	strncpy(request.ifr_name, name, sizeof(request.ifr_name) - 1);
	int result = ioctl(fd, SIOCGIFMTU, &request);
	close(fd);
	return result == 0 ? request.ifr_mtu : 1280;
}

static int findInterface(const char *address, char *name) {
	unsigned char bytes[sizeof(struct in6_addr)];
	int family = strchr(address, ':') == NULL ? AF_INET : AF_INET6;
	if (inet_pton(family, address, bytes) != 1) {
		return 0;
	}
	struct ifaddrs *interfaces;
	if (getifaddrs(&interfaces) != 0) {
		return 0;
	}
	int found = 0;
	for (struct ifaddrs *entry = interfaces; entry != NULL; entry = entry->ifa_next) {
		if (entry->ifa_addr == NULL || entry->ifa_addr->sa_family != family) {
			continue;
		}
		if ((family == AF_INET && memcmp(bytes, &((struct sockaddr_in *)entry->ifa_addr)->sin_addr, sizeof(struct in_addr)) == 0)
		    || (family == AF_INET6 && memcmp(bytes, &((struct sockaddr_in6 *)entry->ifa_addr)->sin6_addr, sizeof(struct in6_addr)) == 0)) {
			strncpy(name, entry->ifa_name, IF_NAMESIZE - 1);
			found = 1;
			break;
		}
	}
	freeifaddrs(interfaces);
	return found;
}
*/
import "C"

import (
	"context"
	"errors"
	"fmt"
	"net/netip"
	"sync/atomic"
	"unsafe"

	"github.com/sagernet/sing-box/experimental/libbox"
)

var unsupported = errors.New("unsupported on HarmonyOS")

type platform struct {
	ctx      context.Context
	requests chan tunPlan
	tunnel   chan int32
	netID    int32
	upstream *libbox.NetworkInterface
	opened   atomic.Bool
	tunName  string
}

var _ libbox.PlatformInterface = (*platform)(nil)

func (*platform) LocalDNSTransport() libbox.LocalDNSTransport { return nil }
func (*platform) UsePlatformAutoDetectInterfaceControl() bool { return true }

func (p *platform) AutoDetectInterfaceControl(fd int32) error {
	if code := C.bindSocket(C.int32_t(fd), C.int32_t(p.netID)); code != 0 {
		return fmt.Errorf("bind socket to underlying network: code %d", int32(code))
	}
	return nil
}

func (p *platform) OpenTun(options libbox.TunOptions) (int32, error) {
	if !options.GetAutoRoute() || options.GetIncludePackage().HasNext() || options.GetExcludePackage().HasNext() || options.IsHTTPProxyEnabled() {
		return -1, errors.New("HarmonyOS requires auto_route and does not support Android package filters or platform HTTP proxy settings")
	}
	plan := tunPlan{MTU: options.GetMTU()}
	for _, iterator := range []libbox.RoutePrefixIterator{options.GetInet4Address(), options.GetInet6Address()} {
		for iterator.HasNext() {
			plan.Addresses = append(plan.Addresses, iterator.Next().String())
		}
	}
	for _, iterator := range []libbox.RoutePrefixIterator{options.GetInet4RouteRange(), options.GetInet6RouteRange()} {
		for iterator.HasNext() {
			plan.Routes = append(plan.Routes, iterator.Next().String())
		}
	}
	if mode := options.GetDNSMode(); mode != nil && mode.Value != libbox.DNSModeDisabled {
		servers, err := options.GetDNSServerAddress()
		if err != nil {
			return -1, err
		}
		for servers.HasNext() {
			plan.DNS = append(plan.DNS, servers.Next())
		}
	}
	if err := plan.validate(); err != nil {
		return -1, err
	}
	select {
	case p.requests <- plan:
	case <-p.ctx.Done():
		return -1, p.ctx.Err()
	}
	select {
	case fd := <-p.tunnel:
		p.opened.Store(true)
		return fd, nil
	case <-p.ctx.Done():
		return -1, p.ctx.Err()
	}
}

func (p *platform) TunName() string { return p.tunName }

func tunName(plan *tunPlan) string {
	for _, address := range plan.Addresses {
		prefix, err := netip.ParsePrefix(address)
		if err != nil {
			continue
		}
		host := C.CString(prefix.Addr().String())
		var name [C.IF_NAMESIZE]C.char
		found := C.findInterface(host, &name[0])
		C.free(unsafe.Pointer(host))
		if found != 0 {
			return C.GoString(&name[0])
		}
	}
	return "vpn-tun"
}

func (p *platform) StartDefaultInterfaceMonitor(listener libbox.InterfaceUpdateListener) error {
	listener.UpdateDefaultInterface(p.upstream.Name, p.upstream.Index, false, false)
	return nil
}

func (*platform) CloseDefaultInterfaceMonitor(libbox.InterfaceUpdateListener) error { return nil }

func newPlatform(ctx context.Context, netID int32, interfaceName string) (*platform, error) {
	name := C.CString(interfaceName)
	defer C.free(unsafe.Pointer(name))
	index := C.if_nametoindex(name)
	if index == 0 {
		return nil, errors.New("underlying network interface does not exist")
	}
	return &platform{
		ctx: ctx, netID: netID,
		requests: make(chan tunPlan), tunnel: make(chan int32),
		upstream: &libbox.NetworkInterface{Name: interfaceName, Index: int32(index), MTU: int32(C.interfaceMTU(name)), Type: libbox.InterfaceTypeOther},
	}, nil
}

type interfaceIterator struct{ value *libbox.NetworkInterface }

func (i *interfaceIterator) HasNext() bool { return i.value != nil }
func (i *interfaceIterator) Next() *libbox.NetworkInterface {
	value := i.value
	i.value = nil
	return value
}

func (p *platform) GetInterfaces() (libbox.NetworkInterfaceIterator, error) {
	return &interfaceIterator{value: p.upstream}, nil
}

func (*platform) UnderNetworkExtension() bool      { return true }
func (*platform) IncludeAllNetworks() bool         { return true }
func (*platform) ReadWIFIState() *libbox.WIFIState { return nil }
func (*platform) ClearDNSCache()                   {}
func (*platform) RegisterMyInterface(string)       {}
func (*platform) FindConnectionOwner(int32, string, int32, string, int32) (*libbox.ConnectionOwner, error) {
	return nil, unsupported
}
func (*platform) SendNotification(*libbox.Notification) error              { return unsupported }
func (*platform) CancelNotification(string, int32) error                   { return unsupported }
func (*platform) StartNeighborMonitor(libbox.NeighborUpdateListener) error { return unsupported }
func (*platform) CloseNeighborMonitor(libbox.NeighborUpdateListener) error { return nil }
func (*platform) UsePlatformShell() bool                                   { return false }
func (*platform) CheckPlatformShell() error                                { return unsupported }
func (*platform) OpenShellSession(*libbox.PlatformUser, string, libbox.StringIterator, string, int32, int32) (libbox.ShellSession, error) {
	return nil, unsupported
}
func (*platform) LookupUser(string) (*libbox.PlatformUser, error) { return nil, unsupported }
func (*platform) LookupSFTPServer() (string, error)               { return "", unsupported }
func (*platform) ReadSystemSSHHostKey() (string, error)           { return "", unsupported }
func (*platform) TailscaleHostname() string                       { return "" }
func (*platform) UsePlatformBridge() bool                         { return false }
func (*platform) CreateBridge(*libbox.BridgeOptions) (libbox.BridgeSession, error) {
	return nil, unsupported
}
func (*platform) UsePlatformAutoRedirect() bool { return false }
func (*platform) CreateAutoRedirect([]byte, libbox.AutoRedirectHandler) (libbox.AutoRedirectSession, error) {
	return nil, unsupported
}
