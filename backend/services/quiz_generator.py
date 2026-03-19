import uuid
import json
from typing import List, Dict, Any
from .lightrag_client import LightRAGClient

class QuizGenerator:
    def __init__(self, lightrag_client: LightRAGClient):
        self.lightrag = lightrag_client
    
    async def generate_quiz(self, node_name: str, node_description: str, num_questions: int = 5) -> List[Dict[str, Any]]:
        query = f"""
请为以下知识点生成测验题目：

知识点名称：{node_name}
知识点描述：{node_description}

请生成 {num_questions} 道题目，包含混合题型：选择题、判断题、简答题。

请以JSON格式返回，格式如下：
{{
    "questions": [
        {{
            "id": "q1",
            "type": "multiple_choice|true_false|short_answer",
            "question": "题目内容",
            "options": ["选项A", "选项B", "选项C", "选项D"],
            "correct_answer": "正确答案",
            "explanation": "答案解释"
        }}
    ]
}}

要求：
1. 选择题提供4个选项
2. 判断题直接给出"对"或"错"
3. 简答题没有选项，正确答案作为参考答案
"""
        
        result = await self.lightrag.query(query, mode="mix")
        response_text = result.get("response", "")
        
        try:
            json_start = response_text.find("{")
            json_end = response_text.rfind("}") + 1
            json_str = response_text[json_start:json_end]
            data = json.loads(json_str)
            
            questions = data.get("questions", [])
            for q in questions:
                if "id" not in q:
                    q["id"] = str(uuid.uuid4())
            
            return questions
        except Exception as e:
            return self._fallback_quiz(node_name)
    
    def _fallback_quiz(self, node_name: str) -> List[Dict[str, Any]]:
        return [
            {
                "id": str(uuid.uuid4()),
                "type": "multiple_choice",
                "question": f"关于{node_name}，以下哪个说法是正确的？",
                "options": ["选项A", "选项B", "选项C", "选项D"],
                "correct_answer": "选项A",
                "explanation": "请根据学习内容判断"
            },
            {
                "id": str(uuid.uuid4()),
                "type": "true_false",
                "question": f"判断：学习{node_name}非常重要。",
                "options": [],
                "correct_answer": "对",
                "explanation": "认真学习每个知识点都很重要"
            }
        ]
    
    async def grade_quiz(self, questions: List[Dict[str, Any]], user_answers: Dict[str, str]) -> Dict[str, Any]:
        query = f"""
请为以下测验进行评分：

题目：
{json.dumps(questions, ensure_ascii=False, indent=2)}

用户答案：
{json.dumps(user_answers, ensure_ascii=False, indent=2)}

请以JSON格式返回评分结果：
{{
    "score": 85.5,
    "total_questions": 10,
    "correct_questions": 8,
    "details": [
        {{
            "question_id": "q1",
            "correct": true,
            "user_answer": "用户答案",
            "correct_answer": "正确答案",
            "feedback": "反馈"
        }}
    ]
}}
"""
        
        result = await self.lightrag.query(query, mode="bypass")
        response_text = result.get("response", "")
        
        try:
            json_start = response_text.find("{")
            json_end = response_text.rfind("}") + 1
            json_str = response_text[json_start:json_end]
            return json.loads(json_str)
        except Exception as e:
            return self._fallback_grading(questions, user_answers)
    
    def _fallback_grading(self, questions: List[Dict[str, Any]], user_answers: Dict[str, str]) -> Dict[str, Any]:
        correct = 0
        details = []
        
        for q in questions:
            q_id = q["id"]
            user_answer = user_answers.get(q_id, "")
            is_correct = user_answer == q.get("correct_answer", "")
            
            if is_correct:
                correct += 1
            
            details.append({
                "question_id": q_id,
                "correct": is_correct,
                "user_answer": user_answer,
                "correct_answer": q.get("correct_answer", ""),
                "feedback": q.get("explanation", "")
            })
        
        total = len(questions)
        score = (correct / total * 100) if total > 0 else 0
        
        return {
            "score": score,
            "total_questions": total,
            "correct_questions": correct,
            "details": details
        }
