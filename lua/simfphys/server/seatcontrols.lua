util.AddNetworkString( "simfphys_mousesteer" )
util.AddNetworkString( "simfphys_blockcontrols" )

net.Receive( "simfphys_mousesteer", function( _, ply )
	if not ply:IsDrivingSimfphys() then return end

	local vehicle = net.ReadEntity()
	local Steer = net.ReadInt( 9 )

	Steer = Steer / 255

	if not vehicle:IsValid() or ply:GetSimfphys() ~= vehicle:GetParent() then return end

	vehicle.ms_Steer = Steer
end )

net.Receive( "simfphys_blockcontrols", function( _, ply )
	if not ply:IsValid() then return end

	ply.blockcontrols = net.ReadBool()
end )

hook.Add( "PlayerButtonDown", "!!!simfphysButtonDown", function( ply, button )
	local vehicle = ply:GetSimfphys()
	if not vehicle:IsValid() then return end
	
	if button == KEY_1 then
		if ply == vehicle:GetDriver() then
			if vehicle:GetIsVehicleLocked() then
				vehicle:UnLock()
			else
				vehicle:Lock()
			end
		else
			if not vehicle:GetDriver():IsValid() then
				ply:ExitVehicle()

				local DriverSeat = vehicle:GetDriverSeat()
				
				if DriverSeat:IsValid() then
					timer.Simple( FrameTime(), function()
						if not vehicle:IsValid() or not ply:IsValid() then return end
						if vehicle:GetDriver():IsValid() or not DriverSeat:IsValid() then return end
						
						ply:EnterVehicle( DriverSeat )

						timer.Simple( FrameTime() * 2, function()
							if not ply:IsValid() or not vehicle:IsValid() then return end
							ply:SetEyeAngles( Angle( 0, vehicle:GetAngles().y, 0 ) )
						end)
					end)
				end
			end
		end
	else
		for _, Pod in pairs( vehicle:GetPassengerSeats() ) do
			if Pod:IsValid() and Pod:GetNWInt( "pPodIndex", 3 ) == simfphys.pSwitchKeys[ button ] and not Pod:GetDriver():IsValid() then
				ply:ExitVehicle()
					
				timer.Simple( FrameTime(), function()
					if not Pod:IsValid() or not ply:IsValid() then return end
					if Pod:GetDriver():IsValid() then return end
							
					ply:EnterVehicle( Pod )
				end)
			end
		end
	end
end )
