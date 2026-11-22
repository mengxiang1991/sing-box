package main

import (
	"reflect"
	"testing"

	"github.com/metacubex/mihomo/hub/executor"
)

func TestMobileTunnel(t *testing.T) {
	cfg, err := executor.ParseWithBytes([]byte("mode: direct\nipv6: true\nport: 7890\nallow-lan: true\ntun:\n  auto-route: true\n  mtu: 1400\n"))
	if err != nil {
		t.Fatal(err)
	}
	options, plan := mobileTunnel(cfg)
	if options.AutoRoute || options.AutoDetectInterface || options.AutoRedirect || cfg.General.Port != 0 || cfg.General.AllowLan {
		t.Fatal("desktop listeners or route management still enabled")
	}
	if cfg.General.Tun.Enable || !options.Enable || options.Device != "vpn-tun" {
		t.Fatal("the tunnel must be started separately with a system descriptor")
	}
	if !reflect.DeepEqual(plan.Routes, []string{"0.0.0.0/0", "::/0"}) || len(plan.DNS) != 2 || plan.MTU != 1400 {
		t.Fatalf("unexpected system tunnel plan: %+v", plan)
	}
}
