package main

import (
	"context"
	"sort"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

const latencyURL = "https://www.gstatic.com/generate_204"

type nodeItem struct {
	Tag         string `json:"tag"`
	Type        string `json:"type"`
	Delay       uint16 `json:"urlTestDelay,omitempty"`
	DialerProxy string `json:"dialerProxy,omitempty"`
}

type nodeGroup struct {
	Tag        string     `json:"tag"`
	Selected   string     `json:"selected"`
	Selectable bool       `json:"selectable"`
	Items      []nodeItem `json:"items"`
}

type nodeGroups struct {
	Group []nodeGroup `json:"group"`
}

func snapshotGroups() *nodeGroups {
	result := &nodeGroups{}
	for name, proxy := range tunnel.Proxies() {
		group, ok := proxy.Adapter().(outboundgroup.ProxyGroup)
		if !ok || group.Hidden() {
			continue
		}
		_, selectable := group.(outboundgroup.SelectAble)
		entry := nodeGroup{Tag: name, Selected: group.Now(), Selectable: selectable}
		for _, node := range group.Proxies() {
			delay := node.LastDelayForTestUrl(latencyURL)
			if delay == ^uint16(0) {
				delay = 0
			}
			entry.Items = append(entry.Items, nodeItem{
				Tag: node.Name(), Type: node.Type().String(), Delay: delay, DialerProxy: node.ProxyInfo().DialerProxy,
			})
		}
		result.Group = append(result.Group, entry)
	}
	sort.Slice(result.Group, func(i, j int) bool { return result.Group[i].Tag < result.Group[j].Tag })
	return result
}

type liveConnection struct {
	ID          string `json:"id"`
	Destination string `json:"destination"`
	Network     string `json:"network"`
	Rule        string `json:"rule"`
	Upload      int64  `json:"upload"`
	Download    int64  `json:"download"`
}

func snapshotConnections() []liveConnection {
	var result []liveConnection
	statistic.DefaultManager.Range(func(connection statistic.Tracker) bool {
		info := connection.Info()
		result = append(result, liveConnection{
			ID: connection.ID(), Destination: info.Metadata.RemoteAddress(), Network: info.Metadata.NetWork.String(),
			Rule: info.Rule, Upload: info.UploadTotal.Load(), Download: info.DownloadTotal.Load(),
		})
		return len(result) < 200
	})
	return result
}

func control(ctx context.Context, action, group, node string) bool {
	switch action {
	case "mode":
		mode, ok := tunnel.ModeMapping[node]
		if !ok {
			return false
		}
		tunnel.SetMode(mode)
		return true
	case "close":
		connection := statistic.DefaultManager.Get(node)
		return connection == nil || connection.Close() == nil
	case "providers":
		go func() {
			for _, provider := range tunnel.Providers() {
				if ctx.Err() != nil {
					return
				}
				if provider.VehicleType().String() == "HTTP" {
					_ = provider.Update()
				}
			}
			for _, provider := range tunnel.RuleProviders() {
				if ctx.Err() != nil {
					return
				}
				if provider.VehicleType().String() == "HTTP" {
					_ = provider.Update()
				}
			}
		}()
		return true
	case "select", "test":
		proxy := tunnel.Proxies()[group]
		if proxy == nil {
			return false
		}
		if action == "test" {
			group, ok := proxy.Adapter().(outboundgroup.ProxyGroup)
			if !ok {
				return false
			}
			go func() {
				ctx, cancel := context.WithTimeout(ctx, 4*time.Second)
				defer cancel()
				_, _ = group.URLTest(ctx, latencyURL, nil)
			}()
			return true
		}
		selector, ok := proxy.Adapter().(outboundgroup.SelectAble)
		if !ok || selector.Set(node) != nil {
			return false
		}
		cachefile.Cache().SetSelected(group, node)
		return true
	default:
		return false
	}
}
