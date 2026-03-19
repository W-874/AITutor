from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session
from typing import List, Dict, Any
import uuid
from datetime import datetime

from ..models.database import get_db, SkillNode, QuizRecord, LearningProgress
from ..services.lightrag_client import LightRAGClient
from ..services.quiz_generator import QuizGenerator

router = APIRouter(prefix="/api/quiz", tags=["quiz"])

lightrag_client = LightRAGClient()
quiz_generator = QuizGenerator(lightrag_client)

@router.get("/generate/{node_id}")
async def generate_quiz(node_id: str, num_questions: int = 5, db: Session = Depends(get_db)):
    node = db.query(SkillNode).filter(SkillNode.id == node_id).first()
    if not node:
        raise HTTPException(status_code=404, detail="Skill node not found")
    
    questions = await quiz_generator.generate_quiz(node.name, node.description, num_questions)
    
    return {
        "node_id": node_id,
        "node_name": node.name,
        "questions": questions
    }

@router.post("/submit/{node_id}")
async def submit_quiz(node_id: str, questions: List[Dict[str, Any]], user_answers: Dict[str, str], db: Session = Depends(get_db)):
    node = db.query(SkillNode).filter(SkillNode.id == node_id).first()
    if not node:
        raise HTTPException(status_code=404, detail="Skill node not found")
    
    grading_result = await quiz_generator.grade_quiz(questions, user_answers)
    
    quiz_record = QuizRecord(
        id=str(uuid.uuid4()),
        node_id=node_id,
        questions=questions,
        answers=user_answers,
        score=grading_result["score"],
        created_at=datetime.utcnow()
    )
    db.add(quiz_record)
    
    progress = db.query(LearningProgress).filter(LearningProgress.node_id == node_id).first()
    if not progress:
        progress = LearningProgress(
            id=str(uuid.uuid4()),
            node_id=node_id,
            quiz_scores=[grading_result["score"]],
            mastery=grading_result["score"]
        )
    else:
        progress.quiz_scores.append(grading_result["score"])
        recent_scores = progress.quiz_scores[-5:]
        progress.mastery = sum(recent_scores) / len(recent_scores)
        progress.last_visit = datetime.utcnow()
    db.add(progress)
    
    node.mastery = progress.mastery
    if node.mastery >= 60 and node.status in ["available", "learning"]:
        node.status = "completed"
        
        all_nodes = db.query(SkillNode).all()
        for n in all_nodes:
            if n.status == "locked" and node_id in (n.parent_ids or []):
                parents_completed = True
                for parent_id in (n.parent_ids or []):
                    parent = db.query(SkillNode).filter(SkillNode.id == parent_id).first()
                    if not parent or parent.status != "completed":
                        parents_completed = False
                        break
                if parents_completed:
                    n.status = "available"
    
    node.updated_at = datetime.utcnow()
    db.commit()
    
    return {
        "status": "success",
        "node_id": node_id,
        "quiz_record_id": quiz_record.id,
        "grading_result": grading_result,
        "new_mastery": node.mastery,
        "new_status": node.status
    }

@router.get("/records/{node_id}")
async def get_quiz_records(node_id: str, db: Session = Depends(get_db)):
    records = db.query(QuizRecord).filter(QuizRecord.node_id == node_id).order_by(QuizRecord.created_at.desc()).all()
    return [
        {
            "id": record.id,
            "node_id": record.node_id,
            "score": record.score,
            "created_at": record.created_at,
            "questions_count": len(record.questions) if record.questions else 0
        }
        for record in records
    ]
