"""
Pydantic 请求/响应模型 - 与接口文档一致的通用结构

功能说明（需实现）：
- 成功响应：success=True, data, session_id, task_id, citations, metadata(tokens_used, duration_ms)
- 错误响应：success=False, error, code, detail
- 知识库：上传参数、列表项、状态查询响应
- Solver：对话请求（session_id、message、kb_id 等）、WebSocket 消息格式（type: thinking|citation|answer|progress|done|error）
- 习题：生成请求（知识库/主题/难度）、提交答案请求、批改结果
- 深度研究：start 请求、stream 消息（percentage, stage）
- 笔记本：CRUD 请求/响应、add 请求
- 引导式学习：start 请求、stream 消息
- 协同写作：rewrite 参数（文本、操作类型）；TTS 请求/响应
- 创意生成：generate 请求
- 配置：LLM 配置 GET/POST 结构
"""
from typing import Any, Optional

from pydantic import BaseModel, Field


# ---------- 通用响应 ----------
class SuccessResponse(BaseModel):
    """成功响应：success=True, data, 可选 session_id/task_id/citations/metadata"""
    success: bool = True
    data: Optional[Any] = None
    session_id: Optional[str] = None
    task_id: Optional[str] = None
    citations: Optional[list] = None
    metadata: Optional[dict] = None  # tokens_used, duration_ms 等


class ErrorResponse(BaseModel):
    """错误响应"""
    success: bool = False
    error: str
    code: Optional[str] = None
    detail: Optional[str] = None


# ---------- WebSocket 消息格式 ----------
class WSMessage(BaseModel):
    """WebSocket 单条消息：type, content, delta, citation, percentage, stage"""
    type: str  # thinking | citation | answer | progress | done | error
    content: Optional[str] = None
    delta: Optional[str] = None
    citation: Optional[dict] = None
    percentage: Optional[float] = None
    stage: Optional[str] = None  # research | synthesis | writing


# ---------- 知识库 ----------
class KnowledgeUploadResponse(BaseModel):
    """上传后返回 kb_id、任务 id 等"""
    kb_id: str
    task_id: Optional[str] = None


class KnowledgeListItem(BaseModel):
    """知识库列表项"""
    kb_id: str
    name: str
    status: str  # processing | ready | failed
    created_at: Optional[str] = None


class KnowledgeStatusResponse(BaseModel):
    """GET knowledge/{kb_id}/status 响应"""
    kb_id: str
    status: str
    progress: Optional[float] = None
    chunks_count: Optional[int] = None


# ---------- Solver ----------
class SolverChatRequest(BaseModel):
    """POST solver/chat：发起/继续对话"""
    session_id: Optional[str] = None  # 无则新建
    message: str
    kb_id: Optional[str] = None  # 关联知识库做 RAG


class SolverChatResponse(BaseModel):
    """返回 session_id、task_id 供 WebSocket 连接"""
    session_id: str
    task_id: Optional[str] = None


# ---------- 习题 ----------
class QuestionGenerateRequest(BaseModel):
    """POST question/generate"""
    kb_id: Optional[str] = None
    topic: Optional[str] = None
    difficulty: Optional[str] = None
    count: int = 1


class QuestionSubmitRequest(BaseModel):
    """POST question/submit 提交答案"""
    question_id: str
    answer: str


# ---------- 深度研究 ----------
class ResearchStartRequest(BaseModel):
    """POST research/start"""
    topic: str


# ---------- 笔记本 ----------
class NotebookCreate(BaseModel):
    """创建笔记本"""
    title: str
    content: Optional[str] = None
    tags: Optional[list[str]] = None


class NotebookUpdate(BaseModel):
    """更新笔记本"""
    title: Optional[str] = None
    content: Optional[str] = None
    tags: Optional[list[str]] = None


class NotebookAddRequest(BaseModel):
    """POST notebook/{id}/add 从其他模块添加内容"""
    source: str  # solver | research | question 等
    content: str
    ref_id: Optional[str] = None


# ---------- 引导式学习 ----------
class GuideStartRequest(BaseModel):
    """POST guide/start：根据笔记本生成学习路径"""
    notebook_id: str


# ---------- 协同写作 ----------
class CowriterRewriteRequest(BaseModel):
    """POST cowriter/rewrite：改写/扩展/缩短/加注释"""
    text: str
    action: str  # rewrite | expand | shorten | annotate
    options: Optional[dict] = None


class CowriterTTSRequest(BaseModel):
    """POST cowriter/tts"""
    text: str
    voice: Optional[str] = None


# ---------- 创意生成 ----------
class IdeagenGenerateRequest(BaseModel):
    """POST ideagen/generate 从笔记本内容生成研究 idea"""
    notebook_id: str


# ---------- 配置 ----------
class LLMConfig(BaseModel):
    """GET/POST api/v1/config/llm"""
    provider: Optional[str] = None  # openai | azure | ...
    api_key: Optional[str] = None
    model: Optional[str] = None
    base_url: Optional[str] = None
