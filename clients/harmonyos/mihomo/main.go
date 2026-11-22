package main

import "C"

import (
	"os"
	"path/filepath"

	"github.com/metacubex/mihomo/constant"
)

//export MBCheckProfile
func MBCheckProfile(config, directory *C.char) C.int {
	if config == nil || directory == nil {
		return 1
	}
	path := filepath.Join(C.GoString(directory), "mihomo")
	if err := os.MkdirAll(path, 0o700); err != nil {
		return 1
	}
	constant.SetHomeDir(path)
	if !checkProfile(C.GoString(config)) {
		return 1
	}
	return 0
}

//export MBReadRules
func MBReadRules(config *C.char) *C.char {
	return C.CString(readRules(C.GoString(config)))
}

//export MBReplaceRules
func MBReplaceRules(config, rules *C.char) *C.char {
	return C.CString(replaceRules(C.GoString(config), C.GoString(rules)))
}

func main() {}
