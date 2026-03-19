from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session
from typing import List, Dict, Any
from datetime import datetime
import json

from ..models.database import get_db, SkillNode, LearningProgress
from ..services.lightrag_client import LightRAGClient
from ..services.skill_tree_builder import SkillTreeBuilder

router = APIRouter(prefix="/api/skill-tree", tags=["skill_tree"])

lightrag_client = LightRAGClient()
skill_tree_builder = SkillTreeBuilder(lightrag_client)

def parse_parent_ids(parent_ids) -> List[str]:
    if parent_ids is None:
        return []
    if isinstance(parent_ids, str):
        try:
            return json.loads(parent_ids)
        except:
            return []
    if isinstance(parent_ids, list):
        return parent_ids
    return []

@router.get("/nodes")
async def get_all_skill_nodes(db: Session = Depends(get_db)):
    nodes = db.query(SkillNode).all()
    return [
        {
            "id": node.id,
            "name": node.name,
            "description": node.description,
            "parent_ids": node.parent_ids,
            "doc_id": node.doc_id,
            "status": node.status,
            "mastery": node.mastery,
            "created_at": node.created_at,
            "updated_at": node.updated_at
        }
        for node in nodes
    ]

@router.get("/nodes/{node_id}")
async def get_skill_node(node_id: str, db: Session = Depends(get_db)):
    node = db.query(SkillNode).filter(SkillNode.id == node_id).first()
    if not node:
        raise HTTPException(status_code=404, detail="Skill node not found")
    return {
        "id": node.id,
        "name": node.name,
        "description": node.description,
        "parent_ids": node.parent_ids,
        "doc_id": node.doc_id,
        "status": node.status,
        "mastery": node.mastery,
        "created_at": node.created_at,
        "updated_at": node.updated_at
    }

@router.get("/nodes/{node_id}/learning-content")
async def get_learning_content(node_id: str, db: Session = Depends(get_db)):
    node = db.query(SkillNode).filter(SkillNode.id == node_id).first()
    if not node:
        raise HTTPException(status_code=404, detail="Skill node not found")
    
    content = await skill_tree_builder.generate_learning_content(node.name, node.description)
    
    if node.status == "available":
        node.status = "learning"
        node.updated_at = datetime.utcnow()
        db.commit()
    
    return {
        "node_id": node_id,
        "node_name": node.name,
        "content": content
    }

@router.post("/nodes/{node_id}/complete")
async def complete_skill_node(node_id: str, db: Session = Depends(get_db)):
    node = db.query(SkillNode).filter(SkillNode.id == node_id).first()
    if not node:
        raise HTTPException(status_code=404, detail="Skill node not found")
    
    node.status = "completed"
    node.mastery = max(node.mastery, 70.0)
    node.updated_at = datetime.utcnow()
    
    all_nodes = db.query(SkillNode).all()
    unlocked_nodes = []
    
    for n in all_nodes:
        if n.status == "locked":
            parent_ids = parse_parent_ids(n.parent_ids)
            
            if node_id in parent_ids:
                all_parents_completed = True
                for parent_id in parent_ids:
                    parent = db.query(SkillNode).filter(SkillNode.id == parent_id).first()
                    if not parent or parent.status != "completed":
                        all_parents_completed = False
                        break
                
                if all_parents_completed:
                    n.status = "available"
                    n.updated_at = datetime.utcnow()
                    unlocked_nodes.append(n.id)
    
    db.commit()
    
    return {
        "status": "success",
        "node_id": node_id,
        "message": "Skill node marked as completed",
        "unlocked_nodes": unlocked_nodes
    }

@router.put("/nodes/{node_id}/mastery")
async def update_mastery(node_id: str, mastery: float, db: Session = Depends(get_db)):
    node = db.query(SkillNode).filter(SkillNode.id == node_id).first()
    if not node:
        raise HTTPException(status_code=404, detail="Skill node not found")
    
    node.mastery = mastery
    node.updated_at = datetime.utcnow()
    db.commit()
    
    return {
        "status": "success",
        "node_id": node_id,
        "mastery": mastery
    }
