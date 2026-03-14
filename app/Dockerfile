FROM golang:1.22-alpine AS builder
RUN apk add --no-cache git ca-certificates
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w -X main.version=0.1.0 -X main.buildTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -o /build/sample-api ./main.go

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /build/sample-api /usr/local/bin/sample-api
USER 1000:1000
EXPOSE 8080 9090
ENTRYPOINT ["sample-api"]
