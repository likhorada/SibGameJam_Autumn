extends RefCounted
## Briefing plus legacy dev quiz. Live questions come from ShiftDirector's run facts.
const INTRO := [
	{"messages": ["CHAT_INTRO_1", "CHAT_INTRO_2"], "answers": ["CHAT_REPLY_1", "CHAT_REPLY_2"]},
	{"messages": ["CHAT_TUTORIAL_1", "CHAT_TUTORIAL_2", "CHAT_TUTORIAL_3"], "answers": ["CHAT_REPLY_3"]},
	{"messages": ["CHAT_THREAT_1", "CHAT_THREAT_2", "OBS_BRIEF"], "answers": ["CHAT_REPLY_4", "CHAT_REPLY_5"]},
]
const QUESTIONS := [
	{"id": "target", "prompt": "CHAT_Q1", "answers": ["CHAT_A_VIKTOR", "CHAT_A_ANTON", "CHAT_A_PAVEL"], "correct": "CHAT_A_VIKTOR"},
	{"id": "drink", "prompt": "CHAT_Q2", "answers": ["CHAT_A_TEA", "CHAT_A_COFFEE", "CHAT_A_WATER"], "correct": "CHAT_A_COFFEE"},
	{"id": "meeting", "prompt": "CHAT_Q3", "answers": ["CHAT_A_IGOR", "CHAT_A_OLGA", "CHAT_A_ANNA"], "correct": "CHAT_A_ANNA"},
]
