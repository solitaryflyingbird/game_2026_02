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
    "phase": "waiting"
}
const GRADE_FACES = {
    1: [1,1,1,1,2,2,2],
    2: [1,1,1,2,2,2,2],
    3: [2,2,2,2,3,3,3],
    4: [3,3,3,3,2,2,2],
}
