import uuid
import json
from typing import List, Dict, Any
from .lightrag_client import LightRAGClient

class SkillTreeBuilder:
    def __init__(self, lightrag_client: LightRAGClient):
        self.lightrag = lightrag_client
    
    async def build_skill_tree_from_document(self, doc_id: str, content_summary: str) -> List[Dict[str, Any]]:
        query = f"""
基于以下文档内容，构建一个技能树结构。请按照以下要求：

1. 识别出文档中的主要知识点和概念
2. 确定知识点之间的依赖关系（前置知识点）
3. 为每个知识点提供简短的描述
4. 将知识点组织成层级结构

文档摘要：
{content_summary}

请以JSON格式返回，格式如下：
{{
    "skills": [
        {{
            "id": "skill_1",
            "name": "知识点名称",
            "description": "知识点描述",
            "parent_ids": ["前置知识点ID列表"]
        }}
    ]
}}
"""
        
        result = await self.lightrag.query(query, mode="mix")
        response_text = result.get("response", "")
        
        try:
            json_start = response_text.find("{")
            json_end = response_text.rfind("}") + 1
            json_str = response_text[json_start:json_end]
            data = json.loads(json_str)
            
            id_mapping = {}
            skills = []
            
            for skill in data.get("skills", []):
                old_id = skill.get("id", str(uuid.uuid4()))
                new_id = str(uuid.uuid4())
                id_mapping[old_id] = new_id
                
                skills.append({
                    "id": new_id,
                    "name": skill.get("name", "未命名知识点"),
                    "description": skill.get("description", ""),
                    "parent_ids": skill.get("parent_ids", []),
                    "doc_id": doc_id,
                    "status": "locked",
                    "mastery": 0.0,
                    "_old_parent_ids": skill.get("parent_ids", [])
                })
            
            for skill in skills:
                old_parent_ids = skill.pop("_old_parent_ids", [])
                new_parent_ids = [id_mapping.get(pid, pid) for pid in old_parent_ids]
                skill["parent_ids"] = new_parent_ids
            
            root_nodes = [s for s in skills if not s["parent_ids"]]
            for node in root_nodes:
                node["status"] = "available"
            
            if not root_nodes and skills:
                skills[0]["status"] = "available"
            
            return skills
        except Exception as e:
            return self._fallback_skill_tree(doc_id, content_summary)
    
    def _fallback_skill_tree(self, doc_id: str, content_summary: str) -> List[Dict[str, Any]]:
        return [
            {
                "id": str(uuid.uuid4()),
                "name": "概述",
                "description": "了解文档的核心内容和主要概念",
                "parent_ids": [],
                "doc_id": doc_id,
                "status": "available",
                "mastery": 0.0
            },
            {
                "id": str(uuid.uuid4()),
                "name": "核心概念",
                "description": "深入学习文档中的关键概念",
                "parent_ids": [],
                "doc_id": doc_id,
                "status": "locked",
                "mastery": 0.0
            }
        ]
    
    async def generate_learning_content(self, node_name: str, node_description: str) -> str:
        query = f"""
请为以下知识点生成教学内容：

知识点名称：{node_name}
知识点描述：{node_description}

请生成详细的教学内容，包括：
1. 概念解释
2. 关键要点
3. 示例说明
4. 学习建议

请使用通俗易懂的语言，适合初学者理解。
"""
        
        result = await self.lightrag.query(query, mode="mix")
        return result.get("response", "")
