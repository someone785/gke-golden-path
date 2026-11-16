package main

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"unicode/utf8"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// maxNameLength は、名前として受け付ける最大の文字数。長すぎる入力でログやトレースが膨らむのを防ぐ
const maxNameLength = 64

type greeting struct {
	Message string `json:"message"`
}

type errorResponse struct {
	Error string `json:"error"`
}

// newHandler は、サービスのすべての経路を持つハンドラーを返す。
func newHandler() http.Handler {
	mux := http.NewServeMux()
	// API の経路は、経路ごとにトレースする。span の名前は経路のパターン (例: "GET /hello") で、
	// span_metrics の span_name になり、SLO の式で使う。
	// 【mux 全体を 1 つの otelhttp で包まない】span の名前を決めるのが経路の振り分けより前になり、
	// 実際の URL (例: "GET /存在しないパス") が名前になる。名前の種類が際限なく増え、span_metrics の系列が膨らむ
	route(mux, "GET /hello", handleHello)

	// 【ヘルスチェックはトレースしない】kubelet が数秒ごとに呼ぶので、トレースと span_metrics が埋もれる
	mux.HandleFunc("GET /healthz", handleHealthz)
	return mux
}

// route は、経路を登録し、その経路のパターンを名前にした span を作るようにする。
func route(mux *http.ServeMux, pattern string, h http.HandlerFunc) {
	mux.Handle(pattern, otelhttp.NewHandler(h, pattern))
}

func handleHello(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("name")
	if name == "" {
		name = "world"
	}
	if utf8.RuneCountInString(name) > maxNameLength {
		writeJSON(w, http.StatusBadRequest, errorResponse{
			Error: fmt.Sprintf("name は %d 文字以内にする", maxNameLength),
		})
		return
	}
	writeJSON(w, http.StatusOK, greeting{Message: fmt.Sprintf("Hello, %s!", name)})
}

func handleHealthz(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok\n"))
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("応答を書けなかった", "error", err)
	}
}
