import streamlit as st
import requests
from typing import Dict, Any, List, Optional
import time
import json

# ==========================================
# 页面配置与自定义样式
# ==========================================
st.set_page_config(
    page_title="AI辅助教学系统",
    page_icon="📚",
    layout="wide",
    initial_sidebar_state="collapsed"
)

st.markdown("""
<style>
    [data-testid="collapsedControl"] { display: none; }
    .stApp { background-color: #f4f6f8; }
    .block-container { padding-top: 1rem; padding-bottom: 0; max-width: 98%; }
    
    [data-testid="column"] {
        background-color: #ffffff;
        border-radius: 12px;
        padding: 1rem;
        box-shadow: 0 4px 6px rgba(0,0,0,0.05);
        height: calc(100vh - 80px);
        overflow-y: auto;
    }
    [data-testid="column"]::-webkit-scrollbar { display: none; }
    [data-testid="column"] { -ms-overflow-style: none; scrollbar-width: none; }
    
    .doc-card {
        border: 1px solid #e0e0e0;
        border-radius: 8px;
        padding: 0.75rem;
        margin-bottom: 0.5rem;
        background-color: #fafafa;
        transition: all 0.2s ease;
    }
    .doc-card:hover {
        border-color: #2196F3;
        background-color: #f5f5f5;
    }
    .doc-card.selected {
        border-color: #2196F3;
        background-color: #e3f2fd;
    }
    .status-badge {
        display: inline-block;
        padding: 2px 8px;
        border-radius: 12px;
        font-size: 0.75rem;
        font-weight: 500;
    }
    .status-processed { background-color: #c8e6c9; color: #2e7d32; }
    .status-processing { background-color: #fff3e0; color: #ef6c00; }
    .status-pending { background-color: #e3f2fd; color: #1565c0; }
    .status-failed { background-color: #ffebee; color: #c62828; }
    .status-preprocessed { background-color: #f3e5f5; color: #7b1fa2; }
    
    .chat-container {
        display: flex;
        flex-direction: column;
        height: calc(100vh - 200px);
    }
    .chat-messages {
        flex: 1;
        overflow-y: auto;
        padding-bottom: 80px;
    }
    .chat-input-container {
        position: sticky;
        bottom: 0;
        background: white;
        padding-top: 10px;
    }
    
    .streaming-text {
        white-space: pre-wrap;
        word-wrap: break-word;
    }
</style>
""", unsafe_allow_html=True)

# ==========================================
# 全局变量与 API 函数
# ==========================================
BASE_URL = "http://localhost:8000"

def api_get(endpoint: str, params: Dict[str, Any] = None):
    try:
        response = requests.get(f"{BASE_URL}{endpoint}", params=params, timeout=300)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        st.error(f"请求失败: {str(e)}")
        return None

def api_post(endpoint: str, data: Dict[str, Any] = None, files: Dict[str, Any] = None):
    try:
        if files:
            response = requests.post(f"{BASE_URL}{endpoint}", files=files, timeout=300)
        else:
            response = requests.post(f"{BASE_URL}{endpoint}", json=data, timeout=300)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        st.error(f"请求失败: {str(e)}")
        return None

def api_delete(endpoint: str):
    try:
        response = requests.delete(f"{BASE_URL}{endpoint}", timeout=300)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        st.error(f"请求失败: {str(e)}")
        return None

# 初始化 Session State
if "center_mode" not in st.session_state:
    st.session_state.center_mode = "home"
if "current_learning_content" not in st.session_state:
    st.session_state.current_learning_content = ""
if "current_node_name" not in st.session_state:
    st.session_state.current_node_name = ""
if "chat_history" not in st.session_state:
    st.session_state.chat_history = []
if "selected_doc_id" not in st.session_state:
    st.session_state.selected_doc_id = None
if "selected_doc_info" not in st.session_state:
    st.session_state.selected_doc_info = None
if "doc_list_page" not in st.session_state:
    st.session_state.doc_list_page = 1
if "doc_status_filter" not in st.session_state:
    st.session_state.doc_status_filter = None
if "auto_refresh" not in st.session_state:
    st.session_state.auto_refresh = False
if "last_pipeline_status" not in st.session_state:
    st.session_state.last_pipeline_status = None

# ==========================================
# 核心UI组件构建
# ==========================================

def get_status_badge(status: str) -> str:
    status_map = {
        "processed": ("✅ 已处理", "status-processed"),
        "processing": ("⏳ 处理中", "status-processing"),
        "pending": ("⏸️ 等待中", "status-pending"),
        "failed": ("❌ 失败", "status-failed"),
        "preprocessed": ("📝 预处理完成", "status-preprocessed")
    }
    text, css_class = status_map.get(status.lower(), (status, "status-pending"))
    return f'<span class="status-badge {css_class}">{text}</span>'

def render_left_panel():
    """左侧面板：来源与文档管理"""
    st.markdown("### 📑 来源 (文档管理)")
    st.divider()
    
    with st.expander("➕ 添加新来源", expanded=False):
        uploaded_file = st.file_uploader("选择上传文档", type=["pdf", "txt", "docx", "md"], label_visibility="collapsed")
        if uploaded_file and st.button("上传并构建技能树", use_container_width=True):
            with st.spinner("处理中..."):
                files = {"file": (uploaded_file.name, uploaded_file.getvalue(), uploaded_file.type)}
                result = api_post("/api/documents/upload", files=files)
                if result:
                    st.success(f"成功! 创建 {result['skills_count']} 个知识点")
                    st.session_state.auto_refresh = True
        
        st.markdown("或")
        text_input = st.text_area("直接粘贴文本", height=100, placeholder="在此输入要学习的文本...")
        if text_input and st.button("插入文本", use_container_width=True):
            with st.spinner("处理中..."):
                result = api_post("/api/documents/insert-text", data={"text": text_input})
                if result:
                    st.success(f"成功! 创建 {result['skills_count']} 个知识点")
                    st.session_state.auto_refresh = True
    
    st.markdown("---")
    
    col1, col2 = st.columns([3, 1])
    with col1:
        st.session_state.doc_status_filter = st.selectbox(
            "状态筛选",
            ["全部", "processed", "processing", "pending", "failed", "preprocessed"],
            index=0,
            label_visibility="collapsed"
        )
    with col2:
        if st.button("🔄", help="刷新列表"):
            st.rerun()
    
    status_filter = None if st.session_state.doc_status_filter == "全部" else st.session_state.doc_status_filter
    
    with st.spinner("加载文档列表..."):
        result = api_post("/api/documents/paginated", data={
            "page": st.session_state.doc_list_page,
            "page_size": 20,
            "status_filter": status_filter
        })
    
    if result:
        docs = result.get("documents", [])
        pagination = result.get("pagination", {})
        status_counts = result.get("status_counts", {})
        
        st.markdown(f"**文档总数:** {pagination.get('total_count', 0)}")
        
        status_labels = {
            "processed": "已处理",
            "processing": "处理中",
            "pending": "等待",
            "failed": "失败",
            "preprocessed": "预处理"
        }
        
        filtered_counts = {k: v for k, v in status_counts.items() if k.lower() in status_labels}
        
        if filtered_counts:
            count_cols = st.columns(len(filtered_counts))
            for i, (status, count) in enumerate(filtered_counts.items()):
                with count_cols[i]:
                    st.metric(status_labels.get(status.lower(), status), count)
        
        st.markdown("---")
        
        for doc in docs:
            doc_id = doc.get("id", "")
            is_selected = st.session_state.selected_doc_id == doc_id
            
            card_class = "doc-card selected" if is_selected else "doc-card"
            
            with st.container():
                st.markdown(f"""
                <div class="{card_class}">
                    <div style="display: flex; justify-content: space-between; align-items: center;">
                        <strong style="font-size: 0.9rem;">📄 {doc.get('file_path', '未知文档')}</strong>
                        {get_status_badge(doc.get('status', 'pending'))}
                    </div>
                    <div style="font-size: 0.75rem; color: #666; margin-top: 4px;">
                        {doc.get('content_summary', '')[:50]}...
                    </div>
                    <div style="font-size: 0.7rem; color: #999; margin-top: 4px;">
                        大小: {doc.get('content_length', 0)} 字符 | 分块: {doc.get('chunks_count', 0)} | 更新: {doc.get('updated_at', '')[:16]}
                    </div>
                </div>
                """, unsafe_allow_html=True)
                
                c1, c2, c3 = st.columns([2, 1, 1])
                with c1:
                    if st.button("📋 查看", key=f"view_{doc_id}", use_container_width=True):
                        st.session_state.selected_doc_id = doc_id
                        st.session_state.selected_doc_info = doc
                        st.session_state.center_mode = "doc_detail"
                        st.rerun()
                with c2:
                    if st.button("📊", key=f"kg_{doc_id}", help="查看知识图谱"):
                        st.session_state.selected_doc_id = doc_id
                        st.session_state.center_mode = "knowledge_graph"
                        st.rerun()
                with c3:
                    if st.button("🗑️", key=f"del_{doc_id}", help="删除文档"):
                        if api_delete(f"/api/documents/{doc_id}"):
                            st.success("已删除")
                            st.rerun()
                
                if doc.get("error_msg"):
                    st.error(f"错误: {doc.get('error_msg')}")
                
                st.markdown("")
        
        if pagination.get("has_prev") or pagination.get("has_next"):
            nav_col1, nav_col2, nav_col3 = st.columns([1, 2, 1])
            with nav_col1:
                if pagination.get("has_prev") and st.button("⬅️ 上一页"):
                    st.session_state.doc_list_page -= 1
                    st.rerun()
            with nav_col3:
                if pagination.get("has_next") and st.button("下一页 ➡️"):
                    st.session_state.doc_list_page += 1
                    st.rerun()
    
    st.markdown("---")
    
    pipeline_status = api_get("/api/documents/pipeline-status")
    if pipeline_status:
        busy = pipeline_status.get("busy", False)
        if busy:
            st.info(f"⏳ 处理中: {pipeline_status.get('job_name', '')}")
            st.progress(
                pipeline_status.get("cur_batch", 0) / max(pipeline_status.get("batchs", 1), 1),
                text=f"进度: {pipeline_status.get('cur_batch', 0)}/{pipeline_status.get('batchs', 0)}"
            )
            st.caption(pipeline_status.get("latest_message", ""))
        else:
            st.success("✅ 处理完成，无任务进行中")

def render_center_panel():
    """中间面板：主干内容与问答对话"""
    
    if st.session_state.center_mode == "home":
        st.markdown(f"## 🤖 AI辅助教学系统概览")
        progress = api_get("/api/learning/progress")
        if progress:
            summary = progress["summary"]
            st.info("欢迎回来！以下是您的学习进度摘要：")
            c1, c2, c3 = st.columns(3)
            c1.metric("整体进度", f"{summary['overall_progress']:.1f}%")
            c2.metric("平均掌握度", f"{summary['average_mastery']:.1f}%")
            c3.metric("总知识点", summary["total_nodes"])
            
    elif st.session_state.center_mode == "learning":
        st.markdown(f"## 📖 {st.session_state.current_node_name}")
        st.markdown(st.session_state.current_learning_content)
        
    elif st.session_state.center_mode == "quiz":
        render_quiz_execution()
    
    elif st.session_state.center_mode == "doc_detail":
        render_document_detail()
    
    elif st.session_state.center_mode == "knowledge_graph":
        render_knowledge_graph()
    
    st.markdown("---")
    
    st.markdown("### 💬 对话与问答")
    
    chat_container = st.container(height=400)
    with chat_container:
        for msg in st.session_state.chat_history:
            with st.chat_message(msg["role"]):
                st.markdown(msg["content"])
                if "refs" in msg and msg["refs"]:
                    st.caption(f"📚 来源: {', '.join(msg['refs'])}")

    query = st.chat_input("开始输入问题...", key="main_chat_input")
    if query:
        st.session_state.chat_history.append({"role": "user", "content": query})
        
        with chat_container:
            with st.chat_message("user"):
                st.markdown(query)
            
            with st.chat_message("assistant"):
                mode = st.session_state.get("qa_mode", "mix")
                inc_refs = st.session_state.get("qa_refs", False)
                
                response_placeholder = st.empty()
                full_response = ""
                references = []
                
                try:
                    with requests.post(
                        f"{BASE_URL}/api/learning/query/stream",
                        json={
                            "query": query,
                            "mode": mode,
                            "include_references": inc_refs
                        },
                        stream=True,
                        timeout=300
                    ) as response:
                        response.raise_for_status()
                        
                        for line in response.iter_lines(decode_unicode=True):
                            if line:
                                try:
                                    data = json.loads(line)
                                    
                                    if "references" in data:
                                        references = data["references"]
                                    
                                    if "response" in data:
                                        chunk = data["response"]
                                        full_response += chunk
                                        response_placeholder.markdown(
                                            f'<div class="streamming-text">{full_response}▌</div>',
                                            unsafe_allow_html=True
                                        )
                                    
                                    if "error" in data:
                                        st.error(f"错误: {data['error']}")
                                        break
                                        
                                except json.JSONDecodeError:
                                    continue
                        
                        response_placeholder.markdown(full_response)
                        
                except Exception as e:
                    st.error(f"请求失败: {str(e)}")
                    full_response = "抱歉，处理您的请求时出现错误。"
                    response_placeholder.markdown(full_response)
                
                if references:
                    ref_names = [r.get('file_path', 'Unknown') for r in references]
                    st.caption(f"📚 来源: {', '.join(ref_names)}")
                
                st.session_state.chat_history.append({
                    "role": "assistant", 
                    "content": full_response,
                    "refs": [r.get('file_path', 'Unknown') for r in references] if references else []
                })

def render_document_detail():
    """渲染文档详情页面"""
    if not st.session_state.selected_doc_id:
        st.warning("请先选择一个文档")
        if st.button("返回主页"):
            st.session_state.center_mode = "home"
            st.rerun()
        return
    
    doc = st.session_state.selected_doc_info
    if not doc:
        result = api_get(f"/api/documents/track/{st.session_state.selected_doc_id}")
        if result and result.get("documents"):
            doc = result["documents"][0]
        else:
            st.error("无法获取文档信息")
            return
    
    st.markdown(f"## 📄 文档详情")
    
    if st.button("⬅️ 返回"):
        st.session_state.center_mode = "home"
        st.rerun()
    
    st.markdown("---")
    
    col1, col2 = st.columns([2, 1])
    with col1:
        st.markdown(f"**文件名:** {doc.get('file_path', '未知')}")
        st.markdown(f"**文档ID:** {doc.get('id', '')}")
        st.markdown(f"**状态:** {get_status_badge(doc.get('status', 'pending'))}", unsafe_allow_html=True)
    
    with col2:
        st.markdown(f"**创建时间:** {doc.get('created_at', '')[:19]}")
        st.markdown(f"**更新时间:** {doc.get('updated_at', '')[:19]}")
        st.markdown(f"**Track ID:** {doc.get('track_id', 'N/A')[:20]}...")
    
    st.markdown("---")
    
    st.markdown("### 📊 文档统计")
    c1, c2, c3 = st.columns(3)
    c1.metric("内容长度", f"{doc.get('content_length', 0):,} 字符")
    c2.metric("分块数量", doc.get('chunks_count', 0))
    c3.metric("处理状态", doc.get('status', 'pending'))
    
    st.markdown("---")
    
    st.markdown("### 📝 内容摘要")
    st.info(doc.get('content_summary', '暂无摘要'))
    
    if doc.get('error_msg'):
        st.error(f"**处理错误:** {doc.get('error_msg')}")
    
    if doc.get('metadata'):
        st.markdown("### 🏷️ 元数据")
        st.json(doc.get('metadata'))
    
    st.markdown("---")
    
    st.markdown("### 🧠 关联知识点")
    knowledge_result = api_get(f"/api/documents/{st.session_state.selected_doc_id}/knowledge")
    if knowledge_result and knowledge_result.get("knowledge_nodes"):
        nodes = knowledge_result["knowledge_nodes"]
        st.markdown(f"共 {len(nodes)} 个知识点")
        
        for node in nodes[:10]:
            with st.expander(f"📖 {node['name']} - {node['status']}", expanded=False):
                st.markdown(f"**描述:** {node.get('description', '暂无描述')}")
                st.markdown(f"**掌握度:** {node.get('mastery', 0):.1f}%")
                st.progress(node.get('mastery', 0) / 100)
    else:
        st.info("暂无关联知识点")

def render_knowledge_graph():
    """渲染知识图谱视图"""
    if not st.session_state.selected_doc_id:
        st.warning("请先选择一个文档")
        if st.button("返回主页"):
            st.session_state.center_mode = "home"
            st.rerun()
        return
    
    st.markdown(f"## 📊 知识图谱")
    
    if st.button("⬅️ 返回"):
        st.session_state.center_mode = "home"
        st.rerun()
    
    st.markdown("---")
    
    knowledge_result = api_get(f"/api/documents/{st.session_state.selected_doc_id}/knowledge")
    if knowledge_result and knowledge_result.get("knowledge_nodes"):
        nodes = knowledge_result["knowledge_nodes"]
        
        st.markdown(f"### 知识点网络 ({len(nodes)} 个节点)")
        
        for node in nodes:
            icon = {"locked": "🔒", "available": "✅", "learning": "📖", "completed": "🏆"}.get(node.get('status', 'locked'), "❓")
            st.markdown(f"**{icon} {node['name']}**")
            st.markdown(f"_{node.get('description', '暂无描述')}_")
            st.progress(node.get('mastery', 0) / 100, text=f"掌握度: {node.get('mastery', 0):.1f}%")
            
            if node.get('parent_ids'):
                st.caption(f"前置知识: {', '.join(node['parent_ids'][:3])}")
            st.markdown("---")
    else:
        st.info("暂无知识点数据，请等待文档处理完成")

def render_right_panel():
    """右侧面板：Studio功能组件区 (进度、技能树、测验设置)"""
    st.markdown("### 🛠️ Studio")
    st.divider()
    
    # 组件1：智能问答设置 (抽离到侧边栏，保持中间简洁)
    with st.expander("⚙️ 问答设置"):
        st.session_state.qa_mode = st.selectbox("查询模式", ["mix", "local", "global", "hybrid", "naive", "bypass"])
        st.session_state.qa_refs = st.checkbox("包含参考文献", value=False)
        if st.button("清空对话历史", use_container_width=True):
            st.session_state.chat_history = []
            st.rerun()

    # 组件2：技能树控制台
    with st.expander("🌳 技能树与学习", expanded=True):
        nodes = api_get("/api/skill-tree/nodes")
        if nodes:
            status_filter = st.selectbox("状态筛选", ["全部", "locked", "available", "learning", "completed"], label_visibility="collapsed")
            filtered_nodes = nodes if status_filter == "全部" else [n for n in nodes if n["status"] == status_filter]
            
            for node in filtered_nodes:
                icon = {"locked": "🔒", "available": "✅", "learning": "📖", "completed": "🏆"}.get(node["status"], "❓")
                st.markdown(f"**{icon} {node['name']}**")
                st.progress(node['mastery'] / 100, text=f"掌握度: {node['mastery']:.1f}%")
                
                c1, c2 = st.columns(2)
                if node["status"] in ["available", "learning"]:
                    if c1.button("开始学习", key=f"learn_{node['id']}", use_container_width=True):
                        with st.spinner("生成中..."):
                            content = api_get(f"/api/skill-tree/nodes/{node['id']}/learning-content")
                            if content:
                                st.session_state.center_mode = "learning"
                                st.session_state.current_node_name = node['name']
                                st.session_state.current_learning_content = content["content"]
                                st.rerun()
                if node["status"] == "learning":
                    if c2.button("标记完成", key=f"comp_{node['id']}", use_container_width=True):
                        if api_post(f"/api/skill-tree/nodes/{node['id']}/complete"):
                            st.success("已完成")
                            st.rerun()
                st.markdown("---")

    # 组件3：测验评估设置
    with st.expander("📝 测验评估配置"):
        if nodes:
            available_nodes = [n for n in nodes if n["status"] in ["available", "learning", "completed"]]
            if available_nodes:
                selected_node = st.selectbox("选择测试点", available_nodes, format_func=lambda x: f"{x['name']}")
                num_q = st.slider("题目数量", 3, 10, 5)
                if st.button("✨ 生成测验 (将在主视窗打开)", use_container_width=True, type="primary"):
                    with st.spinner("正在生成..."):
                        quiz_data = api_get(f"/api/quiz/generate/{selected_node['id']}", params={"num_questions": num_q})
                        if quiz_data:
                            st.session_state.center_mode = "quiz"
                            st.session_state.current_quiz = quiz_data
                            st.session_state.quiz_answers = {}
                            st.session_state.quiz_selected_node_id = selected_node['id']
                            st.rerun()

def render_quiz_execution():
    """专门用于在中间栏渲染正在进行的测验"""
    if "current_quiz" not in st.session_state:
        st.session_state.center_mode = "home"
        st.rerun()
        
    quiz = st.session_state.current_quiz
    st.markdown(f"## 📝 测验: {quiz['node_name']}")
    answers = st.session_state.quiz_answers
    
    for i, q in enumerate(quiz["questions"]):
        st.markdown(f"**Q{i+1}. {q['question']}**")
        
        if q["type"] == "multiple_choice":
            ans = st.radio("选择答案", q["options"], key=f"q_{q['id']}", index=None, label_visibility="collapsed")
        elif q["type"] == "true_false":
            ans = st.radio("判断", ["对", "错"], key=f"q_{q['id']}", index=None, label_visibility="collapsed")
        elif q["type"] == "short_answer":
            ans = st.text_area("回答", key=f"q_{q['id']}", label_visibility="collapsed")
            
        if ans: answers[q["id"]] = ans
        st.markdown("<br>", unsafe_allow_html=True)
        
    if st.button("提交试卷", type="primary"):
        if len(answers) == len(quiz["questions"]):
            with st.spinner("正在评分..."):
                result = api_post(
                    f"/api/quiz/submit/{st.session_state.quiz_selected_node_id}",
                    data={"questions": quiz["questions"], "user_answers": answers}
                )
                if result:
                    st.success(f"测验完成！得分: {result['grading_result']['score']:.1f}%")
                    for detail in result["grading_result"]["details"]:
                        st.info(f"{'✅' if detail['correct'] else '❌'} 你的答案: {detail['user_answer']} | 正确: {detail['correct_answer']}")
                        if detail["feedback"]: st.caption(f"💡 {detail['feedback']}")
                    
                    if st.button("返回主页"):
                        st.session_state.center_mode = "home"
                        st.rerun()
        else:
            st.warning("请回答所有问题！")

# ==========================================
# 页面主渲染流程 (三栏布局)
# ==========================================
def main():
    # 顶部标题 (模拟左上角Logo区域)
    st.markdown("### 📚 AI Foundations & Applications")
    
    # 划分三栏布局：左侧比例较小，中间最宽，右侧中等
    col_left, col_center, col_right = st.columns([1.2, 3, 1.2], gap="large")
    
    with col_left:
        render_left_panel()
        
    with col_center:
        render_center_panel()
        
    with col_right:
        render_right_panel()

if __name__ == "__main__":
    main()