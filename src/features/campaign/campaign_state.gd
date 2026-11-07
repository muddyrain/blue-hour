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
	if CampaignRules.is_investigation(value):
		if not WorldgenState.level_enabled(camp):
			return "INVESTIGATION_CAMP_CAPABILITY"
		for clue: Dictionary in value.clues:
			var ordinal: int = int(clue.transaction_id.get_slice(":",1))
			var expected: String = ("daily-v4:%s:%d:1" % [camp.journey.seed, ordinal + 1]).sha256_text()
			if ordinal > camp.settled_sorties or clue.action_id != expected:
				return "INVESTIGATION_CLUE_SOURCE"
	elif value.preparations>camp.settled_sorties: return "CAMPAIGN_PREPARATIONS_SOURCE"
	if value.outcome=="DEFEAT" and camp.journey.state!="FAILED": return "CAMPAIGN_DEFEAT_SOURCE"
	if value.outcome!="DEFEAT" and camp.journey.state!="ACTIVE": return "CAMPAIGN_LIFE_SOURCE"
	if value.outcome!="ACTIVE" and value.result_transaction!=camp.last_settlement_id: return "CAMPAIGN_RESULT_SOURCE"
	if value.outcome=="VICTORY" and ((not CampaignRules.is_investigation(value) and camp.settled_sorties<5) or not camp.last_day.get("evacuated",false)): return "CAMPAIGN_VICTORY_SOURCE"
	return ""

static func settled(before: Dictionary, after: Dictionary, report: Dictionary, generated: Dictionary) -> Dictionary:
	var value: Dictionary=before.journey.campaign.duplicate(true)
	if CampaignRules.is_investigation(value):
		# FrozenSettlement has already authenticated both the offer and every site's completion.
		var source: Dictionary = generated.get("investigation", {})
		if not source.is_empty() and source.clue_id == CampaignRules.next_clue(value) and report.evacuated and after.journey.state == "ACTIVE":
			if report.site_facts[source.site_id].searched and report.member_results.any(func(member: Dictionary) -> bool: return member.health > 0):
				value.clues.append({"id":source.clue_id, "transaction_id":report.sortie_id,
					"action_id":generated.id, "site_id":source.site_id})
	elif report.evacuated and not generated.campaign.is_finale: value.preparations+=1
	if after.journey.state=="FAILED": value.outcome="DEFEAT"
	elif report.evacuated and generated.campaign.is_finale and not report.encounter.defeat.is_empty(): value.outcome="VICTORY"
	if value.outcome!="ACTIVE": value.result_transaction=report.sortie_id
	return value
