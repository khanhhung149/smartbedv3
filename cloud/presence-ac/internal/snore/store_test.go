package snore

import (
	"context"
	"database/sql"
	"testing"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestAppendWithCanceledContextReturns(t *testing.T) {
	db, err := sql.Open("pgx", "postgres://invalid:invalid@127.0.0.1:1/invalid")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer db.Close()

	s := &Store{db: db}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	if err := s.Append(ctx, Event{}); err == nil {
		t.Fatal("Append với context đã huỷ phải trả lỗi")
	}
}

func TestAppendRejectsNilDB(t *testing.T) {
	if err := (*Store)(nil).Append(context.Background(), Event{}); err == nil {
		t.Fatal("Append trên store nil phải trả lỗi")
	}
	if _, err := Open(nil); err == nil {
		t.Fatal("Open(nil) phải trả lỗi")
	}
}
