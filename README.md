# DeepTutor 后端 MVP

基于 FastAPI 的 DeepTutor 后端，端口默认 **8001**，前端通过 REST + WebSocket 对接。

- **RAG**：Silicon Flow BGE embedding + Chroma 向量库本地持久化 + BM25 检索，混合 RRF 融合。
- **GraphRAG**：独立模块，从 chunk 建实体关系图并持久化，支持基于图的查询与摘要。
- **配置**：`backend/config/app_config.yaml` 统一配置 LLM、Embedding、RAG、GraphRAG；可通过 API 写入 `data/user/config.json` 覆盖。

## 项目结构

```
AITutor/
├── backend/
│   ├── main.py              # FastAPI 入口，挂载路由，启动时创建 data 目录
│   ├── config/
│   │   ├── settings.py      # 统一配置加载（YAML + runtime JSON + 环境变量）
│   │   └── app_config.yaml  # LLM / Embedding / RAG / GraphRAG 配置
│   ├── models/
│   │   └── schemas.py       # Pydantic 请求/响应模型
│   ├── routers/
│   │   ├── knowledge.py     # 知识库：上传 → 切块 → BGE+Chroma+BM25 持久化
│   │   ├── solver.py        # 问题求解：chat + WebSocket stream
│   │   ├── question.py      # 习题生成与批改
│   │   ├── research.py      # 深度研究：start + WebSocket stream
│   │   ├── notebook.py      # 笔记本 CRUD + 添加内容
│   │   ├── guide.py         # 引导式学习
│   │   ├── cowriter.py      # 协同写作（改写、TTS）
│   │   ├── ideagen.py       # 创意生成
│   │   ├── config.py        # GET/POST LLM、Embedding 配置
│   │   └── outputs.py      # 输出文件下载 /api/outputs/{user_id}/{filename}
│   ├── services/
│   │   ├── llm.py           # 统一 LLM 调用（从 config 读配置）
│   │   ├── embedding.py     # Silicon Flow BGE Embedding API
│   │   ├── rag.py           # RAG：切块、BGE、Chroma 持久化、BM25、RRF 混合检索
│   │   └── session.py       # 会话状态（内存 + JSON 持久化）
│   └── graph_rag/           # GraphRAG 独立模块
│       ├── graph_builder.py # 从 chunk 用 LLM 抽取实体/关系，建图
│       ├── graph_store.py   # 图持久化 data/graph_rag/{kb_id}/graph.json
│       └── query.py         # 子图检索 + LLM 摘要
├── data/                    # 运行时生成
│   ├── user/                # config.json（运行时配置）、sessions/、notebooks/
│   ├── knowledge_bases/     # 每 kb_id：chroma/、chunks_meta.json、bm25_index.pkl
│   ├── graph_rag/           # 每 kb_id：graph.json
│   └── outputs/
├── requirements.txt
└── README.md
```

## 运行

```bash
# 安装依赖
pip install -r requirements.txt

# 启动（从项目根 AITutor 执行）
uvicorn backend.main:app --host 0.0.0.0 --port 8001 --reload
# 或
python -m backend.main
```

打开 **http://localhost:8001/docs** 查看 Swagger 文档。

## 配置

- 编辑 **`backend/config/app_config.yaml`** 填写 `embedding.api_key`（Silicon Flow）、`llm.api_key` 等；也可用环境变量 `EMBEDDING_API_KEY`、`LLM_API_KEY`、`LLM_MODEL` 等覆盖。
- 通过 **GET/POST `/api/v1/config/llm`**、**GET/POST `/api/v1/config/embedding`** 可查看/修改配置，POST 会写入 `data/user/config.json` 并生效。

## RAG 与 GraphRAG

- **知识库上传**：PDF/TXT/MD → 切块 → Silicon Flow BGE embedding → Chroma 持久化；同时建 BM25 索引并 pickle 到 `data/knowledge_bases/{kb_id}/`。
- **检索**：向量 top-k + BM25 top-k，RRF 融合后返回混合结果。
- **GraphRAG**：知识库就绪后可选建图（实体/关系抽取 → `data/graph_rag/{kb_id}/graph.json`）；查询时取相关子图再 LLM 摘要。见 `backend/graph_rag/`。

## MVP 实现顺序建议

1. 知识库上传 + 列表（可先不做 embedding）
2. Solver 简单问答（无 RAG）→ 再加 RAG
3. WebSocket 流式输出（打字机效果）
4. 笔记本 CRUD + “添加到笔记本”
5. 习题生成 + 批改
6. 深度研究（可后置）

优先跑通：`/api/v1/solver/chat` + WebSocket streaming + 知识库上传，即可覆盖大部分核心体验。
