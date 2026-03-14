"""
DeepTutor 后端入口 - FastAPI 应用骨架

功能说明（需实现）：
- 创建 FastAPI 应用实例，配置 CORS、中间件
- 挂载所有模块 router：knowledge, solver, question, research, notebook, guide, cowriter, ideagen, config
- 启动事件（lifespan/on_startup）：创建 data/user/、data/knowledge_bases/、data/outputs/ 等目录
- 静态文件路由：/outputs/{user_id}/{filename} 用于下载生成的报告、音频等
- 默认端口 8001，使用 Uvicorn 启动
"""
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.routers import (
    knowledge,
    solver,
    question,
    research,
    notebook,
    guide,
    cowriter,
    ideagen,
    config,
    outputs,
)

# 数据目录根路径（MVP 使用本地文件存储）
DATA_ROOT = Path(__file__).resolve().parent.parent / "data"


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用启动时创建必要目录，关闭时做清理（如有需要）。"""
    # 创建 data 下所有 MVP 需要的目录
    dirs = [
        DATA_ROOT / "user",
        DATA_ROOT / "user" / "sessions",
        DATA_ROOT / "user" / "notebooks",
        DATA_ROOT / "knowledge_bases",
        DATA_ROOT / "outputs",
    ]
    for d in dirs:
        d.mkdir(parents=True, exist_ok=True)
    yield
    # shutdown 可在此做资源释放


app = FastAPI(
    title="DeepTutor API",
    description="DeepTutor 后端 MVP 接口",
    version="0.1.0",
    lifespan=lifespan,
)

# CORS：允许前端跨域
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 挂载各模块路由（按文档优先级）
app.include_router(knowledge.router, prefix="/api/v1/knowledge", tags=["知识库管理"])
app.include_router(solver.router, prefix="/api/v1/solver", tags=["问题求解器"])
app.include_router(question.router, prefix="/api/v1/question", tags=["习题生成器"])
app.include_router(research.router, prefix="/api/v1/research", tags=["深度研究"])
app.include_router(notebook.router, prefix="/api/v1/notebook", tags=["笔记本管理"])
app.include_router(guide.router, prefix="/api/v1/guide", tags=["引导式学习"])
app.include_router(cowriter.router, prefix="/api/v1/cowriter", tags=["协同写作"])
app.include_router(ideagen.router, prefix="/api/v1/ideagen", tags=["自动创意生成"])
app.include_router(config.router, prefix="/api/v1/config", tags=["配置/状态"])
# GET /api/outputs/{user_id}/{filename} 下载生成的报告、音频等（MVP 必须）
app.include_router(outputs.router, prefix="/api/outputs", tags=["输出文件"])


@app.get("/health")
async def health():
    """健康检查，便于部署与前端探测。"""
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.main:app", host="0.0.0.0", port=8001, reload=True)
