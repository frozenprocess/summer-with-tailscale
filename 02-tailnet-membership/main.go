package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"

	"tailscale.com/tsnet"
)

func main() {
	hostname := getenv("TS_HOSTNAME", "hello-tsnet")
	stateDir := getenv("TS_STATE_DIR", "./state")
	authKey := getenv("TS_AUTHKEY", "")
	clientID := getenv("TS_CLIENT_ID", "")
	clientSecret := getenv("TS_CLIENT_SECRET", "")

	if authKey == "" && (clientID == "" || clientSecret == "") {
		log.Fatal("set TS_AUTHKEY, or both TS_CLIENT_ID and TS_CLIENT_SECRET")
	}

	srv := &tsnet.Server{
		Hostname:     hostname,
		Dir:          stateDir,
		AuthKey:      authKey,
		ClientID:     clientID,
		ClientSecret: clientSecret,
		Ephemeral:    false,
	}
	defer srv.Close()

	if _, err := srv.Up(context.Background()); err != nil {
		log.Fatalf("tsnet up: %v", err)
	}

	// srv.Listen("tcp", ":80") also works if you don't need TLS.
	ln, err := srv.ListenTLS("tcp", ":443")
	if err != nil {
		log.Fatalf("listen :443: %v", err)
	}
	defer ln.Close()

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "Hello from tsnet")
	})

	log.Printf("serving https://%s.<tailnet>.ts.net", hostname)
	log.Fatal(http.Serve(ln, nil))
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
