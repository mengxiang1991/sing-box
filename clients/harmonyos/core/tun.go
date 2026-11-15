package main

import (
	"encoding/json"
	"errors"
	"net/netip"
)

type inbound struct {
	Type         string `json:"type"`
	Stack        string `json:"stack"`
	AutoRoute    bool   `json:"auto_route"`
	AutoRedirect bool   `json:"auto_redirect"`
}

func checkTunInbound(config string) error {
	var profile struct {
		Inbounds []inbound `json:"inbounds"`
	}
	if err := json.Unmarshal([]byte(config), &profile); err != nil {
		return errors.New("无法读取 sing-box JSON 配置")
	}
	tuns := 0
	for _, item := range profile.Inbounds {
		if item.Type != "tun" {
			continue
		}
		tuns++
		if item.Stack != "" && item.Stack != "go" {
			return errors.New("鸿蒙版当前支持 TUN 的 go 网络栈")
		}
		if !item.AutoRoute || item.AutoRedirect {
			return errors.New("请为 TUN 启用 auto_route 并关闭 auto_redirect")
		}
	}
	if tuns != 1 {
		return errors.New("配置需要包含一个 TUN 入站")
	}
	return nil
}

type tunPlan struct {
	Addresses []string `json:"addresses"`
	Routes    []string `json:"routes"`
	DNS       []string `json:"dns"`
	MTU       int32    `json:"mtu"`
}

func (p tunPlan) validate() error {
	if len(p.Addresses) == 0 {
		return errors.New("the TUN inbound needs an address")
	}
	if len(p.Routes) == 0 || len(p.Routes) > 1024 {
		return errors.New("HarmonyOS requires between 1 and 1024 VPN routes")
	}
	var families [2]bool
	for _, address := range p.Addresses {
		prefix, err := netip.ParsePrefix(address)
		if err != nil {
			return errors.New("invalid VPN address prefix")
		}
		families[familyIndex(prefix.Addr())] = true
	}
	for _, route := range p.Routes {
		prefix, err := netip.ParsePrefix(route)
		if err != nil || prefix != prefix.Masked() {
			return errors.New("invalid VPN route prefix")
		}
		if !families[familyIndex(prefix.Addr())] {
			return errors.New("VPN route has no TUN address in its address family")
		}
	}
	for _, dns := range p.DNS {
		addr, err := netip.ParseAddr(dns)
		if err != nil || addr.Zone() != "" || !families[familyIndex(addr)] {
			return errors.New("invalid VPN DNS address for the configured TUN")
		}
	}
	minimumMTU := int32(576)
	if families[1] {
		minimumMTU = 1280
	}
	if p.MTU < minimumMTU || p.MTU > 65535 {
		return errors.New("VPN MTU is outside the supported range")
	}
	return nil
}

func familyIndex(address netip.Addr) int {
	if address.Is4() {
		return 0
	}
	return 1
}
