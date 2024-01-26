local math = math

function ENT:WheelOnGround()
	self.FrontWheelPowered = self:GetPowerDistribution() ~= 1
	self.RearWheelPowered = self:GetPowerDistribution() ~= -1
	
	local Wheels = self.Wheels
	for i = 1, #Wheels do
		local Wheel = Wheels[i]		
		if Wheel:IsValid() then
			local dmgMul = Wheel:GetDamaged() and 0.5 or 1
			local surfacemul = simfphys.TractionData[Wheel:GetSurfaceMaterial():lower()]

			self.VehicleData[ "SurfaceMul_" .. i ] = (surfacemul and math.max(surfacemul,0.001) or 1) * dmgMul

			local WheelPos = self:LogicWheelPos( i )

			local WheelRadius = WheelPos.IsFrontWheel and self.FrontWheelRadius or self.RearWheelRadius
			local startpos = Wheel:GetPos()
			local dir = -self.Up
			local len = WheelRadius + math.Clamp(-self.Vel.z / 50,2.5,6)
			local HullSize = Vector(WheelRadius,WheelRadius,0)
			local tr = util.TraceHull( {
				start = startpos,
				endpos = startpos + dir * len,
				maxs = HullSize,
				mins = -HullSize,
				filter = self.VehicleData["filter"]
			} )

			if tr.Hit then
				self.VehicleData[ "onGround_" .. i ] = 1
				Wheel:SetSpeed( Wheel.FX )
				Wheel:SetSkidSound( Wheel.skid )
				Wheel:SetSurfaceMaterial( util.GetSurfacePropName( tr.SurfaceProps ) )
				Wheel:SetOnGround( true )
			else
				self.VehicleData[ "onGround_" .. i ] = 0
				Wheel:SetOnGround( false )
			end
		end
	end

	local FrontOnGround = math.max(self.VehicleData[ "onGround_1" ],self.VehicleData[ "onGround_2" ])
	local RearOnGround = math.max(self.VehicleData[ "onGround_3" ],self.VehicleData[ "onGround_4" ],self.VehicleData[ "onGround_5" ],self.VehicleData[ "onGround_6" ])

	self.DriveWheelsOnGround = math.max(self.FrontWheelPowered and FrontOnGround or 0,self.RearWheelPowered and RearOnGround or 0)
end

function ENT:SimulateAirControls(tilt_forward,tilt_back,tilt_left,tilt_right)
	if self:IsDriveWheelsOnGround() then return end

	if hook.Run( "simfphysAirControl", self, tilt_forward, tilt_back, tilt_left, tilt_right) then return end

	local PObj = self:GetPhysicsObject()

	local TiltForce = ((self.Right * (tilt_right - tilt_left) * 1.8) + (self.Forward * (tilt_forward - tilt_back) * 6)) * math.acos( math.Clamp( self.Up:Dot(Vector(0,0,1)) ,-1,1) ) * (180 / math.pi) * self.Mass
	PObj:ApplyForceOffset( TiltForce, PObj:GetMassCenter() + self.Up )
	PObj:ApplyForceOffset( -TiltForce, PObj:GetMassCenter() - self.Up )
end

function ENT:SimulateEngine(IdleRPM,LimitRPM,Powerbandstart,Powerbandend,c_time)
	local PObj = self:GetPhysicsObject()

	local IsRunning = self:EngineActive()
	local Throttle = self:GetThrottle()

	local selftable = self:GetTable()
	if not self:IsDriveWheelsOnGround() then
		selftable.Clutch = 1
	end

	if selftable.Gears[selftable.CurrentGear] == 0 then
		selftable.GearRatio = 1
		selftable.Clutch = 1
		selftable.HandBrake = selftable.HandBrake + (selftable.HandBrakePower - selftable.HandBrake) * 0.2
	else
		selftable.GearRatio = selftable.Gears[selftable.CurrentGear] * self:GetDiffGear()
	end

	self:SetClutch( selftable.Clutch )
	local InvClutch = 1 - selftable.Clutch

	local GearedRPM = selftable.WheelRPM / math.abs(selftable.GearRatio)

	local MaxTorque = self:GetMaxTorque()

	local DesRPM = Lerp(InvClutch, math.max(IdleRPM + (LimitRPM - IdleRPM) * Throttle,0), GearedRPM )
	local Drag = (MaxTorque * (math.max( selftable.EngineRPM - IdleRPM, 0) / Powerbandend) * ( 1 - Throttle) / 0.15) * InvClutch

	local TurboCharged = self:GetTurboCharged()
	local SuperCharged = self:GetSuperCharged()
	local boost = (TurboCharged and self:SimulateTurbo(Powerbandend) or 0) * 0.3 + (SuperCharged and self:SimulateBlower(Powerbandend) or 0)

	if self:GetCurHealth() <= self:GetMaxHealth() * 0.3 then
		MaxTorque = MaxTorque * (self:GetCurHealth() / (self:GetMaxHealth() * 0.3))
	end

	selftable.EngineRPM = math.Clamp(selftable.EngineRPM + math.Clamp(DesRPM - selftable.EngineRPM,-math.max(selftable.EngineRPM / 15, 1 ),math.max(-selftable.RpmDiff / 1.5 * InvClutch + (selftable.Torque * 5) / 0.15 * selftable.Clutch, 1)) + selftable.RPM_DIFFERENCE * Throttle,0,LimitRPM) * selftable.EngineIsOn
	selftable.Torque = (Throttle + boost) * math.max(MaxTorque * math.min(selftable.EngineRPM / Powerbandstart, (LimitRPM - selftable.EngineRPM) / (LimitRPM - Powerbandend),1), 0)
	self:SetFlyWheelRPM( math.min(selftable.EngineRPM + selftable.exprpmdiff * 2 * InvClutch,LimitRPM) )

	selftable.RpmDiff = selftable.EngineRPM - GearedRPM

	local signGearRatio = ((selftable.GearRatio > 0) and 1 or 0) + ((selftable.GearRatio < 0) and -1 or 0)
	local signThrottle = (Throttle > 0) and 1 or 0
	local signSpeed = ((selftable.ForwardSpeed > 0) and 1 or 0) + ((selftable.ForwardSpeed < 0) and -1 or 0)

	local TorqueDiff = (selftable.RpmDiff / LimitRPM) * 0.15 * selftable.Torque
	local EngineBrake = (signThrottle == 0) and math.min( selftable.EngineRPM * (selftable.EngineRPM / LimitRPM) ^ 2 / 60 * signSpeed, 100 ) or 0

	local GearedPower = ((selftable.ThrottleDelay <= c_time and (selftable.Torque + TorqueDiff) * signThrottle * signGearRatio or 0) - EngineBrake) / math.abs(selftable.GearRatio) / 50

	selftable.EngineTorque = IsRunning and GearedPower * InvClutch or 0

	if not self:GetDoNotStall() then
		if IsRunning then
			if selftable.EngineRPM <= IdleRPM * 0.2 then
				selftable.CurrentGear = 2
				self:StallAndRestart()
			end
		end
	end

	if simfphys.Fuel then
		local FuelUse = (Throttle * 0.3 + 0.7) * ((selftable.EngineRPM / LimitRPM) * MaxTorque + selftable.Torque) / 1500000
		local Fuel = self:GetFuel()
		self:SetFuel( Fuel - FuelUse * (1 / simfphys.FuelMul) )

		selftable.UsedFuel = selftable.UsedFuel and (selftable.UsedFuel + FuelUse) or 0
		selftable.CheckUse = selftable.CheckUse or 0
		if selftable.CheckUse < CurTime() then
			selftable.CheckUse = CurTime() + 1
			self:SetFuelUse( selftable.UsedFuel * 60 )
			selftable.UsedFuel = 0
		end

		if Fuel <= 0 and IsRunning then
			self:StopEngine()
		end
	else
		self:SetFuelUse( -1 )
	end

	local ReactionForce = (selftable.EngineTorque * 2 - math.Clamp(selftable.ForwardSpeed,-selftable.Brake,selftable.Brake)) * selftable.DriveWheelsOnGround
	local BaseMassCenter = PObj:GetMassCenter()
	local dt_mul = math.max( math.min(self:GetPowerDistribution() + 0.5,1),0)

	PObj:ApplyForceOffset( -selftable.Forward * selftable.Mass * ReactionForce, BaseMassCenter + selftable.Up * dt_mul )
	PObj:ApplyForceOffset( selftable.Forward * selftable.Mass * ReactionForce, BaseMassCenter - selftable.Up * dt_mul )
end

function ENT:SimulateTransmission(k_throttle,k_brake,k_fullthrottle,k_clutch,k_handbrake,k_gearup,k_geardown,isauto,IdleRPM,Powerbandstart,Powerbandend,shiftmode,cruisecontrol,curtime)
	local selftable = self:GetTable()

	local GearsCount = #selftable.Gears
	local cruiseThrottle = math.min( math.max(selftable.cc_speed - math.abs(selftable.ForwardSpeed),0) / 10 ^ 2, 1)

	if isnumber(selftable.ForceTransmission) then
		isauto = selftable.ForceTransmission <= 1
	end

	if not isauto then
		selftable.Brake = self:GetBrakePower() * math.max( k_brake, selftable.PressedKeys["joystick_brake"] )
		selftable.HandBrake = selftable.HandBrakePower * k_handbrake
		selftable.Clutch = math.max( k_clutch, k_handbrake, selftable.PressedKeys["joystick_clutch"] )

		local AutoThrottle = self:EngineActive() and ((selftable.EngineRPM < IdleRPM) and (IdleRPM - selftable.EngineRPM) / IdleRPM or 0) or 0
		local Throttle = cruisecontrol and cruiseThrottle or ( math.max( (0.5 + 0.5 * k_fullthrottle) * k_throttle, selftable.PressedKeys["joystick_throttle"] ) + AutoThrottle)
		self:SetThrottle( Throttle  )

		if k_gearup ~= selftable.GearUpPressed then
			selftable.GearUpPressed = k_gearup

			if k_gearup == 1 then

				if selftable.CurrentGear ~= GearsCount then
					selftable.ThrottleDelay = curtime + 0.4 - 0.4 * k_clutch
				end

				selftable.CurrentGear = math.Clamp(selftable.CurrentGear + 1,1,GearsCount)
			end
		end

		if k_geardown ~= selftable.GearDownPressed then
			selftable.GearDownPressed = k_geardown

			if k_geardown == 1 then

				selftable.CurrentGear = math.Clamp(selftable.CurrentGear - 1,1,GearsCount)

				if selftable.CurrentGear == 1 then
					selftable.ThrottleDelay = curtime + 0.25
				end
			end
		end
	else

		local throttleMod = 0.5 + 0.5 * k_fullthrottle
		local throttleForward = math.max( k_throttle * throttleMod, selftable.PressedKeys["joystick_throttle"] )
		local throttleReverse = math.max( k_brake * throttleMod, selftable.PressedKeys["joystick_brake"] )
		local throttleStanding = math.max( k_throttle * throttleMod, k_brake * throttleMod, selftable.PressedKeys["joystick_brake"], selftable.PressedKeys["joystick_throttle"] )
		local inputThrottle = selftable.ForwardSpeed >= 50 and throttleForward or ((selftable.ForwardSpeed < 50 and selftable.ForwardSpeed > -350) and throttleStanding or throttleReverse)

		local Throttle = cruisecontrol and cruiseThrottle or inputThrottle
		local CalcRPM = selftable.EngineRPM - selftable.RPM_DIFFERENCE * Throttle
		self:SetThrottle( Throttle )

		if selftable.CurrentGear <= 3 and Throttle > 0 and selftable.CurrentGear ~= 2 then
			if Throttle < 1 and not cruisecontrol then
				local autoclutch = math.Clamp((Powerbandstart / selftable.EngineRPM) - 0.5,0,1)

				selftable.sm_autoclutch = selftable.sm_autoclutch and (selftable.sm_autoclutch + math.Clamp(autoclutch - selftable.sm_autoclutch,-0.2,0.1) ) or 0
			else
				selftable.sm_autoclutch = (selftable.EngineRPM < IdleRPM + (Powerbandstart - IdleRPM)) and 1 or 0
			end
		else
			selftable.sm_autoclutch = 0
		end

		selftable.Clutch = math.max(selftable.sm_autoclutch,k_handbrake)

		selftable.HandBrake = selftable.HandBrakePower * k_handbrake

		selftable.Brake = self:GetBrakePower() * (selftable.ForwardSpeed >= 0 and math.max(k_brake,selftable.PressedKeys["joystick_brake"]) or math.max(k_throttle,selftable.PressedKeys["joystick_throttle"]))

		if self:IsDriveWheelsOnGround() then
			if selftable.ForwardSpeed >= 50 then
				if selftable.Clutch == 0 then
					local NextGear = selftable.CurrentGear + 1 <= GearsCount and math.min(selftable.CurrentGear + 1,GearsCount) or selftable.CurrentGear
					local NextGearRatio = selftable.Gears[NextGear] * self:GetDiffGear()
					local NextGearRPM = selftable.WheelRPM / math.abs(NextGearRatio)

					local PrevGear = selftable.CurrentGear - 1 <= GearsCount and math.max(selftable.CurrentGear - 1,3) or selftable.CurrentGear
					local PrevGearRatio = selftable.Gears[PrevGear] * self:GetDiffGear()
					local PrevGearRPM = selftable.WheelRPM / math.abs(PrevGearRatio)

					local minThrottle = shiftmode == 1 and 1 or math.max(Throttle,0.5)

					local ShiftUpRPM = Powerbandstart + (Powerbandend - Powerbandstart) * minThrottle
					local ShiftDownRPM = IdleRPM + (Powerbandend - Powerbandstart) * minThrottle

					local CanShiftUp = NextGearRPM > math.max(Powerbandstart * minThrottle,Powerbandstart - IdleRPM) and CalcRPM >= ShiftUpRPM and selftable.CurrentGear < GearsCount
					local CanShiftDown = CalcRPM <= ShiftDownRPM and PrevGearRPM < ShiftDownRPM and selftable.CurrentGear > 3

					if CanShiftUp and selftable.NextShift < curtime then
						selftable.CurrentGear = selftable.CurrentGear + 1
						selftable.NextShift = curtime + 0.5
						selftable.ThrottleDelay = curtime + 0.25
					end

					if CanShiftDown and selftable.NextShift < curtime then
						selftable.CurrentGear = selftable.CurrentGear - 1
						selftable.NextShift = curtime + 0.35
					end

					selftable.CurrentGear = math.Clamp(selftable.CurrentGear,3,GearsCount)
				end

			elseif (selftable.ForwardSpeed < 50 and selftable.ForwardSpeed > -350) then

				selftable.CurrentGear = (k_throttle == 1 and 3 or k_brake == 1 and 1 or selftable.PressedKeys["joystick_throttle"] > 0 and 3 or selftable.PressedKeys["joystick_brake"] > 0 and 1) or 3
				selftable.Brake = self:GetBrakePower() * math.max(k_throttle * k_brake,selftable.PressedKeys["joystick_throttle"] * selftable.PressedKeys["joystick_brake"])

			elseif (selftable.ForwardSpeed >= -350) then

				if (Throttle > 0) then
					selftable.Brake = 0
				end

				selftable.CurrentGear = 1
			end

			if (Throttle == 0 and math.abs(selftable.ForwardSpeed) <= 80) then
				selftable.CurrentGear = 2
				selftable.Brake = 0
			end
		end
	end
	self:SetIsBraking( selftable.Brake > 0 )
	self:SetGear( selftable.CurrentGear )
	self:SetHandBrakeEnabled( selftable.HandBrake > 0 or selftable.CurrentGear == 2 )

	if selftable.Clutch == 1 or selftable.CurrentGear == 2 then
		if math.abs(selftable.ForwardSpeed) <= 20 then

			local PObj = self:GetPhysicsObject()
			local TiltForce = selftable.Torque * (-1 + self:GetThrottle() * 2)

			PObj:ApplyForceOffset( selftable.Up * TiltForce, PObj:GetMassCenter() + selftable.Right * 1000 )
			PObj:ApplyForceOffset( -selftable.Up * TiltForce, PObj:GetMassCenter() - selftable.Right * 1000)
		end
	end
end

function ENT:GetTransformedDirection()
	local SteerAngForward = self.Forward:Angle()
	local SteerAngRight = self.Right:Angle()
	local SteerAngForward2 = self.Forward:Angle()
	local SteerAngRight2 = self.Right:Angle()

	SteerAngForward:RotateAroundAxis(-self.Up, self.VehicleData[ "Steer" ])
	SteerAngRight:RotateAroundAxis(-self.Up, self.VehicleData[ "Steer" ])
	SteerAngForward2:RotateAroundAxis(-self.Up, -self.VehicleData[ "Steer" ])
	SteerAngRight2:RotateAroundAxis(-self.Up, -self.VehicleData[ "Steer" ])

	local SteerForward = SteerAngForward:Forward()
	local SteerRight = SteerAngRight:Forward()
	local SteerForward2 = SteerAngForward2:Forward()
	local SteerRight2 = SteerAngRight2:Forward()

	return {Forward = SteerForward,Right = SteerRight,Forward2 = SteerForward2, Right2 = SteerRight2}
end

function ENT:LogicWheelPos( index )
	local IsFront = index == 1 or index == 2
	local IsRight = index == 2 or index == 4 or index == 6

	return {IsFrontWheel = IsFront, IsRightWheel = IsRight}
end

function ENT:SimulateWheels(k_clutch,LimitRPM)
	local Steer = self:GetTransformedDirection()
	local MaxGrip = self:GetMaxTraction()
	local Efficiency = self:GetEfficiency()
	local GripOffset = self:GetTractionBias() * MaxGrip

	local selftable = self:GetTable()

	local VehicleData = selftable.VehicleData
	local Wheels = selftable.Wheels
	for i = 1, #Wheels do
		local Wheel = Wheels[i]
		
		if Wheel:IsValid() then
			local WheelPos = self:LogicWheelPos( i )
			local WheelRadius = WheelPos.IsFrontWheel and selftable.FrontWheelRadius or selftable.RearWheelRadius
			local WheelDiameter = WheelRadius * 2
			local SurfaceMultiplicator = VehicleData[ "SurfaceMul_" .. i ]
			local MaxTraction = (WheelPos.IsFrontWheel and (MaxGrip + GripOffset) or  (MaxGrip - GripOffset)) * SurfaceMultiplicator

			local IsPoweredWheel = (WheelPos.IsFrontWheel and selftable.FrontWheelPowered or not WheelPos.IsFrontWheel and selftable.RearWheelPowered) and 1 or 0

			local Velocity = Wheel:GetVelocity()
			local VelForward = Velocity:GetNormalized()
			local OnGround = VehicleData[ "onGround_" .. i ]

			local Forward = WheelPos.IsFrontWheel and Steer.Forward or selftable.Forward
			local Right = WheelPos.IsFrontWheel and Steer.Right or selftable.Right

			if selftable.CustomWheels then
				if WheelPos.IsFrontWheel then
					Forward = selftable.SteerMaster:IsValid() and Steer.Forward or selftable.Forward
					Right = selftable.SteerMaster:IsValid() and Steer.Right or selftable.Right
				else
					if selftable.SteerMaster2 and selftable.SteerMaster2:IsValid() then
						Forward = Steer.Forward2
						Right = Steer.Right2
					end
				end
			end

			local Ax = math.deg( math.acos( math.Clamp( Forward:Dot(VelForward) ,-1,1) ) )
			local Ay = math.deg( math.asin( math.Clamp( Right:Dot(VelForward) ,-1,1) ) )

			local Fx = math.cos( math.rad( Ax ) ) * Velocity:Length()
			local Fy = math.sin( math.rad( Ay ) ) * Velocity:Length()

			local absFy = math.abs(Fy)
			local absFx = math.abs(Fx)

			local PowerBiasMul = WheelPos.IsFrontWheel and (1 - self:GetPowerDistribution()) * 0.5 or (1 + self:GetPowerDistribution()) * 0.5
			local BrakeForce = math.Clamp(-Fx,-selftable.Brake,selftable.Brake) * SurfaceMultiplicator

			local TorqueConv = selftable.EngineTorque * PowerBiasMul * IsPoweredWheel
			local ForwardForce = TorqueConv + (not WheelPos.IsFrontWheel and math.Clamp(-Fx,-selftable.HandBrake,selftable.HandBrake) or 0) + BrakeForce * 0.5

			local TractionCycle = Vector(math.min(absFy,MaxTraction),ForwardForce,0):Length()

			local GripLoss = math.max(TractionCycle - MaxTraction,0)
			local GripRemaining = math.max(MaxTraction - GripLoss,math.min(absFy / 25,MaxTraction))
			--local GripRemaining = math.max(MaxTraction - GripLoss,math.min(absFy / 25,MaxTraction / 2))

			local signForwardForce = ((ForwardForce > 0) and 1 or 0) + ((ForwardForce < 0) and -1 or 0)
			local signEngineTorque = ((selftable.EngineTorque > 0) and 1 or 0) + ((selftable.EngineTorque < 0) and -1 or 0)

			local Power = ForwardForce * Efficiency - GripLoss * signForwardForce + math.Clamp(BrakeForce * 0.5,-MaxTraction,MaxTraction)

			local Force = -Right * math.Clamp(Fy,-GripRemaining,GripRemaining) + Forward * Power

			local wRad = Wheel:GetDamaged() and Wheel.dRadius or WheelRadius
			local TurnWheel = ((Fx + GripLoss * 35 * signEngineTorque * IsPoweredWheel) / wRad * 1.85) + selftable.EngineRPM / 80 * (1 - OnGround) * IsPoweredWheel * (1 - k_clutch)

			Wheel.FX = Fx
			Wheel.skid = ((MaxTraction - (MaxTraction - Vector(absFy,math.abs(ForwardForce * 10),0):Length())) / MaxTraction) - 10

			local RPM = (absFx / (3.14 * WheelDiameter)) * 52 * OnGround
			local GripLossFaktor = math.Clamp(GripLoss,0,MaxTraction) / MaxTraction

			VehicleData[ "WheelRPM_".. i ] = RPM
			VehicleData[ "GripLossFaktor_".. i ] = GripLossFaktor
			VehicleData[ "Exp_GLF_".. i ] = GripLossFaktor ^ 2
			Wheel:SetGripLoss( GripLossFaktor )

			local WheelOPow = math.abs( selftable.CurrentGear == 1 and math.min( TorqueConv, 0 ) or math.max( TorqueConv, 0 ) ) > 0
			local FrontWheelCanTurn = (WheelOPow and 0 or selftable.Brake) < MaxTraction * 1.75
			local RearWheelCanTurn = (selftable.HandBrake < MaxTraction) and (WheelOPow and 0 or selftable.Brake) < MaxTraction * 2

			if WheelPos.IsFrontWheel then
				if FrontWheelCanTurn then
					VehicleData[ "spin_" .. i ] = VehicleData[ "spin_" .. i ] + TurnWheel
				end
			else
				if RearWheelCanTurn then
					VehicleData[ "spin_" .. i ] = VehicleData[ "spin_" .. i ] + TurnWheel
				end
			end

			if selftable.CustomWheels then
				local GhostEnt = selftable.GhostWheels[i]
				if GhostEnt:IsValid() then
					local Angle = GhostEnt:GetAngles()
					local offsetang = WheelPos.IsFrontWheel and selftable.CustomWheelAngleOffset or (selftable.CustomWheelAngleOffset_R or selftable.CustomWheelAngleOffset)
					local Direction = GhostEnt:LocalToWorldAngles( offsetang ):Forward()
					local TFront = FrontWheelCanTurn and TurnWheel or 0
					local TBack = RearWheelCanTurn and TurnWheel or 0

					local AngleStep = WheelPos.IsFrontWheel and TFront or TBack
					Angle:RotateAroundAxis(Direction, WheelPos.IsRightWheel and AngleStep or -AngleStep)

					selftable.GhostWheels[i]:SetAngles( Angle )
				end
			else
				self:SetPoseParameter(VehicleData[ "pp_spin_" .. i ],VehicleData[ "spin_" .. i ])
			end

			if ( OnGround >= 1 ) and ( not selftable.PhysicsEnabled ) then
				local phys = Wheel:GetPhysicsObject()
				if phys:IsValid() then
					Force:Mul( 185 )
					phys:ApplyForceCenter( Force )
				end
			end
		end
	end

	local target_diff = math.max(LimitRPM * 0.95 - selftable.EngineRPM,0)

	if selftable.FrontWheelPowered and selftable.RearWheelPowered then
		selftable.WheelRPM = math.max(VehicleData[ "WheelRPM_1" ] or 0,VehicleData[ "WheelRPM_2" ] or 0,VehicleData[ "WheelRPM_3" ] or 0,VehicleData[ "WheelRPM_4" ] or 0)
		selftable.RPM_DIFFERENCE = target_diff * math.max(VehicleData[ "GripLossFaktor_1" ] or 0,VehicleData[ "GripLossFaktor_2" ] or 0,VehicleData[ "GripLossFaktor_3" ] or 0,VehicleData[ "GripLossFaktor_4" ] or 0)
		selftable.exprpmdiff = target_diff * math.max(VehicleData[ "Exp_GLF_1" ] or 0,VehicleData[ "Exp_GLF_2" ] or 0,VehicleData[ "Exp_GLF_3" ] or 0,VehicleData[ "Exp_GLF_4" ] or 0)

	elseif not selftable.FrontWheelPowered and selftable.RearWheelPowered then
		selftable.WheelRPM = math.max(VehicleData[ "WheelRPM_3" ] or 0,VehicleData[ "WheelRPM_4" ] or 0)
		selftable.RPM_DIFFERENCE = target_diff * math.max(VehicleData[ "GripLossFaktor_3" ] or 0,VehicleData[ "GripLossFaktor_4" ] or 0)
		selftable.exprpmdiff = target_diff * math.max(VehicleData[ "Exp_GLF_3" ] or 0,VehicleData[ "Exp_GLF_4" ] or 0)

	elseif selftable.FrontWheelPowered and not selftable.RearWheelPowered then
		selftable.WheelRPM = math.max(VehicleData[ "WheelRPM_1" ] or 0,VehicleData[ "WheelRPM_2" ] or 0)
		selftable.RPM_DIFFERENCE = target_diff * math.max(VehicleData[ "GripLossFaktor_1" ] or 0,VehicleData[ "GripLossFaktor_2" ] or 0)
		selftable.exprpmdiff = target_diff * math.max(VehicleData[ "Exp_GLF_1" ] or 0,VehicleData[ "Exp_GLF_2" ] or 0)

	else
		selftable.WheelRPM = 0
		selftable.RPM_DIFFERENCE = 0
		selftable.exprpmdiff = 0
	end
end

function ENT:SimulateTurbo(LimitRPM)
	if not self.Turbo then return end

	local Throttle = self:GetThrottle()

	self.SmoothTurbo = self.SmoothTurbo + math.Clamp(math.min(self.EngineRPM / LimitRPM,1) * 600 * (0.75 + 0.25 * Throttle) - self.SmoothTurbo,-15,15)

	local Volume = math.Clamp( ((self.SmoothTurbo - 300) / 150) ,0, 1) * 0.5
	local Pitch = math.Clamp( self.SmoothTurbo / 7 , 0 , 255)

	local boost = math.Clamp( -0.25 + (self.SmoothTurbo / 500) ^ 5,0,1)

	self.Turbo:ChangeVolume( Volume )
	self.Turbo:ChangePitch( Pitch )

	return boost
end

function ENT:SimulateBlower(LimitRPM)
	if not self.Blower or not self.BlowerWhine then return end

	local Throttle = self:GetThrottle()

	self.SmoothBlower = self.SmoothBlower + math.Clamp(math.min(self.EngineRPM / LimitRPM,1) * 500 - self.SmoothBlower,-20,20)

	local Volume1 = math.Clamp( self.SmoothBlower / 400 * (1 - 0.4 * Throttle) ,0, 1)
	local Volume2 = math.Clamp( self.SmoothBlower / 400 * (0.10 + 0.4 * Throttle) ,0, 1)

	local Pitch1 = 50 + math.Clamp( self.SmoothBlower / 4.5 , 0 , 205)
	local Pitch2 = Pitch1 * 1.2

	local boost = math.Clamp( (self.SmoothBlower / 600) ^ 4 ,0,1)

	self.Blower:ChangeVolume( Volume1 )
	self.Blower:ChangePitch( Pitch1 )

	self.BlowerWhine:ChangeVolume( Volume2 )
	self.BlowerWhine:ChangePitch( Pitch2 )

	return boost
end