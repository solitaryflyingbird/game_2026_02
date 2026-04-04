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
    "scout_drone": {
        "name": "정찰 드론",
        "hp": 15,
        "skills": [
            { "type": "attack", "value": 3 },
            { "type": "attack", "value": 5 },
        ],
    },
    "assault_drone": {
        "name": "강습 드론",
        "hp": 20,
        "skills": [
            { "type": "attack", "value": 4 },
            { "type": "attack", "value": 6 },
        ],
    },
    "heavy_mech": {
        "name": "중장갑 메카",
        "hp": 30,
        "skills": [
            { "type": "attack", "value": 4 },
            { "type": "attack", "value": 6 },
            { "type": "attack", "value": 8 },
        ],
    },
}

const FLOOR_ENCOUNTERS = {
    1: ["scout_drone"],
    2: ["scout_drone", "scout_drone"],
    3: ["assault_drone"],
    4: ["assault_drone", "scout_drone"],
    5: ["heavy_mech"],
    6: ["heavy_mech", "assault_drone"],
}
