"""
问题求解器 - 对话 + WebSocket 流式输出

需实现的接口：
- POST /api/v1/solver/chat：发起新对话或继续对话
  - 请求体：session_id（可选）、message、kb_id（可选，做 RAG）
  - 返回 session_id、task_id，供前端连接 WebSocket
- WebSocket ws://.../api/v1/solver/stream/{session_id}
  - 实时流式返回：type 为 thinking | citation | answer | done | error 的 JSON 消息
  - 实现打字机效果：delta 为增量文本；citation 为引用片段
"""
import json
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, HTTPException

from backend.models.schemas import SolverChatRequest, SolverChatResponse, WSMessage
from backend.services import session as session_svc
from backend.services import llm
from backend.services import rag

router = APIRouter()


@router.post(
    "/chat",
    response_model=SolverChatResponse,
    summary="发起/继续对话",
)
async def solver_chat(body: SolverChatRequest):
    """
    若未传 session_id 则新建会话；将 user message 写入会话；
    可选根据 kb_id 做 RAG 检索，再调用 LLM；
    返回 session_id 与 task_id，前端用 session_id 连 WebSocket 收流式结果。
    """
    # TODO: session_id = body.session_id or 生成新 ID
    # TODO: session_svc.append_message(session_id, "user", body.message)
    # TODO: 若 body.kb_id：rag.query(kb_id, body.message) 得到 context，拼进 prompt
    # TODO: 将“待回复”任务放入队列或标记，供 WebSocket 消费
    return SolverChatResponse(session_id="", task_id="")


@router.websocket("/stream/{session_id}")
async def solver_stream(websocket: WebSocket, session_id: str):
    """
    接受 WebSocket 连接后，根据 session_id 取最后一条 user message，
    流式调用 LLM（及 RAG），按 WSMessage 格式推送：
    - type=thinking：思考过程
    - type=citation：引用块
    - type=answer：delta 为增量内容
    - type=done：结束
    - type=error：错误信息
    """
    await websocket.accept()
    try:
        # TODO: session = session_svc.get_session(session_id)
        # TODO: async for chunk in llm.chat(..., stream=True): 组装 WSMessage，send_text(json.dumps(...))
        # TODO: 最后发送 type=done，并 session_svc.append_message(session_id, "assistant", full_content)
        await websocket.send_text(
            json.dumps({"type": "done", "content": ""})
        )
    except WebSocketDisconnect:
        pass
    except Exception as e:
        await websocket.send_text(
            json.dumps({"type": "error", "content": str(e)})
        )
    finally:
        await websocket.close()
