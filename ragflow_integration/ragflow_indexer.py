"""
RAGFlow Indexer for Kotaemon
Uploads documents to RAGFlow knowledge base via its HTTP API.
RAGFlow handles all the heavy lifting:
  - OCR for scanned PDFs
  - Table / chart extraction
  - Intelligent chunking
  - Embedding & vector storage
"""

from __future__ import annotations

import logging
import os
import time
from pathlib import Path
from typing import Generator

import requests

from kotaemon.base import Document, Param
from ktem.index.file.base import BaseFileIndexIndexing

logger = logging.getLogger(__name__)

RAGFLOW_API_BASE = os.environ.get("RAGFLOW_API_BASE", "http://localhost:9380")
RAGFLOW_API_KEY = os.environ.get("RAGFLOW_API_KEY", "")
RAGFLOW_DATASET_ID = os.environ.get("RAGFLOW_DATASET_ID", "")


class RAGFlowIndexer(BaseFileIndexIndexing):
    """
    Indexing pipeline that delegates document processing to RAGFlow.

    RAGFlow's deepdoc engine handles:
      - Automatic layout detection
      - OCR for image/scan-based PDFs
      - Table extraction with structure preservation
      - Intelligent chunk boundaries
    """

    api_base: str = Param(
        default_callback=lambda _: RAGFLOW_API_BASE,
        help="RAGFlow API base URL",
    )
    api_key: str = Param(
        default_callback=lambda _: RAGFLOW_API_KEY,
        help="RAGFlow API key",
    )
    dataset_id: str = Param(
        default_callback=lambda _: RAGFLOW_DATASET_ID,
        help="RAGFlow dataset (knowledge base) ID",
    )
    wait_for_parsing: bool = Param(
        default=True,
        help="Wait for RAGFlow to finish parsing before returning",
    )
    parse_poll_interval: int = Param(
        default=5,
        help="Seconds between parse status polls",
    )

    @property
    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self.api_key}",
        }

    def _upload_document(self, file_path: Path) -> str | None:
        """Upload a single file to RAGFlow and return its document ID."""
        url = f"{self.api_base}/api/v1/datasets/{self.dataset_id}/documents"
        try:
            with open(file_path, "rb") as f:
                resp = requests.post(
                    url,
                    headers=self._headers,
                    files={"file": (file_path.name, f)},
                    timeout=120,
                )
            resp.raise_for_status()
            data = resp.json()
            if data.get("code") == 0 and data.get("data"):
                doc_id = data["data"][0].get("id")
                logger.info(f"Uploaded {file_path.name} → RAGFlow doc_id={doc_id}")
                return doc_id
            else:
                logger.error(f"RAGFlow upload error for {file_path.name}: {data}")
                return None
        except Exception as e:
            logger.error(f"Failed to upload {file_path.name}: {e}")
            return None

    def _start_parsing(self, doc_id: str) -> bool:
        """Trigger parsing for a document in RAGFlow."""
        url = f"{self.api_base}/api/v1/datasets/{self.dataset_id}/chunks"
        try:
            resp = requests.post(
                url,
                headers={**self._headers, "Content-Type": "application/json"},
                json={"document_ids": [doc_id]},
                timeout=30,
            )
            resp.raise_for_status()
            return resp.json().get("code") == 0
        except Exception as e:
            logger.error(f"Failed to start parsing doc {doc_id}: {e}")
            return False

    def _wait_until_parsed(self, doc_id: str, timeout: int = 300) -> bool:
        """Poll until RAGFlow finishes parsing the document."""
        url = f"{self.api_base}/api/v1/datasets/{self.dataset_id}/documents"
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                resp = requests.get(
                    url,
                    headers=self._headers,
                    params={"id": doc_id},
                    timeout=15,
                )
                resp.raise_for_status()
                data = resp.json()
                docs = data.get("data", {}).get("docs", [])
                if docs:
                    status = docs[0].get("run", "")
                    if status == "DONE":
                        return True
                    elif status == "FAIL":
                        logger.error(f"RAGFlow parsing failed for doc {doc_id}")
                        return False
            except Exception as e:
                logger.warning(f"Status poll error: {e}")
            time.sleep(self.parse_poll_interval)
        logger.warning(f"Timeout waiting for doc {doc_id} to parse")
        return False

    def run(
        self, file_paths: str | Path | list[str | Path], *args, **kwargs
    ) -> tuple[list[str | None], list[str | None]]:
        if isinstance(file_paths, (str, Path)):
            file_paths = [file_paths]

        doc_ids: list[str | None] = []
        errors: list[str | None] = []

        for fp in file_paths:
            path = Path(fp)
            doc_id = self._upload_document(path)
            if doc_id is None:
                doc_ids.append(None)
                errors.append(f"Upload failed for {path.name}")
                continue

            if not self._start_parsing(doc_id):
                doc_ids.append(None)
                errors.append(f"Failed to trigger parsing for {path.name}")
                continue

            if self.wait_for_parsing:
                success = self._wait_until_parsed(doc_id)
                if not success:
                    doc_ids.append(None)
                    errors.append(f"Parsing did not complete for {path.name}")
                    continue

            doc_ids.append(doc_id)
            errors.append(None)

        return doc_ids, errors

    def stream(
        self, file_paths: str | Path | list[str | Path], *args, **kwargs
    ) -> Generator[Document, None, tuple[list, list, list]]:
        if isinstance(file_paths, (str, Path)):
            file_paths = [file_paths]

        doc_ids: list[str | None] = []
        errors: list[str | None] = []

        for fp in file_paths:
            path = Path(fp)
            yield Document(text=f"Uploading {path.name} to RAGFlow...")

            doc_id = self._upload_document(path)
            if doc_id is None:
                doc_ids.append(None)
                errors.append(f"Upload failed for {path.name}")
                yield Document(text=f"❌ Upload failed for {path.name}")
                continue

            yield Document(text=f"⚙️ RAGFlow is parsing {path.name} (OCR + layout detection)...")
            if not self._start_parsing(doc_id):
                doc_ids.append(None)
                errors.append(f"Parse trigger failed for {path.name}")
                continue

            success = self._wait_until_parsed(doc_id)
            if success:
                doc_ids.append(doc_id)
                errors.append(None)
                yield Document(text=f"✅ {path.name} indexed successfully by RAGFlow.")
            else:
                doc_ids.append(None)
                errors.append(f"Parsing timeout for {path.name}")
                yield Document(text=f"⚠️ Parsing timeout for {path.name}. It may still complete in RAGFlow.")

        return doc_ids, errors, []

    @classmethod
    def get_pipeline(cls, user_settings, index_settings):
        return cls()
