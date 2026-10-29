package main

// SkyRay's Auto, the core side on iOS (compiled into libXray's C bridge as package main by scripts/build-libxray.sh,
// like echfetch_export.go). The extension's Xray holds every line of the subscription behind one balancer; the
// extension measures the lines itself, through a loopback inbound per line, and holds the balancer to the line it
// chooses with this call — Xray's own `api bo` over the configuration's API inbound, since libXray keeps its managed
// instance to itself. A JSON request in, a JSON result out; the result is freed with CGoFree, like CGoInvoke's.
//
//	{"api": "127.0.0.1:41285", "balancer": "auto", "target": "line-<id>"}   → {"ok": true}
//	an empty target gives the balancer back to its strategy                  → {"ok": false, "error": "…"} on failure
//	{"api": "…", "balancer": "auto"} with "query": true                      → {"ok": true, "target": "<the line held to>"}

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/xtls/xray-core/app/router/command"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

type balancerRequest struct {
	API      string `json:"api"`
	Balancer string `json:"balancer"`
	Target   string `json:"target"`
	Query    bool   `json:"query"`
}

type balancerResult struct {
	OK     bool   `json:"ok"`
	Target string `json:"target,omitempty"`
	Error  string `json:"error,omitempty"`
}

//export CGoBalancerOverride
func CGoBalancerOverride(requestJSON *C.char) *C.char {
	return C.CString(BalancerOverride(C.GoString(requestJSON)))
}

// BalancerOverride is CGoBalancerOverride without the C strings (tests, and any Go caller).
func BalancerOverride(requestJSON string) string {
	var req balancerRequest
	if err := json.Unmarshal([]byte(requestJSON), &req); err != nil {
		return balancerFailed("request: " + err.Error())
	}
	target, err := balancerCall(req)
	if err != nil {
		return balancerFailed(err.Error())
	}
	out, _ := json.Marshal(balancerResult{OK: true, Target: target})
	return string(out)
}

func balancerFailed(msg string) string {
	out, _ := json.Marshal(balancerResult{OK: false, Error: msg})
	return string(out)
}

func balancerCall(req balancerRequest) (string, error) {
	if req.API == "" || req.Balancer == "" {
		return "", errors.New("api and balancer are required")
	}
	conn, err := grpc.NewClient(req.API, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return "", err
	}
	defer conn.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	client := command.NewRoutingServiceClient(conn)
	if req.Query {
		info, err := client.GetBalancerInfo(ctx, &command.GetBalancerInfoRequest{Tag: req.Balancer})
		if err != nil {
			return "", err
		}
		if b := info.GetBalancer(); b != nil && b.GetOverride() != nil {
			return b.GetOverride().GetTarget(), nil
		}
		return "", nil
	}
	if _, err := client.OverrideBalancerTarget(ctx, &command.OverrideBalancerTargetRequest{BalancerTag: req.Balancer, Target: req.Target}); err != nil {
		return "", err
	}
	return req.Target, nil
}
