class_name ChatSession
extends RefCounted
## Run-local state; independent of desktop visibility, localization and presentation.
signal changed
signal finished(won: bool, score: int)
signal intro_completed
const CONTENT := preload("res://data/chat/contract.gd")
var history: Array[Dictionary] = []
var pending: Array[String] = []
var choices: Array[String] = []
var selected: String = ""
var typed: int = 0
var intro_step: int = -1
var question_index: int = -1
var score: int = 0
var quiz_started: bool = false
var ended: bool = false
var answers: Dictionary = {}
var questions: Array = CONTENT.QUESTIONS.duplicate(true)
var live_report: bool = false


func start() -> void:
	if intro_step >= 0 or quiz_started:
		return
	intro_step = 0
	_intro()


func _intro() -> void:
	if intro_step < CONTENT.INTRO.size():
		pending.assign(CONTENT.INTRO[intro_step].messages)
		choices.assign(CONTENT.INTRO[intro_step].answers)
	else:
		pending.assign(["OBS_GO"] if live_report else ["CHAT_WAIT"])
		choices.clear()
		intro_completed.emit()
	changed.emit()


func deliver_next() -> void:
	if pending.is_empty():
		return
	history.append({"sender": "handler", "text": pending.pop_front()})
	changed.emit()
	if pending.is_empty() and ended:
		finished.emit(score == questions.size(), score)


func select_reply(key: String) -> void:
	if ended or not pending.is_empty() or not choices.has(key):
		return
	selected = key
	typed = 0
	changed.emit()


func type_character(length: int) -> void:
	if not selected.is_empty() and not ended:
		typed = mini(typed + 2, length)
		changed.emit()


func submit(length: int) -> bool:
	if selected.is_empty() or typed < length or ended:
		return false
	var reply := selected
	history.append({"sender": "you", "text": reply})
	selected = ""
	typed = 0
	choices.clear()
	if quiz_started:
		var question: Dictionary = questions[question_index]
		answers[question.id] = reply
		if reply == question.correct:
			score += 1
		question_index += 1
		if question_index == questions.size():
			ended = true
			pending.assign(["CHAT_SUCCESS" if score == questions.size() else "CHAT_FAILURE"])
		else:
			_question()
	else:
		intro_step += 1
		_intro()
	changed.emit()
	return true


func start_quiz() -> void:
	if quiz_started or ended:
		return
	quiz_started = true
	question_index = 0
	selected = ""
	typed = 0
	pending.assign(["CHAT_REPORT"] if live_report else ["CHAT_TEST_FACTS", "CHAT_REPORT"])
	_question()
	changed.emit()


func _question() -> void:
	var question: Dictionary = questions[question_index]
	pending.append(question.prompt)
	choices.assign(question.answers)
