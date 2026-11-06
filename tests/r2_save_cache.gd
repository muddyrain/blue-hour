extends SceneTree
## Exact full-content identities must never reuse a proof after nested mutation.
var failures: int=0
var checks: int=0

func _initialize() -> void:
	call_deferred("run")

func expect(valid: bool, label: String) -> void:
	checks+=1
	if not valid:
		failures+=1
		printerr("R2_CACHE_FAIL ",label)

func verify(value: Dictionary, label: String) -> void:
	var exact: String=RecordEncoding._digest(RecordEncoding._encode(value)) if SurvivalContracts._json_value(value,-2) else ""
	var normal: Variant=JSON.parse_string(JSON.stringify(value,"",true,true)) if SurvivalContracts._json_value(value,-2) else null
	var legacy: String=JSON.stringify(normal,"",true,true).sha256_text() if normal is Dictionary else ""
	var business: String=legacy if SurvivalContracts._json_value(value,0) else ""
	for pass_number: int in range(2):
		expect(SurvivalContracts.json_value(value,0)==SurvivalContracts._json_value(value,0),label+" JSON depth0 "+str(pass_number))
		expect(SurvivalContracts.json_value(value,-2)==SurvivalContracts._json_value(value,-2),label+" JSON depth-2 "+str(pass_number))
		expect(RecordEncoding.fingerprint(value)==exact,label+" exact "+str(pass_number))
		expect(TransactionReceipt.legacy_fingerprint(value)==legacy,label+" legacy "+str(pass_number))
		expect(SurvivalContracts.fingerprint(value)==business,label+" business "+str(pass_number))

func run() -> void:
	expect({"x":[200.0]}!={"x":[199.99999999999997]},"fixed engine native nested comparison rejects adjacent ULP")
	expect({"x":[5e-20]}!={"x":[6e-20]},"fixed engine native comparison is not approximate")
	verify({"zero":0.0},"positive zero first")
	verify({"zero":-0.0},"negative zero after positive")
	verify({"x":INF},"positive infinity rejected")
	verify({"x":NAN},"NaN rejected")
	verify({"x":200.0},"finite after nonfinite")
	verify({"limit":float(SurvivalContracts.MAX_JSON_INTEGER+1)},"finite float outside safe integer range")
	verify({"limit":SurvivalContracts.MAX_JSON_INTEGER+1},"unsafe int cannot alias equal-valued valid float")
	var value: Dictionary={"geometry":{"rect":[16.0,32,280,80]},"rewards":{"cash":5},"person":{"health":200.0,"dead":false},"tiny":5e-20}
	verify(value,"cold and warm")
	var original: String=RecordEncoding.fingerprint(value)
	value.geometry.rect[0]=17.0
	verify(value,"same dictionary nested geometry")
	expect(RecordEncoding.fingerprint(value)!=original,"changed geometry cannot use prior proof")
	value.rewards.cash=6
	verify(value,"same dictionary nested reward")
	value.person.health=0.0
	value.person.dead=true
	verify(value,"same dictionary permanent death facts")
	value.tiny=6e-20
	verify(value,"distinct tiny binary64")
	value.person.health=INF
	verify(value,"invalid after valid")
	value.person.health=200.0
	verify(value,"valid after invalid")
	verify({"zero":-0.0,"int":1,"float":1.0,"name":&"name","null":null,"bool":true},"supported scalar representations")
	verify({"b":{"n":200.0},"a":1},"original dictionary order")
	verify({"a":1,"b":{"n":200.0}},"different dictionary order")
	verify({"a":1,"b":{"n":199.99999999999997}},"one ULP difference cannot alias proof")
	verify({"a":1.0,"b":{"n":200.0}},"integer and float input normalization")
	var deep: Dictionary={"leaf":1}
	for index: int in range(67): deep={"child":deep}
	verify(deep,"depth rejection")
	var object: RefCounted=RefCounted.new()
	verify({"unsupported":object},"object cannot alias valid null")
	verify({"unsupported":null},"valid null after invalid object")
	print("R2_SAVE_CACHE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures==0 else 1)
