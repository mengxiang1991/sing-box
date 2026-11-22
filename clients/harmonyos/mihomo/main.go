package main

import "C"

//export MBCheckProfile
func MBCheckProfile(config *C.char) C.int {
	if config == nil || !checkProfile(C.GoString(config)) {
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
