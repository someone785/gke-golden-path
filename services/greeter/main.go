// greeter は、ゴールデンパスの見本になる小さな HTTP の API。
// 挨拶を JSON で返すだけだが、本番で動かすサービスに要るもの (ヘルスチェック、トレース、終了の処理) をそろえる。
//
// 環境変数:
//
//	PORT                         待ち受けるポート (既定 8080)
//	OTEL_EXPORTER_OTLP_ENDPOINT  トレースの送り先 (例: http://otel-collector:4318)。空ならトレースを送らない
//	OTEL_SERVICE_NAME            トレースに付けるサービス名 (既定 greeter)
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	if err := run(); err != nil {
		slog.Error("終了する", "error", err)
		os.Exit(1)
	}
}

func run() error {
	// SIGTERM は、Kubernetes が Pod を止めるときに送る。受け取ったら新しい接続を断り、処理中のものを終えてから止まる
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	shutdownTracing, err := setupTracing(ctx)
	if err != nil {
		return err
	}
	defer func() {
		// 【終了の前に、溜まっているトレースを送り切る】送り切らないと、最後の数件のトレースが消える
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTracing(ctx); err != nil {
			slog.Error("トレースの送信を終えられなかった", "error", err)
		}
	}()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	srv := &http.Server{
		Addr:    ":" + port,
		Handler: newHandler(),
		// 【タイムアウトを付ける】既定は無制限で、遅いクライアントに接続を握られ続ける
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		slog.Info("待ち受けを始める", "port", port)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
		close(errCh)
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
	}

	slog.Info("終了の合図を受け取った。処理中のリクエストを終えてから止まる")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return srv.Shutdown(ctx)
}
