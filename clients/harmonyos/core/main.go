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
	"time"
	"unsafe"

	"github.com/sagernet/sing-box/experimental/libbox"
)

type status struct {
	State string   `json:"state"`
	Error string   `json:"error,omitempty"`
	Tun   *tunPlan `json:"tun,omitempty"`
}

var runtimeState struct {
	sync.Mutex
	status
	platform *platform
	cancel   context.CancelFunc
}

//export SBStart
func SBStart(config, directory, iface *C.char, network C.int) C.int {
	runtimeState.Lock()
	defer runtimeState.Unlock()
	if runtimeState.cancel != nil || config == nil || directory == nil || iface == nil {
		return 1
	}
	ctx, cancel := context.WithCancel(context.Background())
	runtimeState.cancel = cancel
	runtimeState.status = status{State: "starting"}
	go run(ctx, C.GoString(config), C.GoString(directory), C.GoString(iface), int32(network))
	return 0
}

func run(ctx context.Context, config, directory, iface string, network int32) {
	failure := ""
	defer func() {
		runtimeState.Lock()
		runtimeState.cancel()
		runtimeState.cancel = nil
		runtimeState.platform = nil
		runtimeState.status = status{State: "stopped", Error: failure}
		runtimeState.Unlock()
	}()
	if err := checkTunInbound(config); err != nil {
		failure = err.Error()
		return
	}
	platform, err := newPlatform(ctx, network, iface)
	if err != nil {
		failure = "无法读取系统的默认网络接口"
		return
	}
	temp := filepath.Join(directory, "cache")
	if err = os.MkdirAll(temp, 0o700); err != nil {
		failure = "无法创建内核缓存目录"
		return
	}
	if err = libbox.Setup(&libbox.SetupOptions{
		BasePath: directory, WorkingPath: directory, TempPath: temp,
		LogMaxLines: 64, CrashReportSource: "HarmonyOS",
	}); err != nil {
		failure = "无法初始化 sing-box 内核"
		return
	}
	if err = libbox.CheckConfig(config); err != nil {
		failure = "配置未通过 sing-box 校验"
		return
	}
	server, err := libbox.NewCommandServerWithContext(ctx, handler{}, platform)
	if err != nil {
		failure = "无法创建 sing-box 服务"
		return
	}
	defer server.Close()
	runtimeState.Lock()
	runtimeState.platform = platform
	runtimeState.Unlock()
	if err = server.StartOrReloadService(config, &libbox.OverrideOptions{}); err != nil {
		if ctx.Err() == nil {
			failure = "无法启动 sing-box，请检查 TUN、路由和出站配置"
		}
		return
	}
	defer server.CloseService()
	if !platform.opened.Load() {
		failure = "请在配置中启用一个 TUN 入站"
		return
	}
	runtimeState.Lock()
	if ctx.Err() == nil {
		runtimeState.status = status{State: "connected"}
	}
	runtimeState.Unlock()
	<-ctx.Done()
}

//export SBStatus
func SBStatus() *C.char {
	runtimeState.Lock()
	defer runtimeState.Unlock()
	if p := runtimeState.platform; p != nil && runtimeState.State == "starting" {
		select {
		case plan := <-p.requests:
			runtimeState.Tun = &plan
		default:
		}
	}
	if runtimeState.State == "" {
		runtimeState.State = "stopped"
	}
	result, _ := json.Marshal(runtimeState.status)
	return C.CString(string(result))
}

//export SBSetTunnel
func SBSetTunnel(fd C.int) C.int {
	runtimeState.Lock()
	defer runtimeState.Unlock()
	p := runtimeState.platform
	if p == nil || fd < 0 || runtimeState.State != "starting" || runtimeState.Tun == nil {
		return 1
	}
	p.tunName = tunName(runtimeState.Tun)
	select {
	case p.tunnel <- int32(fd):
		runtimeState.Tun = nil
		return 0
	case <-p.ctx.Done():
		return 1
	case <-time.After(time.Second):
		return 1
	}
}

//export SBStop
func SBStop() {
	runtimeState.Lock()
	defer runtimeState.Unlock()
	if runtimeState.cancel != nil {
		runtimeState.status = status{State: "stopping"}
		runtimeState.cancel()
	}
}

//export SBFree
func SBFree(value *C.char) { C.free(unsafe.Pointer(value)) }

type handler struct{}

func (handler) ServiceStop() error                                       { SBStop(); return nil }
func (handler) ServiceReload() error                                     { return unsupported }
func (handler) GetSystemProxyStatus() (*libbox.SystemProxyStatus, error) { return nil, unsupported }
func (handler) SetSystemProxyEnabled(bool) error                         { return unsupported }
func (handler) TriggerNativeCrash() error                                { return unsupported }
func (handler) WriteDebugMessage(string)                                 {}
func (handler) ConnectSSHAgent() (int32, error)                          { return -1, unsupported }

func main() {}
