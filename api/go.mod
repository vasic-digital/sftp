module github.com/vasic-digital/sftp/api

go 1.26.2

replace digital.vasic.auth => ../auth

replace digital.vasic.cache => ../cache

replace digital.vasic.concurrency => ../concurrency

replace digital.vasic.config => ../config

replace digital.vasic.database => ../database

replace digital.vasic.discovery => ../discovery

replace digital.vasic.filesystem => ../filesystem

replace digital.vasic.formatters => ../formatters

replace digital.vasic.http3 => ../http3

replace digital.vasic.i18n => ../i18n

replace digital.vasic.mdns => ../mdns

replace digital.vasic.middleware => ../middleware

replace digital.vasic.observability => ../observability

replace digital.vasic.ratelimiter => ../ratelimiter

replace digital.vasic.recovery => ../recovery

replace digital.vasic.security => ../security

replace digital.vasic.storage => ../storage

replace digital.vasic.streaming => ../streaming

replace digital.vasic.watcher => ../watcher

require (
	digital.vasic.auth v0.0.0-00010101000000-000000000000
	digital.vasic.cache v0.0.0-00010101000000-000000000000
	digital.vasic.concurrency v0.0.0
	digital.vasic.config v0.0.0-00010101000000-000000000000
	digital.vasic.database v0.0.0-00010101000000-000000000000
	digital.vasic.discovery v0.0.0-00010101000000-000000000000
	digital.vasic.filesystem v0.0.0-00010101000000-000000000000
	digital.vasic.formatters v0.0.0-00010101000000-000000000000
	digital.vasic.http3 v0.0.0-00010101000000-000000000000
	digital.vasic.i18n v0.0.0-00010101000000-000000000000
	digital.vasic.mdns v0.0.0-00010101000000-000000000000
	digital.vasic.middleware v0.0.0-00010101000000-000000000000
	digital.vasic.observability v0.0.0-00010101000000-000000000000
	digital.vasic.ratelimiter v0.0.0-00010101000000-000000000000
	digital.vasic.recovery v0.0.0-00010101000000-000000000000
	digital.vasic.security v0.0.0-00010101000000-000000000000
	digital.vasic.storage v0.0.0-00010101000000-000000000000
	digital.vasic.streaming v0.0.0-00010101000000-000000000000
	digital.vasic.watcher v0.0.0-00010101000000-000000000000
	github.com/gin-gonic/gin v1.12.0
	github.com/golang-jwt/jwt/v5 v5.3.1
	github.com/jackc/pgx/v5 v5.10.0
	github.com/mattn/go-sqlite3 v1.14.47
	gopkg.in/yaml.v3 v3.0.1
)

require (
	github.com/bytedance/gopkg v0.1.3 // indirect
	github.com/bytedance/sonic v1.15.0 // indirect
	github.com/bytedance/sonic/loader v0.5.0 // indirect
	github.com/cenkalti/backoff v2.2.1+incompatible // indirect
	github.com/cloudwego/base64x v0.1.6 // indirect
	github.com/dustin/go-humanize v1.0.1 // indirect
	github.com/fsnotify/fsnotify v1.8.0 // indirect
	github.com/gabriel-vasile/mimetype v1.4.12 // indirect
	github.com/geoffgarside/ber v1.1.0 // indirect
	github.com/gin-contrib/sse v1.1.0 // indirect
	github.com/go-playground/locales v0.14.1 // indirect
	github.com/go-playground/universal-translator v0.18.1 // indirect
	github.com/go-playground/validator/v10 v10.30.1 // indirect
	github.com/goccy/go-json v0.10.5 // indirect
	github.com/goccy/go-yaml v1.19.2 // indirect
	github.com/google/uuid v1.6.0 // indirect
	github.com/gorilla/websocket v1.5.3 // indirect
	github.com/grandcat/zeroconf v1.0.0 // indirect
	github.com/hashicorp/errwrap v1.0.0 // indirect
	github.com/hashicorp/go-multierror v1.1.1 // indirect
	github.com/hirochachacha/go-smb2 v1.1.0 // indirect
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	github.com/jlaffaye/ftp v0.2.0 // indirect
	github.com/json-iterator/go v1.1.12 // indirect
	github.com/klauspost/cpuid/v2 v2.3.0 // indirect
	github.com/leodido/go-urn v1.4.0 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/miekg/dns v1.1.27 // indirect
	github.com/modern-go/concurrent v0.0.0-20180306012644-bacd9c7ef1dd // indirect
	github.com/modern-go/reflect2 v1.0.2 // indirect
	github.com/ncruces/go-strftime v0.1.9 // indirect
	github.com/pelletier/go-toml/v2 v2.2.4 // indirect
	github.com/quic-go/qpack v0.6.0 // indirect
	github.com/quic-go/quic-go v0.59.0 // indirect
	github.com/remyoudompheng/bigfft v0.0.0-20230129092748-24d4a6f8daec // indirect
	github.com/sirupsen/logrus v1.9.4 // indirect
	github.com/twitchyliquid64/golang-asm v0.15.1 // indirect
	github.com/ugorji/go/codec v1.3.1 // indirect
	go.mongodb.org/mongo-driver/v2 v2.5.0 // indirect
	golang.org/x/arch v0.22.0 // indirect
	golang.org/x/crypto v0.52.0 // indirect
	golang.org/x/exp v0.0.0-20250408133849-7e4ce0ab07d0 // indirect
	golang.org/x/net v0.54.0 // indirect
	golang.org/x/sys v0.45.0 // indirect
	golang.org/x/text v0.37.0 // indirect
	google.golang.org/protobuf v1.36.11 // indirect
	modernc.org/libc v1.65.7 // indirect
	modernc.org/mathutil v1.7.1 // indirect
	modernc.org/memory v1.11.0 // indirect
	modernc.org/sqlite v1.37.1 // indirect
)
