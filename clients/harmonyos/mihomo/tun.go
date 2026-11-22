package main

import (
	"net/netip"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	LC "github.com/metacubex/mihomo/listener/config"
)

type tunPlan struct {
	Addresses []string `json:"addresses"`
	Routes    []string `json:"routes"`
	DNS       []string `json:"dns"`
	MTU       uint32   `json:"mtu"`
}

func mobileTunnel(cfg *config.Config) (LC.Tun, tunPlan) {
	mtu := cfg.General.Tun.MTU
	if mtu < 1280 || mtu > 9000 {
		mtu = 1500
	}
	options := LC.Tun{
		Enable: true, Device: "vpn-tun", Stack: C.TunMips, MTU: mtu,
		Inet4Address: []netip.Prefix{netip.MustParsePrefix("172.19.0.1/30")},
	}
	plan := tunPlan{
		Addresses: []string{options.Inet4Address[0].String()},
		Routes:    []string{"0.0.0.0/0"},
		DNS:       []string{options.Inet4Address[0].Addr().Next().String()},
		MTU:       mtu,
	}
	if cfg.General.IPv6 {
		options.Inet6Address = []netip.Prefix{netip.MustParsePrefix("fdfe:dcba:9876::1/126")}
		plan.Addresses = append(plan.Addresses, options.Inet6Address[0].String())
		plan.Routes = append(plan.Routes, "::/0")
		plan.DNS = append(plan.DNS, options.Inet6Address[0].Addr().Next().String())
	}
	// The HarmonyOS VPN extension is the only inbound in this mode.
	cfg.General.Inbound = config.Inbound{}
	cfg.General.RoutingMark = 0
	cfg.General.Interface = ""
	cfg.IPTables.Enable = false
	cfg.Listeners = nil
	cfg.Tunnels = nil
	cfg.DNS.Enable = true
	cfg.DNS.Listen = ""
	cfg.DNS.ListenRoutingMark = 0
	cfg.NTP.WriteToSystem = false
	return options, plan
}
