extends Node
const starting_data = {
    "hp": 30,
    "max_hp": 30,
    "floor": 1,
    "dice": {
        "attack": { "grade": 1, "grade_exp": 0 },
        "block":  { "grade": 1, "grade_exp": 0 },
        "boost":  { "grade": 1, "grade_exp": 0 },
        "heal":   { "grade": 1, "grade_exp": 0 },
    },
    "phase": "title"
}
const GRADE_FACES = {
    1: [1,1,1,1,2,2,2],
    2: [1,1,1,2,2,2,2],
    3: [2,2,2,2,3,3,3],
    4: [3,3,3,3,2,2,2],
}

const ENEMIES = {
    "slime": {
        "name": "슬라임",
        "hp": 15,
        "skills": [
            { "type": "attack", "value": 3 },
            { "type": "attack", "value": 5 },
        ],
    },
    "goblin": {
        "name": "고블린",
        "hp": 20,
        "skills": [
            { "type": "attack", "value": 4 },
            { "type": "attack", "value": 6 },
        ],
    },
    "golem": {
        "name": "골렘",
        "hp": 30,
        "skills": [
            { "type": "attack", "value": 4 },
            { "type": "attack", "value": 6 },
            { "type": "attack", "value": 8 },
        ],
    },
}
 
const FLOOR_ENCOUNTERS = {
    1: ["slime"],
    2: ["slime", "slime"],
    3: ["goblin"],
    4: ["goblin", "slime"],
    5: ["golem"],
    6: ["golem", "goblin"],
}
