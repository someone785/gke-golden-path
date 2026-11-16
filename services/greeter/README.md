# greeter

ゴールデンパスの見本になる、小さな HTTP の API (Go)。フェーズ 3 で、これをもとにテンプレート (`templates/service-go/`) を作る。

| 経路 | 内容 | トレース |
|---|---|---|
| `GET /hello?name=<名前>` | `{"message":"Hello, <名前>!"}` を返す。名前は 64 文字まで (超えると 400) | する (span の名前は `GET /hello`) |
| `GET /healthz` | `ok` を返す (Kubernetes のヘルスチェック用) | しない |

## 手元で動かす
```bash
go test -race ./...
go run .                      # http://localhost:8080/hello?name=Gopher
docker build -t greeter:dev .
docker run --rm -p 8080:8080 greeter:dev
```

## 環境変数
| 名前 | 既定 | 内容 |
|---|---|---|
| `PORT` | `8080` | 待ち受けるポート |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | (空) | トレースの送り先 (OTLP/HTTP、例: `http://otel-collector:4318`)。空ならトレースを送らない |
| `OTEL_SERVICE_NAME` | `greeter` | トレースに付けるサービス名 |

## 作りの理由
- **span の名前は経路のパターンにする**: span_metrics の `span_name` になり、SLO の式で使う。実際の URL を名前にすると、名前の種類が際限なく増える (`handler.go` の `route`、テストの `TestSpanNames`)
- **ヘルスチェックはトレースしない**: 数秒ごとに呼ばれ、トレースと span_metrics が埋もれる
- **SIGTERM で、処理中のリクエストを終えてから止まる**: Pod を止めるときに、リクエストを途中で切らない。止まる前に、溜まっているトレースも送り切る
- **実行用のイメージは distroless/static (nonroot)**: シェルもパッケージマネージャーもなく、root で動かない。ベースのイメージは digest で固定する (ADR 0005)

## 未確認
- トレースが OTel Demo の OTel Collector に届き、span_metrics に `service_name="greeter"` が出るか (クラスタで確かめる)
