from __future__ import annotations

import os
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logger_handler import logger
from app.models.note import Note
from app.rag.vector_store import VectorStoreService


@dataclass
class SourceChunk:
    source_type: str
    source_id: str
    title: str
    content: str
    chunk_id: str | None = None
    score: float | None = None

    def citation(self) -> dict:
        quote = self.content.strip().replace("\n", " ")
        if len(quote) > 220:
            quote = quote[:220] + "..."
        return {
            "source_type": self.source_type,
            "source_id": self.source_id,
            "title": self.title,
            "chunk_id": self.chunk_id,
            "quote": quote,
            "score": self.score,
        }


class SourceCollector:
    """Collect note and knowledge snippets under the current user's boundary."""

    async def collect(
        self,
        db: AsyncSession,
        user_id: str,
        source_type: str,
        source_ids: list[str],
        max_chunks: int = 12,
    ) -> list[SourceChunk]:
        chunks: list[SourceChunk] = []
        normalized_ids = [sid for sid in source_ids if sid]

        if source_type in {"note", "mixed"}:
            chunks.extend(await self._collect_notes(db, user_id, normalized_ids))

        if source_type in {"knowledge", "mixed"}:
            chunks.extend(await self._collect_knowledge(user_id, normalized_ids, max_chunks=max_chunks))

        return chunks[:max_chunks]

    async def _collect_notes(self, db: AsyncSession, user_id: str, note_ids: list[str]) -> list[SourceChunk]:
        if not note_ids:
            return []
        result = await db.execute(select(Note).where(Note.user_id == user_id, Note.id.in_(note_ids)))
        notes = result.scalars().all()
        return [
            SourceChunk(
                source_type="note",
                source_id=note.id,
                title=note.title,
                content=note.content,
                chunk_id=note.id,
            )
            for note in notes
        ]

    async def _collect_knowledge(self, user_id: str, source_ids: list[str], max_chunks: int) -> list[SourceChunk]:
        try:
            vector_store = VectorStoreService()
            raw = await vector_store.knowledge_store.get(
                include=["documents", "metadatas"],
                where={"user_id": user_id},
            )
        except Exception as exc:
            logger.error(f"收集知识库来源失败 user_id={user_id}: {exc}")
            return []

        selected = set(source_ids)
        chunks: list[SourceChunk] = []
        for index, doc_id in enumerate(raw.get("ids", [])):
            metadata = raw.get("metadatas", [])[index] or {}
            content = raw.get("documents", [])[index] or ""
            source = metadata.get("source", metadata.get("filename", ""))
            source_name = os.path.basename(source) if isinstance(source, str) else str(source)
            original_filename = metadata.get("original_filename") or source_name
            md5 = metadata.get("md5")
            candidates = {doc_id, source_name, original_filename}
            if md5:
                candidates.add(md5)

            if selected and not (selected & candidates):
                continue

            chunks.append(
                SourceChunk(
                    source_type="knowledge",
                    source_id=str(md5 or original_filename or doc_id),
                    title=str(original_filename or source_name or "知识库文档"),
                    content=content,
                    chunk_id=str(doc_id),
                )
            )
            if len(chunks) >= max_chunks:
                break

        return chunks


def format_source_context(chunks: list[SourceChunk], max_chars: int = 8000) -> str:
    parts = []
    total = 0
    for idx, chunk in enumerate(chunks, 1):
        item = f"[{idx}] 来源:{chunk.source_type} 标题:{chunk.title}\n{chunk.content.strip()}\n"
        if total + len(item) > max_chars:
            break
        parts.append(item)
        total += len(item)
    return "\n".join(parts)
