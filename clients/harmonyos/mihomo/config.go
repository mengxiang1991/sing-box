package main

import (
	"github.com/metacubex/mihomo/hub/executor"
	"go.yaml.in/yaml/v3"
)

func checkProfile(text string) bool {
	data := []byte(text)
	var fields map[string]yaml.Node
	if err := yaml.Unmarshal(data, &fields); err != nil {
		return false
	}
	for _, key := range []string{"mode", "proxies", "proxy-groups", "proxy-providers", "rules", "rule-providers"} {
		if _, exists := fields[key]; exists {
			_, err := executor.ParseWithBytes(data)
			return err == nil
		}
	}
	return false
}
