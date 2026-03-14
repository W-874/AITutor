"""
习题生成器 - 生成题目、提交答案与批改

需实现的接口：
- POST /api/v1/question/generate：根据知识库/主题/难度生成题目
  - 请求体：kb_id、topic、difficulty、count
  - 返回题目列表（含 question_id、题干、选项/开放题、答案要点等），可选用 LLM 流式生成
- POST /api/v1/question/submit：提交答案 → 批改 + 解析
  - 请求体：question_id、answer
  - 返回批改结果（对错、得分、解析、citations）
"""
from fastapi import APIRouter, HTTPException

from backend.models.schemas import (
    SuccessResponse,
    ErrorResponse,
    QuestionGenerateRequest,
    QuestionSubmitRequest,
)
from backend.services import llm
from backend.services import rag

router = APIRouter()


@router.post(
    "/generate",
    response_model=SuccessResponse,
    summary="根据知识库/主题/难度生成题目",
)
async def question_generate(body: QuestionGenerateRequest):
    """
    可选从 kb_id 检索相关上下文，结合 topic、difficulty 调用 LLM 生成 count 道题；
    题目持久化到 data/user/ 或会话，返回 question_id 列表与题目内容。
    """
    # TODO: 若 body.kb_id：rag.query 取 context
    # TODO: prompt = f"根据以下内容/主题 {body.topic}，难度 {body.difficulty}，生成 {body.count} 道题..."
    # TODO: questions = llm.chat(...)；解析为结构化题目列表并存储
    return SuccessResponse(data={"questions": []})


@router.post(
    "/submit",
    response_model=SuccessResponse,
    summary="提交答案并批改",
)
async def question_submit(body: QuestionSubmitRequest):
    """
    根据 question_id 取原题与参考答案，用 LLM 批改用户 answer，返回对错、得分、解析、citations。
    """
    # TODO: 取题目与标准答案/要点
    # TODO: llm.chat([...], "请批改以下答案并给出解析") → 解析 JSON 或文本
    return SuccessResponse(
        data={
            "correct": False,
            "score": 0,
            "feedback": "",
            "citations": [],
        }
    )
