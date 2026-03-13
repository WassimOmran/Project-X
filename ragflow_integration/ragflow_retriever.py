"""
RAGFlow Retriever for Kotaemon
Sends queries to RAGFlow's /dify/retrieval endpoint and maps results
back to Kotaemon's RetrievedDocument format.
"""

from __future__ import annotations

import logging
import os
from typing import Optional

import requests

from kotaemon.base import Document, Param, RetrievedDocument
from ktem.index.file.base import BaseFileIndexRetriever

logger = logging.getLogger(__name__)

RAGFLOW_API_BASE = os.environ.get("RAGFLOW_API_BASE", "http://localhost:9380")
RAGFLOW_API_KEY = os.environ.get("RAGFLOW_API_KEY", "")
RAGFLOW_DATASET_ID = os.environ.get("RAGFLOW_DATASET_ID", "")


class RAGFlowRetriever(BaseFileIndexRetriever):
    """
    Retriever that calls RAGFlow's Dify-compatible retrieval API.

    RAGFlow handles:
    - Deep PDF/table/chart parsing
    - Chunking & re-ranking
    - Vector + keyword hybrid search

    Kotaemon handles:
    - Beautiful chat UI
    - Citation rendering
    - Multi-model LLM support
    """

    api_base: str = Param(
        default_callback=lambda _: RAGFLOW_API_BASE,
        help="RAGFlow API base URL (e.g. http://localhost:9380)",
    )
    api_key: str = Param(
        default_callback=lambda _: RAGFLOW_API_KEY,
        help="RAGFlow API key",
    )
    dataset_id: str = Param(
        default_callback=lambda _: RAGFLOW_DATASET_ID,
        help="RAGFlow knowledge base (dataset) ID to retrieve from",
    )
    top_k: int = Param(default=10, help="Number of chunks to retrieve")
    score_threshold: float = Param(
        default=0.0, help="Minimum similarity score (0.0 = return all)"
    )
    use_kg: bool = Param(
        default=False, help="Whether to also query the knowledge graph in RAGFlow"
    )

    def run(self, text: str, top_k: Optional[int] = None, **kwargs):
        """
        Retrieve relevant chunks from RAGFlow for the given query text.

        Args:
            text: the query string
            top_k: override default top_k if provided

        Returns:
            list[RetrievedDocument]
        """
        k = top_k or self.top_k
        if not self.dataset_id:
            logger.warning(
                "RAGFlowRetriever: RAGFLOW_DATASET_ID not set. "
                "Please configure it in .env or flowsettings.py"
            )
            return []

        url = f"{self.api_base}/dify/retrieval"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        payload = {
            "knowledge_id": self.dataset_id,
            "query": text,
            "use_kg": self.use_kg,
            "retrieval_setting": {
                "score_threshold": self.score_threshold,
                "top_k": k,
            },
        }

        try:
            resp = requests.post(url, json=payload, headers=headers, timeout=30)
            resp.raise_for_status()
            data = resp.json()
        except requests.RequestException as e:
            logger.error(f"RAGFlow retrieval request failed: {e}")
            return []

        records = data.get("records", [])
        results: list[RetrievedDocument] = []

        for rec in records:
            doc = RetrievedDocument(
                text=rec.get("content", ""),
                score=float(rec.get("score", 0.0)),
                metadata={
                    "source": rec.get("title", ""),
                    "doc_id": rec.get("metadata", {}).get("doc_id", ""),
                    **rec.get("metadata", {}),
                },
            )
            results.append(doc)

        logger.info(f"RAGFlow returned {len(results)} chunks for query: {text[:60]!r}")
        return results

    @classmethod
    def get_user_settings(cls) -> dict:
        return {
            "top_k": {
                "name": "Top-K chunks",
                "value": 10,
                "component": "number",
            },
            "score_threshold": {
                "name": "Score threshold",
                "value": 0.0,
                "component": "number",
            },
            "use_kg": {
                "name": "Use knowledge graph",
                "value": False,
                "component": "checkbox",
            },
        }

    @classmethod
    def get_pipeline(cls, user_settings, index_settings, selected=None):
        pipeline = cls(
            top_k=int(user_settings.get("top_k", 10)),
            score_threshold=float(user_settings.get("score_threshold", 0.0)),
            use_kg=bool(user_settings.get("use_kg", False)),
        )
        return pipeline
