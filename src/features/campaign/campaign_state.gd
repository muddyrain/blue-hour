class_name CampaignState
extends RefCounted
## Adapter inside the existing 111 journey; settlement remains the only result writer.

static func is_short(camp: Dictionary) -> bool:
	return camp.get("journey",{}).has("campaign")

static func ended(camp: Dictionary) -> bool:
	return is_short(camp) and camp.journey.campaign.get("outcome")!="ACTIVE"

static func problem(camp: Dictionary) -> String:
	if not is_short(camp): return ""
	var issue: String=CampaignRules.problem(camp.journey.campaign,String(camp.get("profile_id","")))
	if not issue.is_empty(): return issue
	var value: Dictionary=camp.journey.campaign
	if value.preparations>camp.settled_sorties: return "CAMPAIGN_PREPARATIONS_SOURCE"
	if value.outcome=="DEFEAT" and camp.journey.state!="FAILED": return "CAMPAIGN_DEFEAT_SOURCE"
	if value.outcome!="DEFEAT" and camp.journey.state!="ACTIVE": return "CAMPAIGN_LIFE_SOURCE"
	if value.outcome!="ACTIVE" and value.result_transaction!=camp.last_settlement_id: return "CAMPAIGN_RESULT_SOURCE"
	if value.outcome=="VICTORY" and (camp.settled_sorties<5 or not camp.last_day.get("evacuated",false)): return "CAMPAIGN_VICTORY_SOURCE"
	return ""

static func settled(before: Dictionary, after: Dictionary, report: Dictionary, generated: Dictionary) -> Dictionary:
	var value: Dictionary=before.journey.campaign.duplicate(true)
	if report.evacuated and not generated.campaign.is_finale: value.preparations+=1
	if after.journey.state=="FAILED": value.outcome="DEFEAT"
	elif report.evacuated and generated.campaign.is_finale and not report.encounter.defeat.is_empty(): value.outcome="VICTORY"
	if value.outcome!="ACTIVE": value.result_transaction=report.sortie_id
	return value
