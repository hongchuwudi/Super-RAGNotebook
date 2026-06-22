"""pgvector-backed vector store

Revision ID: 20260621_0002
Revises: 20260618_0001
Create Date: 2026-06-21
"""

from __future__ import annotations

import os

from alembic import op


revision = "20260621_0002"
down_revision = "20260618_0001"
branch_labels = None
depends_on = None


def _embedding_dim() -> int:
    return int(os.getenv("EMBEDDING_DIM", "1024"))


def upgrade() -> None:
    embedding_dim = _embedding_dim()

    op.execute("CREATE EXTENSION IF NOT EXISTS vector")
    op.execute(
        f"""
        CREATE TABLE IF NOT EXISTS vector_chunks (
            id VARCHAR(64) PRIMARY KEY,
            store VARCHAR(32) NOT NULL,
            user_id VARCHAR(64) NOT NULL,
            document_id VARCHAR(128),
            content TEXT NOT NULL,
            metadata JSONB NOT NULL DEFAULT '{{}}'::jsonb,
            embedding vector({embedding_dim}) NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE INDEX IF NOT EXISTS ix_vector_chunks_store_user ON vector_chunks (store, user_id)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_vector_chunks_document ON vector_chunks (store, user_id, document_id)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_vector_chunks_metadata ON vector_chunks USING gin (metadata jsonb_path_ops)")
    op.execute(
        """
        CREATE INDEX IF NOT EXISTS ix_vector_chunks_embedding_hnsw
        ON vector_chunks USING hnsw (embedding vector_cosine_ops)
        """
    )

    op.execute(
        """
        CREATE TABLE IF NOT EXISTS knowledge_md5_records (
            user_id VARCHAR(64) NOT NULL,
            md5 VARCHAR(32) NOT NULL,
            filename TEXT,
            original_filename TEXT,
            upload_time TIMESTAMPTZ NOT NULL DEFAULT now(),
            PRIMARY KEY (user_id, md5)
        )
        """
    )
    op.execute("CREATE INDEX IF NOT EXISTS ix_knowledge_md5_user_filename ON knowledge_md5_records (user_id, filename)")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_knowledge_md5_user_filename")
    op.execute("DROP TABLE IF EXISTS knowledge_md5_records")
    op.execute("DROP INDEX IF EXISTS ix_vector_chunks_embedding_hnsw")
    op.execute("DROP INDEX IF EXISTS ix_vector_chunks_metadata")
    op.execute("DROP INDEX IF EXISTS ix_vector_chunks_document")
    op.execute("DROP INDEX IF EXISTS ix_vector_chunks_store_user")
    op.execute("DROP TABLE IF EXISTS vector_chunks")
