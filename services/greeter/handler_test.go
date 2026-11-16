package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"go.opentelemetry.io/otel"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
)

func TestHello(t *testing.T) {
	tests := []struct {
		name       string
		query      string
		wantStatus int
		wantBody   string
	}{
		{name: "名前なしなら world", query: "", wantStatus: http.StatusOK, wantBody: "Hello, world!"},
		{name: "名前あり", query: "?name=Gopher", wantStatus: http.StatusOK, wantBody: "Hello, Gopher!"},
		{name: "日本語の名前", query: "?name=%E3%81%B2%E3%81%A8", wantStatus: http.StatusOK, wantBody: "Hello, ひと!"},
		{name: "64 文字までは受け付ける", query: "?name=" + strings.Repeat("a", 64), wantStatus: http.StatusOK, wantBody: "Hello, " + strings.Repeat("a", 64) + "!"},
		{name: "65 文字は断る", query: "?name=" + strings.Repeat("a", 65), wantStatus: http.StatusBadRequest},
	}

	h := newHandler()
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/hello"+tt.query, nil))

			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d (body: %s)", rec.Code, tt.wantStatus, rec.Body.String())
			}
			if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
				t.Errorf("Content-Type = %q, want application/json", ct)
			}
			if tt.wantBody == "" {
				return
			}
			var got greeting
			if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
				t.Fatalf("JSON を読めない: %v", err)
			}
			if got.Message != tt.wantBody {
				t.Errorf("message = %q, want %q", got.Message, tt.wantBody)
			}
		})
	}
}

func TestHelloRejectsOtherMethods(t *testing.T) {
	rec := httptest.NewRecorder()
	newHandler().ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/hello", nil))
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusMethodNotAllowed)
	}
}

func TestHealthz(t *testing.T) {
	rec := httptest.NewRecorder()
	newHandler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if body := rec.Body.String(); body != "ok\n" {
		t.Errorf("body = %q, want %q", body, "ok\n")
	}
}

func TestUnknownPath(t *testing.T) {
	rec := httptest.NewRecorder()
	newHandler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/nope", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
}

// span の名前が経路のパターンになり、ヘルスチェックと存在しないパスはトレースされないことを確かめる。
// span_metrics の系列を増やしすぎないため (handler.go の route のコメント)
func TestSpanNames(t *testing.T) {
	sr := tracetest.NewSpanRecorder()
	tp := sdktrace.NewTracerProvider(sdktrace.WithSpanProcessor(sr))
	prev := otel.GetTracerProvider()
	otel.SetTracerProvider(tp)
	t.Cleanup(func() { otel.SetTracerProvider(prev) })

	h := newHandler()
	for _, path := range []string{"/hello?name=a", "/hello?name=b", "/healthz", "/nope", "/hello/extra"} {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, path, nil))
	}

	var names []string
	for _, s := range sr.Ended() {
		names = append(names, s.Name())
	}
	want := []string{"GET /hello", "GET /hello"}
	if strings.Join(names, ",") != strings.Join(want, ",") {
		t.Fatalf("span names = %q, want %q", names, want)
	}
}
