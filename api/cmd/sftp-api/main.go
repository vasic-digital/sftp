// Package main is the bootstrap entrypoint for the SFTP Enterprise
// management API. The real wiring lands with STREAM-2 (ATM-002); this
// placeholder exists so `go mod tidy`/`go list`/`go build` resolve the full
// dependency set (owned submodules + third-party libs) from day one.
//
// Blank imports pin the packages WITHOUT inventing constructors — the real
// APIs are wired by STREAM-2 against the actual exported symbols (§11.4.6
// no-guessing: we do not fabricate signatures we have not verified).
package main

import (
	"fmt"

	_ "digital.vasic.auth/pkg/token"
	_ "digital.vasic.cache/pkg/memory"
	_ "digital.vasic.concurrency/pkg/retry"
	_ "digital.vasic.config/pkg/config"
	_ "digital.vasic.database/pkg/sqlite"
	_ "digital.vasic.discovery/pkg/scanner"
	_ "digital.vasic.filesystem/pkg/factory"
	_ "digital.vasic.formatters/pkg/formatter"
	_ "digital.vasic.http3/pkg/server"
	_ "digital.vasic.i18n/pkg/i18n"
	_ "digital.vasic.mdns/pkg/service"
	_ "digital.vasic.middleware/pkg/logging"
	_ "digital.vasic.observability/pkg/health"
	_ "digital.vasic.ratelimiter/pkg/tokenbucket"
	_ "digital.vasic.recovery/pkg/facade"
	_ "digital.vasic.security/pkg/ssrf"
	_ "digital.vasic.storage/pkg/local"
	_ "digital.vasic.streaming/pkg/websocket"
	_ "digital.vasic.watcher/pkg/watcher"

	_ "github.com/gin-gonic/gin"
	_ "github.com/golang-jwt/jwt/v5"
	_ "github.com/jackc/pgx/v5"
	_ "github.com/mattn/go-sqlite3"
	_ "gopkg.in/yaml.v3"
)

func main() {
	fmt.Println("sftp-api bootstrap placeholder — see ATM-002 (STREAM-2)")
}
