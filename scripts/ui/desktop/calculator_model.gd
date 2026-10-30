class_name DesktopCalculator
extends RefCounted
## Ordinary sequential calculator, not an expression evaluator. No eval/user code.

var entry: String = "0"
var error: bool = false
var error_message: String = ""
var _stored: float = 0.0
var _operator: String = ""
var _new_entry: bool = true
var _repeat_operator: String = ""
var _repeat_value: float = 0.0


func press(token: String) -> void:
	if token == "C":
		clear()
	elif token == "CE":
		entry = "0"
		error = false
		error_message = ""
		_new_entry = false
		_repeat_operator = ""
	elif token in ["+", "-", "*", "/"]:
		_operation(token)
	elif token == "=":
		_equals()
	elif token == "BACK":
		if error:
			clear()
		elif not _new_entry:
			entry = entry.left(-1)
			if entry in ["", "-"]:
				entry = "0"
	elif token == "SIGN":
		if not error:
			if _new_entry and not _operator.is_empty():
				entry = "0"
			entry = entry.trim_prefix("-") if entry.begins_with("-") else "-" + entry
			_new_entry = false
	elif token in [".", ","] or (token.length() == 1 and token in "0123456789"):
		if error:
			clear()
		if _new_entry:
			entry = "0"
			_new_entry = false
			if _operator.is_empty():
				_repeat_operator = ""
		if token in [".", ","]:
			if not entry.contains("."):
				entry += "."
		elif entry.replace("-", "").replace(".", "").length() < 14:
			if entry in ["0", "-0"]:
				entry = ("-" if entry.begins_with("-") else "") + token
			else:
				entry += token


func clear() -> void:
	entry = "0"
	error = false
	error_message = ""
	_stored = 0.0
	_operator = ""
	_new_entry = true
	_repeat_operator = ""
	_repeat_value = 0.0


func _operation(operation: String) -> void:
	if error:
		return
	if not _operator.is_empty() and not _new_entry:
		_stored = _calculate(_stored, entry.to_float(), _operator)
		if error:
			return
		entry = _format(_stored)
	elif _operator.is_empty():
		_stored = entry.to_float()
	_operator = operation
	_new_entry = true
	_repeat_operator = ""


func _equals() -> void:
	if error:
		return
	var result := entry.to_float()
	if not _operator.is_empty():
		_repeat_value = _stored if _new_entry else entry.to_float()
		_repeat_operator = _operator
		result = _calculate(_stored, _repeat_value, _operator)
		_operator = ""
	elif not _repeat_operator.is_empty():
		result = _calculate(result, _repeat_value, _repeat_operator)
	if not error:
		entry = _format(result)
		_new_entry = true


func _calculate(left: float, right: float, operation: String) -> float:
	var result := 0.0
	match operation:
		"+": result = left + right
		"-": result = left - right
		"*": result = left * right
		"/":
			if right == 0.0:
				_fail("Деление на ноль")
				return 0.0
			result = left / right
	if not is_finite(result) or absf(result) >= 1.0e14:
		_fail("Число слишком велико")
	return result


func _fail(message: String) -> void:
	error = true
	error_message = message
	entry = "Ошибка"
	_operator = ""
	_repeat_operator = ""


func _format(value: float) -> String:
	var text := String.num(value, 10).trim_suffix(".0")
	return "0" if text == "-0" else text
