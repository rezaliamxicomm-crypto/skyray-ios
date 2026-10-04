package main

// The door to the subscription fetch with Encrypted Client Hello (echfetch/echfetch.go, compiled into this
// bridge as package main by scripts/build-libxray.sh). A JSON request in, a JSON result out; the result is
// freed with CGoFree, like CGoInvoke's. It does not touch libXray's managed Xray instance.

/*
#include <stdlib.h>
*/
import "C"

//export CGoFetchSubscriptionEch
func CGoFetchSubscriptionEch(requestJSON *C.char) *C.char {
	return C.CString(FetchSubscriptionEch(C.GoString(requestJSON)))
}
