package main

import "testing"

func TestCheckProfile(t *testing.T) {
	for _, test := range []struct {
		name string
		text string
		ok   bool
	}{
		{"Clash rules", "mode: rule\nproxy-groups:\n- name: Pick\n  type: select\n  proxies: [DIRECT]\nrules: ['DOMAIN,example.com,Pick', 'MATCH,DIRECT']\n", true},
		{"Clash provider", "proxy-providers:\n  nodes:\n    type: inline\n    payload:\n    - {name: example, type: ss, server: 192.0.2.1, port: 8388, cipher: aes-128-gcm, password: example}\nproxy-groups:\n- name: Pick\n  type: select\n  use: [nodes]\n  proxies: [DIRECT]\nrules: ['MATCH,Pick']\n", true},
		{"broken YAML", "proxies: [", false},
		{"unknown outbound", "rules: ['MATCH,Missing']\n", false},
		{"sing-box JSON", `{"outbounds":[{"type":"direct"}]}`, false},
		{"empty mapping", "{}", false},
		{"chained proxies", `proxies:
  - {name: Entry, type: socks5, server: 192.0.2.1, port: 1080}
  - {name: Exit, type: socks5, server: 192.0.2.2, port: 1080, dialer-proxy: Entry}
rules: ['MATCH,Exit']
`, true},
		{"circular chain", `proxies:
  - {name: Entry, type: socks5, server: 192.0.2.1, port: 1080, dialer-proxy: Exit}
  - {name: Exit, type: socks5, server: 192.0.2.2, port: 1080, dialer-proxy: Entry}
rules: ['MATCH,Exit']
`, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			if ok := checkProfile(test.text); ok != test.ok {
				t.Fatalf("checkProfile() = %v, want %v", ok, test.ok)
			}
		})
	}
}
