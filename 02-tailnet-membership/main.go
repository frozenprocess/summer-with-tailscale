package main

import (
	"context"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"

	"tailscale.com/tsnet"
)

func main() {
	hostname := getenv("TS_HOSTNAME", "ollama")
	stateDir := getenv("TS_STATE_DIR", "./state")
	backend := getenv("BACKEND_ADDR", "127.0.0.1:11434")
	authKey := getenv("TS_AUTHKEY", "")
	clientId := getenv("TS_CLIENT_ID", "")
	clientSecret := getenv("TS_CLIENT_SECRET", "")

	if authKey == "" && clientId == "" && clientSecret == "" {
		log.Fatal("Please provide an AuthKey or oAuth credentials")
	}

	srv := &tsnet.Server{
		Hostname:     hostname,
		AuthKey:      authKey,
		ClientID:     clientId,
		ClientSecret: clientSecret,
		Dir:          stateDir,
	}
	defer srv.Close()

	if _, err := srv.Up(context.Background()); err != nil {
		log.Fatalf("tsnet up: %v", err)
	}
	// reminder tls must be enabled
	tlsLn, err := srv.ListenTLS("tcp", ":443")
	if err != nil {
		log.Fatalf("listen :443: %v", err)
	}
	defer tlsLn.Close()

	target, err := url.Parse("http://" + backend)
	if err != nil {
		log.Fatalf("parse backend addr %q: %v", backend, err)
	}
	// Identity nudge here
	proxy := &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(target)
			r.SetXForwarded()
		},
	}

	log.Printf("proxying https://%s.<tailnet>.ts.net -> %s", hostname, backend)
	log.Fatal(http.Serve(tlsLn, proxy))
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
