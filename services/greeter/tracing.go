package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

// setupTracing は、トレースを OTLP (HTTP) で送るように設定し、終了の処理を返す。
// OTEL_EXPORTER_OTLP_ENDPOINT が空なら何も送らない (手元で `go run` するときに、送り先がなくても動くように)。
func setupTracing(ctx context.Context) (func(context.Context) error, error) {
	// 呼び出し元から来たトレースの文脈 (traceparent) を引き継ぐ。これがないと、呼び出し元とトレースがつながらない
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, propagation.Baggage{},
	))

	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") == "" {
		slog.Info("OTEL_EXPORTER_OTLP_ENDPOINT が空なので、トレースを送らない")
		return func(context.Context) error { return nil }, nil
	}

	// 送り先・ヘッダーなどは、OTEL_EXPORTER_OTLP_* の環境変数から読む (OTel の仕様の環境変数)
	exporter, err := otlptracehttp.New(ctx)
	if err != nil {
		return nil, fmt.Errorf("トレースの exporter を作れない: %w", err)
	}

	if os.Getenv("OTEL_SERVICE_NAME") == "" {
		// resource.Default() は OTEL_SERVICE_NAME を読む。未設定なら、このサービスの名前にする
		_ = os.Setenv("OTEL_SERVICE_NAME", "greeter")
	}
	res, err := resource.Merge(resource.Default(), resource.Environment())
	if err != nil {
		return nil, fmt.Errorf("resource を作れない: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	return tp.Shutdown, nil
}
