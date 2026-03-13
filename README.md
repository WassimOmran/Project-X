# Project X — Most Powerful Open Source RAG Stack

**RAGFlow** (best document accuracy) + **Kotaemon** (best UI/UX) combined into one platform.

```
┌─────────────────────────────────────────────────┐
│              Kotaemon  :7860                     │
│   Beautiful chat UI · Citations · Multi-LLM      │
│         ↕  RAGFlow Integration Adapter           │
├─────────────────────────────────────────────────┤
│              RAGFlow  :9380                      │
│   deepdoc OCR · Table extraction · Chunking      │
│   Elasticsearch hybrid vector+keyword search     │
│   MySQL · MinIO · Redis                          │
└─────────────────────────────────────────────────┘
```

## Why this combination?

| Feature | RAGFlow | Kotaemon | This Stack |
|---|---|---|---|
| PDF/table/chart parsing | ✅ Best-in-class | Basic | ✅ RAGFlow |
| OCR for scanned docs | ✅ | ❌ | ✅ RAGFlow |
| Chat UI with citations | Basic | ✅ Beautiful | ✅ Kotaemon |
| Multi-LLM support | Limited | ✅ 20+ models | ✅ Kotaemon |
| Knowledge graph | ✅ | ✅ | ✅ Both |
| Hybrid search | ✅ | ✅ | ✅ RAGFlow |

## Quick Start

### Prerequisites
- Docker Desktop (4GB+ RAM allocated)
- ~20GB disk space

### 1. Configure
```bash
cp .env.example .env
# Edit .env — at minimum set one LLM API key
```

### 2. Launch
```bash
./setup.sh
```

### 3. Connect RAGFlow to Kotaemon
1. Open **RAGFlow** at [http://localhost:80](http://localhost:80)
   - Register an account
   - Go to **Settings → API Keys** → create a new key
   - Copy the key

2. Edit `.env` and set:
   ```
   RAGFLOW_API_KEY=ragflow-xxxxxxxxxxxxxxxxxxxxxxxx
   ```

3. Restart Kotaemon:
   ```bash
   docker compose restart kotaemon
   ```

4. Open **Kotaemon** at [http://localhost:7860](http://localhost:7860)
   - Login: `admin` / `admin`
   - Upload documents via **RAGFlow Collection**
   - Start chatting!

## Services

| Service | URL | Description |
|---|---|---|
| Kotaemon UI | http://localhost:7860 | Main chat interface |
| RAGFlow UI | http://localhost:80 | Document management |
| RAGFlow API | http://localhost:9380 | REST API |
| MinIO Console | http://localhost:9001 | Object storage UI |
| Elasticsearch | http://localhost:1200 | Vector DB |

## Architecture

```
User → Kotaemon UI (Gradio, port 7860)
           ↓
    RAGFlowRetriever
    (ragflow_integration/)
           ↓ POST /dify/retrieval
    RAGFlow API (port 9380)
           ↓
    Elasticsearch (hybrid vector+keyword)
    + deepdoc parsed chunks
```

### Integration Files

| File | Purpose |
|---|---|
| `kotaemon/ragflow_integration/ragflow_retriever.py` | Calls RAGFlow's retrieval API |
| `kotaemon/ragflow_integration/ragflow_indexer.py` | Uploads docs to RAGFlow |
| `kotaemon/ragflow_integration/ragflow_index.py` | Kotaemon index wrapper |
| `kotaemon/flowsettings.py` | Registers RAGFlowIndex in Kotaemon |

## Environment Variables

| Variable | Description |
|---|---|
| `RAGFLOW_API_KEY` | API key from RAGFlow Settings |
| `RAGFLOW_DATASET_ID` | (Optional) Specific dataset ID |
| `OPENAI_API_KEY` | OpenAI key for Kotaemon LLM |
| `ANTHROPIC_API_KEY` | Claude key for Kotaemon LLM |

## Commands

```bash
# Start
./setup.sh

# Stop (keeps data)
docker compose down

# Stop and wipe all data
./teardown.sh

# View logs
docker compose logs -f ragflow
docker compose logs -f kotaemon

# Restart after .env changes
docker compose restart kotaemon
```

## Supported File Types

`.pdf .docx .doc .xlsx .xls .pptx .png .jpg .jpeg .tiff .csv .html .txt .md .zip`

RAGFlow's deepdoc engine handles all of these with:
- Layout detection
- Table structure extraction  
- OCR for image-based content
- Formula recognition
