local function lockControls( bLock )
	net.Start( "simfphys_blockcontrols" )
		net.WriteBool( bLock )
	net.SendToServer()
end

hook.Add( "OnContextMenuOpen", "simfphys_seatswitching_cmenuopen", function()
	lockControls( true )
end )

hook.Add( "OnContextMenuClose", "simfphys_seatswitching_cmenuclose", function()
	lockControls( false )
end )

hook.Add( "OnSpawnMenuOpen", "simfphys_seatswitching_menuopen", function()
	lockControls( true )
end )

hook.Add( "OnSpawnMenuClose", "simfphys_seatswitching_menuclose", function()
	lockControls( false )
end )

hook.Add( "FinishChat", "simfphys_seatswitching_chatend", function()
	lockControls( false )
end )

hook.Add( "StartChat", "simfphys_seatswitching_chatstart", function()
	lockControls( true )
end )
