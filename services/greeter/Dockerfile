# greeter のイメージ。ビルドと実行を分け、実行するイメージには静的なバイナリ 1 つだけを入れる。
# 【ベースのイメージはタグではなく digest で固定する】タグは付け替えられるため (ADR 0005)。
# 末尾のコメントが元のタグ。版を上げるときは `docker buildx imagetools inspect <タグ>` で digest を調べ直す。

# 【Go の版は mise.toml の go とそろえる】
FROM golang:1.27.4-bookworm@sha256:4fa7c968ba93f1635670522dbb01a2c78150443e1385746924566079f36570ea AS build

WORKDIR /src
# 依存の取得を先に行い、ソースだけを変えたときは、この層をキャッシュから使えるようにする
COPY go.mod go.sum ./
RUN go mod download && go mod verify

COPY *.go ./
# CGO_ENABLED=0: C のライブラリに依存しない静的なバイナリにする (distroless/static で動かすため)
# -trimpath: バイナリに手元のパスを埋め込まない。同じソースから同じバイナリができやすくなる
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/greeter .

# 実行用: シェルもパッケージマネージャーもない。脆弱性の検査の対象と、侵入されたときにできることが減る
FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab

COPY --from=build /out/greeter /greeter
# nonroot (UID 65532) で動かす。Kyverno の方針 (フェーズ 3 のステップ 5) で root での実行を拒否するため
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/greeter"]
