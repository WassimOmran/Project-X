"""
RAGFlowIndex — Kotaemon index backed by RAGFlow.

Wires together:
  - RAGFlowIndexer  (document upload & parsing via RAGFlow deepdoc)
  - RAGFlowRetriever (chunk retrieval via RAGFlow's Dify-compatible API)

Register this in flowsettings.py under KH_INDEX_TYPES and KH_INDICES to make
it appear as a selectable collection type in Kotaemon's UI.
"""

from __future__ import annotations

import logging
import os
from typing import Optional, Type

import requests

from ktem.index.base import BaseIndex

from .ragflow_indexer import RAGFlowIndexer
from .ragflow_retriever import RAGFlowRetriever

logger = logging.getLogger(__name__)

RAGFLOW_API_BASE = os.environ.get("RAGFLOW_API_BASE", "http://localhost:9380")
RAGFLOW_API_KEY = os.environ.get("RAGFLOW_API_KEY", "")


class RAGFlowIndex(BaseIndex):
    """
    A Kotaemon index backed entirely by RAGFlow.

    Documents are uploaded to RAGFlow which handles:
      - Intelligent PDF / DOCX / table parsing via deepdoc
      - Chunking with layout awareness
      - Embedding via your configured embedding model
      - Hybrid vector + keyword retrieval

    The Kotaemon UI provides:
      - Beautiful chat interface with inline citations
      - Multi-user support
      - LLM model selector
      - Citation source viewer
    """

    _indexing_pipeline_cls: Type[RAGFlowIndexer] = RAGFlowIndexer
    _retriever_pipeline_clss: list[Type[RAGFlowRetriever]] = [RAGFlowRetriever]

    def _setup_resources(self):
        """
        Create a new RAGFlow dataset for this index if one doesn't exist yet.
        The dataset ID is stored in self.config["ragflow_dataset_id"].
        """
        dataset_id = self.config.get("ragflow_dataset_id", "")
        if not dataset_id:
            dataset_id = self._create_ragflow_dataset(self.name)
            if dataset_id:
                self.config["ragflow_dataset_id"] = dataset_id
                logger.info(
                    f"Created RAGFlow dataset '{self.name}' → id={dataset_id}"
                )
            else:
                logger.error(
                    "Could not create RAGFlow dataset. "
                    "Check RAGFLOW_API_BASE and RAGFLOW_API_KEY in .env"
                )

        os.environ["RAGFLOW_DATASET_ID"] = dataset_id

    def _create_ragflow_dataset(self, name: str) -> str | None:
        """Create a new knowledge base in RAGFlow and return its ID."""
        url = f"{RAGFLOW_API_BASE}/api/v1/datasets"
        headers = {
            "Authorization": f"Bearer {RAGFLOW_API_KEY}",
            "Content-Type": "application/json",
        }
        payload = {
            "name": name,
            "chunk_method": "naive",
            "parser_config": {
                "chunk_token_count": 512,
                "layout_recognize": True,
                "html4excel": False,
            },
        }
        try:
            resp = requests.post(url, json=payload, headers=headers, timeout=15)
            resp.raise_for_status()
            data = resp.json()
            if data.get("code") == 0:
                return data["data"]["id"]
            logger.error(f"RAGFlow dataset creation error: {data}")
            return None
        except Exception as e:
            logger.error(f"Failed to create RAGFlow dataset: {e}")
            return None

    def get_indexing_pipeline(self, settings: dict, user_id: str) -> RAGFlowIndexer:
        dataset_id = self.config.get("ragflow_dataset_id", "")
        return RAGFlowIndexer(dataset_id=dataset_id)

    def get_retriever_pipelines(
        self, settings: dict, user_id: str, selected: Optional[list] = None
    ) -> list[RAGFlowRetriever]:
        dataset_id = self.config.get("ragflow_dataset_id", "")
        user_settings = settings.get(f"index.{self.id}.retriever", {})
        retriever = RAGFlowRetriever.get_pipeline(
            user_settings=user_settings,
            index_settings=self.config,
        )
        retriever.dataset_id = dataset_id
        return [retriever]

    @classmethod
    def get_admin_settings(cls) -> dict:
        return {
            "ragflow_dataset_id": {
                "name": "RAGFlow Dataset ID",
                "value": "",
                "component": "text",
                "info": (
                    "Leave blank to auto-create a new dataset in RAGFlow. "
                    "Or paste an existing dataset ID from RAGFlow UI."
                ),
            },
        }

    @classmethod
    def get_user_settings(cls) -> dict:
        return {}
