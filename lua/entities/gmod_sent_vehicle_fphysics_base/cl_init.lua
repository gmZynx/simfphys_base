include("shared.lua")

function ENT:Initialize()
	self.SmoothRPM = 0
	self.OldDist = 0
	self.PitchOffset = 0
	self.OldActive = false
	self.OldGear = 0
	self.OldThrottle = 0
	self.FadeThrottle = 0
	self.SoundMode = 0
	self.DamageSnd = CreateSound(self, "simulated_vehicles/engine_damaged.wav")
	self.EngineSounds = {}
end

function ENT:Think()
	local Active = self:GetActive()
	local Throttle = self:GetThrottle()
	local LimitRPM = self:GetLimitRPM()
	self:ManageSounds(Active, Throttle, LimitRPM)

	if self:IsDormant() then return end
	local selfTable = self:GetTable()
	local curtime = CurTime()

	selfTable.RunNext = selfTable.RunNext or 0
	if selfTable.RunNext < curtime then
		self:ManageEffects( Active, Throttle, LimitRPM, selfTable )
		self:CalcFlasher()
	end

	if selfTable.RunNext < curtime then
		self:ManageEffects( Active, Throttle, LimitRPM, selfTable )
		self:CalcFlasher()
		selfTable.RunNext = curtime + 0.06
	end

	self:SetPoseParameters(curtime)
end

function ENT:CalcFlasher()
	self.Flasher = self.Flasher or 0
	local flashspeed = self.turnsignals_damaged and 0.06 or 0.0375
	self.Flasher = self.Flasher and self.Flasher + flashspeed or 0

	if self.Flasher >= 1 then
		self.Flasher = self.Flasher - 1
	end

	self.flashnum = math.min(math.abs(math.cos(math.rad(self.Flasher * 360)) ^ 2 * 1.5), 1)
	if not self.signal_left and not self.signal_right then return end

	if LocalPlayer() == self:GetDriver() then
		local fl_snd = self.flashnum > 0.9

		if fl_snd ~= self.fl_snd then
			self.fl_snd = fl_snd

			if fl_snd then
				self:EmitSound("simulated_vehicles/sfx/flasher_on.ogg")
			else
				self:EmitSound("simulated_vehicles/sfx/flasher_off.ogg")
			end
		end
	end
end

function ENT:GetFlasher()
	self.flashnum = self.flashnum or 0

	return self.flashnum
end

function ENT:SetPoseParameters(curtime)
	local selfTable = self:GetTable()
	selfTable.sm_vSteer = selfTable.sm_vSteer and selfTable.sm_vSteer + (self:GetVehicleSteer() - selfTable.sm_vSteer) * 0.3 or 0
	self:SetPoseParameter("vehicle_steer", selfTable.sm_vSteer)

	if not istable(selfTable.pp_data) then
		selfTable.ppNextCheck = selfTable.ppNextCheck or curtime + 0.5

		if selfTable.ppNextCheck < curtime then
			selfTable.ppNextCheck = curtime + 0.5
			-- net.Start("simfphys_request_ppdata",true)
			-- 	net.WriteEntity( self )
			-- net.SendToServer()
		end
	else
		if not selfTable.CustomWheels then
			for i = 1, #selfTable.pp_data do
				local Wheel = selfTable.pp_data[i].entity

				if Wheel and Wheel:IsValid() then
					local addPos = Wheel:GetDamaged() and selfTable.pp_data[i].dradius or 0
					local Pose = (selfTable.pp_data[i].pos - self:WorldToLocal(Wheel:GetPos()).z + addPos) / selfTable.pp_data[i].travel
					self:SetPoseParameter(selfTable.pp_data[i].name, Pose)
				end
			end
		end
	end

	self:InvalidateBoneCache()
end

function ENT:GetEnginePos()
	local Attachment = self:GetAttachment(self:LookupAttachment("vehicle_engine"))
	local pos = self:GetPos()

	if Attachment then
		pos = Attachment.Pos
	end

	if self.EnginePos == nil then
		local vehiclelist = list.Get("simfphys_vehicles")[self:GetSpawn_List()]

		if vehiclelist then
			self.EnginePos = vehiclelist.Members.EnginePos or false
		else
			self.EnginePos = false
		end
	elseif isvector(self.EnginePos) then
		pos = self:LocalToWorld(self.EnginePos)
	end

	return pos
end

function ENT:GetRPM()
	local RPM = self.SmoothRPM and self.SmoothRPM or 0

	return RPM
end

function ENT:DamageEffects( selfTable )
	local Pos = self:GetEnginePos()
	local Scale = self:GetCurHealth() / self:GetMaxHealth()
	local smoke = self:OnSmoke() and Scale <= 0.5
	local fire = self:OnFire()

	if selfTable.wasSmoke ~= smoke then
		selfTable.wasSmoke = smoke
		if smoke then
			selfTable.smokesnd = CreateSound(self, "ambient/gas/steam2.wav")
			selfTable.smokesnd:PlayEx(0.2,90)
		else
			if selfTable.smokesnd then
				selfTable.smokesnd:Stop()
			end
		end
	end

	if selfTable.wasFire ~= fire then
		selfTable.wasFire = fire
		if fire then
			self:EmitSound( "ambient/fire/mtov_flame2.wav" )

			selfTable.firesnd = CreateSound(self, "ambient/fire/fire_small1.wav")
			selfTable.firesnd:Play()
		else
			if selfTable.firesnd then
				selfTable.firesnd:Stop()
			end
		end
	end

	if smoke and Scale <= 0.5 then
		local effectdata = EffectData()
		    effectdata:SetOrigin( Pos )
            effectdata:SetEntity( self )
        util.Effect( "simfphys_engine_smoke", effectdata )
	end

	if fire then
		local effectdata = EffectData()
		effectdata:SetOrigin(Pos)
		effectdata:SetEntity(self)
		util.Effect("simfphys_engine_fire", effectdata)
	end
end

function ENT:ManageEffects( Active, fThrottle, LimitRPM, selfTable )
	self:DamageEffects( selfTable )

	Active = Active and self:GetFlyWheelRPM() ~= 0
	if not Active then return end
	if not selfTable.ExhaustPositions then return end

	local Scale = fThrottle * ( 0.2 + math.min( self:GetRPM() / LimitRPM, 1 ) * 0.8 ) ^ 2

	for i = 1, #selfTable.ExhaustPositions do
		local positions = selfTable.ExhaustPositions[i]
		if positions.OnBodyGroups then
			if self:BodyGroupIsValid(positions.OnBodyGroups) then
				local effectdata = EffectData()
				effectdata:SetOrigin(positions.pos)
				effectdata:SetAngles(positions.ang)
				effectdata:SetMagnitude(Scale)
				effectdata:SetEntity(self)
				util.Effect("simfphys_exhaust", effectdata)
			end
		else
			local effectdata = EffectData()
			effectdata:SetOrigin(positions.pos)
			effectdata:SetAngles(positions.ang)
			effectdata:SetMagnitude(Scale)
			effectdata:SetEntity(self)
			util.Effect("simfphys_exhaust", effectdata)
		end
	end
end

function ENT:ManageSounds(Active, fThrottle, LimitRPM)
	local selfTable = self:GetTable()
	local FlyWheelRPM = self:GetFlyWheelRPM()
	Active = Active and ( FlyWheelRPM ~= 0 )
	local IdleRPM = self:GetIdleRPM()
	local IsCruise = self:GetIsCruiseModeOn()

	local CurDist = ( LocalPlayer():GetPos() - self:GetPos() ):Length()
	local Throttle = IsCruise and math.Clamp(self:GetThrottle() ^ 3,0.01,0.7) or fThrottle
	local Gear = self:GetGear()
	local Clutch = self:GetClutch()
	local FadeRPM = LimitRPM * 0.5
	local FT = FrameTime()
	local Rate = 3.33 * FT
	selfTable.FadeThrottle = selfTable.FadeThrottle + math.Clamp(Throttle - selfTable.FadeThrottle, -Rate, Rate)
	selfTable.PitchOffset = selfTable.PitchOffset + ((CurDist - selfTable.OldDist) * 0.23 - selfTable.PitchOffset) * 0.5
	selfTable.OldDist = CurDist
	selfTable.SmoothRPM = selfTable.SmoothRPM + math.Clamp(FlyWheelRPM - selfTable.SmoothRPM, -0.972 * FT * LimitRPM, 1.66 * FT * LimitRPM)
	selfTable.OldThrottle2 = selfTable.OldThrottle2 or 0

	if Throttle ~= selfTable.OldThrottle2 then
		selfTable.OldThrottle2 = Throttle

		if Throttle == 0 then
			if selfTable.SmoothRPM > LimitRPM * 0.6 then
				self:Backfire()
			end
		end
	end

	if self:GetRevlimiter() and LimitRPM > 2500 then
		if selfTable.SmoothRPM >= LimitRPM - 200 and selfTable.FadeThrottle > 0 then
			selfTable.SmoothRPM = selfTable.SmoothRPM - 0.2 * LimitRPM
			selfTable.FadeThrottle = 0.2
			self:Backfire()
		end
	end

	if Active ~= selfTable.OldActive then
		local preset = self:GetEngineSoundPreset()
		local UseGearResetter = self:SetSoundPreset(preset, selfTable)
		selfTable.SoundMode = UseGearResetter and 2 or 1
		selfTable.OldActive = Active

		if Active then
			local MaxHealth = self:GetMaxHealth()
			local Health = self:GetCurHealth()

			if Health <= MaxHealth * 0.6 then
				selfTable.DamageSnd:PlayEx(0, 0)
			end

			if selfTable.SoundMode == 2 then
				selfTable.HighRPM = CreateSound(self, selfTable.EngineSounds["HighRPM"])
				selfTable.LowRPM = CreateSound(self, selfTable.EngineSounds["LowRPM"])
				selfTable.Idle = CreateSound(self, selfTable.EngineSounds["Idle"])
				selfTable.HighRPM:PlayEx(0, 0)
				selfTable.LowRPM:PlayEx(0, 0)
				selfTable.Idle:PlayEx(0, 0)
			else
				local IdleSound = selfTable.EngineSounds["IdleSound"]
				local LowSound = selfTable.EngineSounds["LowSound"]
				local HighSound = selfTable.EngineSounds["HighSound"]
				local ThrottleSound = selfTable.EngineSounds["ThrottleSound"]

				if IdleSound then
					selfTable.Idle = CreateSound(self, IdleSound)
					selfTable.Idle:PlayEx(0, 0)
				end

				if LowSound then
					selfTable.LowRPM = CreateSound(self, LowSound)
					selfTable.LowRPM:PlayEx(0, 0)
				end

				if HighSound then
					selfTable.HighRPM = CreateSound(self, HighSound)
					selfTable.HighRPM:PlayEx(0, 0)
				end

				if ThrottleSound then
					selfTable.Valves = CreateSound(self, ThrottleSound)
					selfTable.Valves:PlayEx(0, 0)
				end
			end
		else
			self:SaveStopSounds()
		end
	end

	if Active then
		local Volume = 0.25 + 0.25 * (selfTable.SmoothRPM / LimitRPM) ^ 1.5 + selfTable.FadeThrottle * 0.5
		local Pitch = math.Clamp((20 + selfTable.SmoothRPM / 50 - selfTable.PitchOffset) * selfTable.PitchMulAll, 0, 255)

		if selfTable.DamageSnd then
			selfTable.DamageSnd:ChangeVolume(selfTable.SmoothRPM / LimitRPM * 0.6 ^ 1.5)
			selfTable.DamageSnd:ChangePitch(100)
		end

		if selfTable.SoundMode == 2 then
			if selfTable.FadeThrottle ~= selfTable.OldThrottle then
				selfTable.OldThrottle = selfTable.FadeThrottle

				if selfTable.FadeThrottle == 0 and Clutch == 0 then
					if selfTable.SmoothRPM >= FadeRPM then
						if IsCruise ~= true then
							if selfTable.LowRPM then
								selfTable.LowRPM:Stop()
							end

							selfTable.LowRPM = CreateSound(self, selfTable.EngineSounds["RevDown"])
							selfTable.LowRPM:PlayEx(0, 0)
						end
					end
				end
			end

			if Gear ~= selfTable.OldGear then
				if selfTable.SmoothRPM >= FadeRPM and Gear > 3 then
					if Clutch ~= 1 then
						if selfTable.OldGear < Gear then
							if selfTable.HighRPM then
								selfTable.HighRPM:Stop()
							end

							selfTable.HighRPM = CreateSound(self, selfTable.EngineSounds["ShiftUpToHigh"])
							selfTable.HighRPM:PlayEx(0, 0)

							if selfTable.SmoothRPM > LimitRPM * 0.6 then
								if math.random(0, 4) >= 3 then
									timer.Simple(0.4, function()
										if not self:IsValid() then return end
										self:Backfire()
									end)
								end
							end
						else
							if selfTable.FadeThrottle > 0 then
								if selfTable.HighRPM then
									selfTable.HighRPM:Stop()
								end

								selfTable.HighRPM = CreateSound(self, selfTable.EngineSounds["ShiftDownToHigh"])
								selfTable.HighRPM:PlayEx(0, 0)
							end
						end
					end
				else
					if Clutch ~= 1 then
						if selfTable.OldGear > Gear and selfTable.FadeThrottle > 0 and Gear >= 3 then
							if selfTable.HighRPM then
								selfTable.HighRPM:Stop()
							end

							selfTable.HighRPM = CreateSound(self, selfTable.EngineSounds["ShiftDownToHigh"])
							selfTable.HighRPM:PlayEx(0, 0)
						else
							if selfTable.HighRPM then
								selfTable.HighRPM:Stop()
							end

							if selfTable.LowRPM then
								selfTable.LowRPM:Stop()
							end

							selfTable.HighRPM = CreateSound(self, selfTable.EngineSounds["HighRPM"])
							selfTable.LowRPM = CreateSound(self, selfTable.EngineSounds["LowRPM"])
							selfTable.HighRPM:PlayEx(0, 0)
							selfTable.LowRPM:PlayEx(0, 0)
						end
					end
				end

				selfTable.OldGear = Gear
			end

			selfTable.Idle:ChangeVolume(math.Clamp(math.min(selfTable.SmoothRPM / IdleRPM * 3, 1.5 + selfTable.FadeThrottle * 0.5) * 0.7 - selfTable.SmoothRPM / 2000, 0, 1))
			selfTable.Idle:ChangePitch(math.Clamp(Pitch * 3, 0, 255))
			selfTable.LowRPM:ChangeVolume(math.Clamp(Volume - (selfTable.SmoothRPM - 2000) / 2000 * selfTable.FadeThrottle, 0, 1))
			selfTable.LowRPM:ChangePitch(math.Clamp(Pitch * selfTable.PitchMulLow, 0, 255))
			local hivol = math.max((selfTable.SmoothRPM - 2000) / 2000, 0) * Volume
			selfTable.HighRPM:ChangeVolume(selfTable.FadeThrottle < 0.4 and hivol * selfTable.FadeThrottle or hivol * selfTable.FadeThrottle * 2.5)
			selfTable.HighRPM:ChangePitch(math.Clamp(Pitch * selfTable.PitchMulHigh, 0, 255))
		else
			if Gear ~= selfTable.OldGear then
				if selfTable.SmoothRPM >= FadeRPM and Gear > 3 then
					if Clutch ~= 1 then
						if selfTable.OldGear < Gear then
							if selfTable.SmoothRPM > LimitRPM * 0.6 then
								if math.random(0, 4) >= 3 then
									timer.Simple(0.4, function()
										if not self:IsValid() then return end
										self:Backfire()
									end)
								end
							end
						end
					end
				end

				selfTable.OldGear = Gear
			end

			local IdlePitch = selfTable.Idle_PitchMul
			selfTable.Idle:ChangeVolume(math.Clamp(math.min(selfTable.SmoothRPM / IdleRPM * 3, 1.5 + selfTable.FadeThrottle * 0.5) * 0.7 - selfTable.SmoothRPM / 2000, 0, 1))
			selfTable.Idle:ChangePitch(math.Clamp(Pitch * 3 * IdlePitch, 0, 255))
			local LowPitch = selfTable.Mid_PitchMul
			local LowVolume = selfTable.Mid_VolumeMul
			local LowFadeOutRPM = LimitRPM * selfTable.Mid_FadeOutRPMpercent / 100
			local LowFadeOutRate = LimitRPM * selfTable.Mid_FadeOutRate
			selfTable.LowRPM:ChangeVolume(math.Clamp((Volume - math.Clamp((selfTable.SmoothRPM - LowFadeOutRPM) / LowFadeOutRate, 0, 1)) * LowVolume, 0, 1))
			selfTable.LowRPM:ChangePitch(math.Clamp(Pitch * LowPitch, 0, 255))
			local HighPitch = selfTable.High_PitchMul
			local HighVolume = selfTable.High_VolumeMul
			local HighFadeInRPM = LimitRPM * selfTable.High_FadeInRPMpercent / 100
			local HighFadeInRate = LimitRPM * selfTable.High_FadeInRate
			selfTable.HighRPM:ChangeVolume(math.Clamp(math.Clamp((selfTable.SmoothRPM - HighFadeInRPM) / HighFadeInRate, 0, Volume) * HighVolume, 0, 1))
			selfTable.HighRPM:ChangePitch(math.Clamp(Pitch * HighPitch, 0, 255))
			local ThrottlePitch = selfTable.Throttle_PitchMul
			local ThrottleVolume = selfTable.Throttle_VolumeMul
			selfTable.Valves:ChangeVolume(math.Clamp((selfTable.SmoothRPM - 2000) / 2000, 0, Volume) * (0.2 + 0.15 * selfTable.FadeThrottle) * ThrottleVolume)
			selfTable.Valves:ChangePitch(math.Clamp(Pitch * ThrottlePitch, 0, 255))
		end
	end
end

function ENT:Backfire(damaged)
	if not self:GetBackFire() and not damaged then return end
	if not self.ExhaustPositions then return end
	local expos = self.ExhaustPositions

	for i = 1, #expos do
		if math.random(1, 3) >= 2 or damaged then
			local Pos = expos[i].pos
			local Ang = expos[i].ang - Angle(90, 0, 0)

			if expos[i].OnBodyGroups then
				if self:BodyGroupIsValid(expos[i].OnBodyGroups) then
					local effectdata = EffectData()
					effectdata:SetOrigin(Pos)
					effectdata:SetAngles(Ang)
					effectdata:SetEntity(self)
					effectdata:SetFlags(damaged and 1 or 0)
					util.Effect("simfphys_backfire", effectdata)
				end
			else
				local effectdata = EffectData()
				effectdata:SetOrigin(Pos)
				effectdata:SetAngles(Ang)
				effectdata:SetEntity(self)
				effectdata:SetFlags(damaged and 1 or 0)
				util.Effect("simfphys_backfire", effectdata)
			end
		end
	end
end

function ENT:Draw()
	self:DrawModel()
end

local blank = {}
function ENT:SetSoundPreset(index, selfTable)
	local vehiclelist = list.Get("simfphys_vehicles")[self:GetSpawn_List()] or false
	local Members = vehiclelist and vehiclelist.Members or blank

	if vehiclelist then
		if not selfTable.ExhaustPositions then
			selfTable.ExhaustPositions = Members.ExhaustPositions
		end
	end

	if index == -1 then
		if vehiclelist then
			local soundoverride = self:GetSoundoverride()
			local data = string.Explode(",", soundoverride)

			if soundoverride ~= "" and data[1] == "1" then
				selfTable.EngineSounds["Idle"] = data[4]
				selfTable.EngineSounds["LowRPM"] = data[6]
				selfTable.EngineSounds["HighRPM"] = data[2]
				selfTable.EngineSounds["RevDown"] = data[8]
				selfTable.EngineSounds["ShiftUpToHigh"] = data[10]
				selfTable.EngineSounds["ShiftDownToHigh"] = data[9]
				selfTable.PitchMulLow = data[7]
				selfTable.PitchMulHigh = data[3]
				selfTable.PitchMulAll = data[5]
			else
				local idle = Members.snd_idle or ""
				local low = Members.snd_low or ""
				local mid = Members.snd_mid or ""
				local revdown = Members.snd_low_revdown or ""
				local gearup = Members.snd_mid_gearup or ""
				local geardown = Members.snd_mid_geardown or ""
				selfTable.EngineSounds["Idle"] = idle ~= "" and idle or false
				selfTable.EngineSounds["LowRPM"] = low ~= "" and low or false
				selfTable.EngineSounds["HighRPM"] = mid ~= "" and mid or false
				selfTable.EngineSounds["RevDown"] = revdown ~= "" and revdown or low
				selfTable.EngineSounds["ShiftUpToHigh"] = gearup ~= "" and gearup or mid
				selfTable.EngineSounds["ShiftDownToHigh"] = geardown ~= "" and geardown or gearup
				selfTable.PitchMulLow = Members.snd_low_pitch or 1
				selfTable.PitchMulHigh = Members.snd_mid_pitch or 1
				selfTable.PitchMulAll = Members.snd_pitch or 1
			end
		else
			local ded = "common/bugreporter_failed.wav"
			selfTable.EngineSounds["Idle"] = ded
			selfTable.EngineSounds["LowRPM"] = ded
			selfTable.EngineSounds["HighRPM"] = ded
			selfTable.EngineSounds["RevDown"] = ded
			selfTable.EngineSounds["ShiftUpToHigh"] = ded
			selfTable.EngineSounds["ShiftDownToHigh"] = ded
			selfTable.PitchMulLow = 0
			selfTable.PitchMulHigh = 0
			selfTable.PitchMulAll = 0
		end

		if selfTable.EngineSounds["Idle"] ~= false and selfTable.EngineSounds["LowRPM"] ~= false and selfTable.EngineSounds["HighRPM"] ~= false then
			return true
		else
			self:SetSoundPreset(0, selfTable)

			return false
		end
	end

	if index == 0 then
		local soundoverride = self:GetSoundoverride()
		local data = string.Explode(",", soundoverride)

		if soundoverride ~= "" and data[1] ~= "1" then
			selfTable.EngineSounds["IdleSound"] = data[1]
			selfTable.Idle_PitchMul = data[2]
			selfTable.EngineSounds["LowSound"] = data[3]
			selfTable.Mid_PitchMul = data[4]
			selfTable.Mid_VolumeMul = data[5]
			selfTable.Mid_FadeOutRPMpercent = data[6]
			selfTable.Mid_FadeOutRate = data[7]
			selfTable.EngineSounds["HighSound"] = data[8]
			selfTable.High_PitchMul = data[9]
			selfTable.High_VolumeMul = data[10]
			selfTable.High_FadeInRPMpercent = data[11]
			selfTable.High_FadeInRate = data[12]
			selfTable.EngineSounds["ThrottleSound"] = data[13]
			selfTable.Throttle_PitchMul = data[14]
			selfTable.Throttle_VolumeMul = data[15]
		else
			selfTable.EngineSounds["IdleSound"] = Members.Sound_Idle or "simulated_vehicles/misc/e49_idle.wav"
			selfTable.Idle_PitchMul = Members.Sound_IdlePitch or 1
			selfTable.EngineSounds["LowSound"] = Members.Sound_Mid or "simulated_vehicles/misc/gto_onlow.wav"
			selfTable.Mid_PitchMul = Members.Sound_MidPitch or 1
			selfTable.Mid_VolumeMul = Members.Sound_MidVolume or 0.75
			selfTable.Mid_FadeOutRPMpercent = Members.Sound_MidFadeOutRPMpercent or 68
			selfTable.Mid_FadeOutRate = Members.Sound_MidFadeOutRate or 0.4
			selfTable.EngineSounds["HighSound"] = Members.Sound_High or "simulated_vehicles/misc/nv2_onlow_ex.wav"
			selfTable.High_PitchMul = Members.Sound_HighPitch or 1
			selfTable.High_VolumeMul = Members.Sound_HighVolume or 1
			selfTable.High_FadeInRPMpercent = Members.Sound_HighFadeInRPMpercent or 26.6
			selfTable.High_FadeInRate = Members.Sound_HighFadeInRate or 0.266
			selfTable.EngineSounds["ThrottleSound"] = Members.Sound_Throttle or "simulated_vehicles/valve_noise.wav"
			selfTable.Throttle_PitchMul = Members.Sound_ThrottlePitch or 0.65
			selfTable.Throttle_VolumeMul = Members.Sound_ThrottleVolume or 1
		end

		selfTable.PitchMulLow = 1
		selfTable.PitchMulHigh = 1
		selfTable.PitchMulAll = 1

		return false
	end

	if index > 0 then
		local clampindex = math.Clamp(index, 1, #simfphys.SoundPresets)
		selfTable.EngineSounds["Idle"] = simfphys.SoundPresets[clampindex][1]
		selfTable.EngineSounds["LowRPM"] = simfphys.SoundPresets[clampindex][2]
		selfTable.EngineSounds["HighRPM"] = simfphys.SoundPresets[clampindex][3]
		selfTable.EngineSounds["RevDown"] = simfphys.SoundPresets[clampindex][4]
		selfTable.EngineSounds["ShiftUpToHigh"] = simfphys.SoundPresets[clampindex][5]
		selfTable.EngineSounds["ShiftDownToHigh"] = simfphys.SoundPresets[clampindex][6]
		selfTable.PitchMulLow = simfphys.SoundPresets[clampindex][7]
		selfTable.PitchMulHigh = simfphys.SoundPresets[clampindex][8]
		selfTable.PitchMulAll = simfphys.SoundPresets[clampindex][9]

		return true
	end

	return false
end

function ENT:GetVehicleInfo()
	return self.VehicleInfo
end

function ENT:SaveStopSounds()
	if self.HighRPM then
		self.HighRPM:Stop()
	end

	if self.LowRPM then
		self.LowRPM:Stop()
	end

	if self.Idle then
		self.Idle:Stop()
	end

	if self.Valves then
		self.Valves:Stop()
	end

	if self.DamageSnd then
		self.DamageSnd:Stop()
	end
end

function ENT:OnRemove()
	self:SaveStopSounds()

	if self.smokesnd then
		self.smokesnd:Stop()
	end

	if self.firesnd then
		self.firesnd:Stop()
	end
end