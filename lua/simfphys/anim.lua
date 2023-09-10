hook.Add("CalcMainActivity", "simfphysSeatActivityOverride", function(ply)
	local veh, inVehicle = ply:GetSimfphys()

	if not inVehicle then return end
	if not veh:IsValid() then return end

	if ply.m_bWasNoclipping then
		ply.m_bWasNoclipping = nil
		ply:AnimResetGestureSlot( GESTURE_SLOT_CUSTOM )

		if CLIENT then
			ply:SetIK( true )
		end
	end

	ply.CalcIdeal = ACT_HL2MP_SIT
	ply.CalcSeqOverride = isfunction( veh.GetSeatAnimation ) and veh:GetSeatAnimation( ply ) or -1

	if not ply:IsDrivingSimfphys() and ply:GetAllowWeaponsInVehicle() and ply:GetActiveWeapon():IsValid() then
		
		local holdtype = ply:GetActiveWeapon():GetHoldType()

		if holdtype == "smg" then
			holdtype = "smg1"
		end

		local seqid = ply:LookupSequence( "sit_" .. holdtype )

		if seqid ~= -1 then
			ply.CalcSeqOverride = seqid
		end
	end

	return ply.CalcIdeal, ply.CalcSeqOverride
end)

if CLIENT then
	hook.Add("UpdateAnimation", "simfphysPoseparameters", function(ply , vel, seq)
		if not ply:IsDrivingSimfphys() then return end

		local Car, inVehicle = ply:GetSimfphys()

		if not inVehicle then return end
		if not Car:IsValid() then return end

		local Steer = Car:GetVehicleSteer()

		ply:SetPoseParameter( "vehicle_steer", Steer )
		ply:InvalidateBoneCache()

		GAMEMODE:GrabEarAnimation( ply )
		GAMEMODE:MouthMoveAnimation( ply )

		return true
	end)
end
