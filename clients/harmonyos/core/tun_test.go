package main

import (
	"testing"
)

func TestCheckTunInbound(t *testing.T) {
	for name, config := range map[string]string{
		"native stack":   `{"inbounds":[{"type":"tun", "stack":"system", "auto_route":true}]}`,
		"no TUN":         `{"inbounds":[{"type":"mixed"}]}`,
		"two TUNs":       `{"inbounds":[{"type":"tun", "auto_route":true},{"type":"tun", "auto_route":true}]}`,
		"auto redirect":  `{"inbounds":[{"type":"tun", "auto_route":true, "auto_redirect":true}]}`,
		"route disabled": `{"inbounds":[{"type":"tun"}]}`,
	} {
		t.Run(name, func(t *testing.T) {
			if checkTunInbound(config) == nil {
				t.Fatal("unsupported configuration accepted")
			}
		})
	}
	if err := checkTunInbound(`{"inbounds":[{"type":"tun","stack":"go","auto_route":true}]}`); err != nil {
		t.Fatal(err)
	}
}

func TestValidateTunPlan(t *testing.T) {
	valid := tunPlan{
		Addresses: []string{"172.19.0.1/30", "fd00::1/126"},
		Routes:    []string{"0.0.0.0/0", "::/0"},
		DNS:       []string{"172.19.0.2", "fd00::2"},
		MTU:       1400,
	}
	if err := valid.validate(); err != nil {
		t.Fatal(err)
	}
	for name, update := range map[string]func(*tunPlan){
		"missing address": func(p *tunPlan) { p.Addresses = nil },
		"missing routes":  func(p *tunPlan) { p.Routes = nil },
		"uncovered IPv6":  func(p *tunPlan) { p.Addresses = p.Addresses[:1] },
		"unmasked route":  func(p *tunPlan) { p.Routes = []string{"10.1.1.1/8"} },
		"invalid DNS":     func(p *tunPlan) { p.DNS = []string{"not-an-address"} },
		"undersized MTU":  func(p *tunPlan) { p.MTU = 576 },
	} {
		t.Run(name, func(t *testing.T) {
			plan := valid
			update(&plan)
			if err := plan.validate(); err == nil {
				t.Fatal("invalid TUN configuration was accepted")
			}
		})
	}
}
