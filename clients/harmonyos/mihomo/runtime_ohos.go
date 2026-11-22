//go:build openharmony

package main

// #include <stdlib.h>
import "C"

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"unsafe"

	MC "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type coreState struct {
	State       string           `json:"state"`
	Error       string           `json:"error,omitempty"`
	Tun         *tunPlan         `json:"tun,omitempty"`
	Groups      *nodeGroups      `json:"groups,omitempty"`
	Mode        string           `json:"mode,omitempty"`
	Connections []liveConnection `json:"connections,omitempty"`
}

var core = struct {
	sync.Mutex
	status coreState
	fd     chan int
	cancel context.CancelFunc
	ctx    context.Context
}{status: coreState{State: "stopped"}}

//export MBStart
func MBStart(config, directory *C.char) C.int {
	if config == nil || directory == nil {
		return 1
	}
	core.Lock()
	defer core.Unlock()
	if core.cancel != nil {
		return 1
	}
	ctx, cancel := context.WithCancel(context.Background())
	core.cancel = cancel
	core.ctx = ctx
	core.status = coreState{State: "starting"}
	core.fd = make(chan int, 1)
	go runCore(ctx, C.GoString(config), filepath.Join(C.GoString(directory), "mihomo"), core.fd)
	return 0
}

func runCore(ctx context.Context, content, directory string, fd <-chan int) {
	var failure string
	defer func() {
		core.Lock()
		defer core.Unlock()
		core.cancel()
		core.cancel = nil
		core.ctx = nil
		core.fd = nil
		core.status = coreState{State: "stopped", Error: failure}
	}()
	if err := os.MkdirAll(directory, 0o700); err != nil {
		failure = "无法创建 Mihomo 配置目录"
		return
	}
	MC.SetHomeDir(directory)
	cfg, err := executor.ParseWithBytes([]byte(content))
	if err != nil {
		failure = "配置未通过 Mihomo 校验"
		return
	}
	options, plan := mobileTunnel(cfg)
	core.Lock()
	if ctx.Err() == nil {
		core.status.Tun = &plan
	}
	core.Unlock()
	select {
	case options.FileDescriptor = <-fd:
	case <-ctx.Done():
		return
	}
	if ctx.Err() != nil {
		return
	}
	executor.ApplyConfig(cfg, true)
	defer func() {
		tunnel.OnSuspend()
		statistic.DefaultManager.Range(func(connection statistic.Tracker) bool {
			_ = connection.Close()
			return true
		})
		for _, provider := range tunnel.Providers() {
			if closer, ok := provider.(interface{ Close() error }); ok {
				_ = closer.Close()
			}
		}
		for _, provider := range tunnel.RuleProviders() {
			if closer, ok := provider.(interface{ Close() error }); ok {
				_ = closer.Close()
			}
		}
		executor.Shutdown()
	}()
	if ctx.Err() != nil {
		return
	}
	listener, err := sing_tun.New(options, tunnel.Tunnel)
	if err != nil {
		failure = "Mihomo 无法接管鸿蒙 TUN"
		return
	}
	defer listener.Close()
	core.Lock()
	if ctx.Err() == nil {
		core.status = coreState{State: "connected"}
	}
	core.Unlock()
	<-ctx.Done()
}

//export MBSetTunnel
func MBSetTunnel(fd C.int) C.int {
	core.Lock()
	defer core.Unlock()
	if core.status.Tun == nil || fd <= 0 {
		return 1
	}
	core.status.Tun = nil
	core.fd <- int(fd)
	return 0
}

//export MBStatus
func MBStatus() *C.char {
	core.Lock()
	defer core.Unlock()
	current := core.status
	if current.State == "connected" {
		current.Groups = snapshotGroups()
		current.Mode = tunnel.Mode().String()
		current.Connections = snapshotConnections()
	}
	state, _ := json.Marshal(current)
	return C.CString(string(state))
}

//export MBControl
func MBControl(action, group, node *C.char) C.int {
	core.Lock()
	defer core.Unlock()
	if core.status.State != "connected" || action == nil || group == nil || node == nil ||
		!control(core.ctx, C.GoString(action), C.GoString(group), C.GoString(node)) {
		return 1
	}
	return 0
}

//export MBStop
func MBStop() {
	core.Lock()
	defer core.Unlock()
	if core.cancel != nil {
		core.status = coreState{State: "stopping"}
		core.cancel()
	}
}

//export MBFree
func MBFree(value *C.char) {
	C.free(unsafe.Pointer(value))
}
