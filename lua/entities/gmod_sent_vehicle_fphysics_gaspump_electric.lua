AddCSLuaFile()

ENT.Type	= "anim"
ENT.PrintName	= "gas pump (electric)"
ENT.Category	= "simfphys"

ENT.Spawnable = true
ENT.AdminOnly = false

function ENT:SetupDataTables()
	self:NetworkVar( "Entity",0, "User" )
	self:NetworkVar( "Bool",0, "Active" )
	self:NetworkVar( "Float",0, "FuelUsed" )
	
	if SERVER then
		self:NetworkVarNotify( "Active", self.OnActiveChanged )
	end
end

local function bezier(p0, p1, p2, p3, t)
	local e = p0 + t * (p1 - p0)
	local f = p1 + t * (p2 - p1)
	local g = p2 + t * (p3 - p2)

	local h = e + t * (f - e)
	local i = f + t * (g - f)

	local p = h + t * (i - h)

	return p
end

if CLIENT then 
	local cable = Material( "cable/cable2" )
	local electric_meme = Material( "conquest/energy_collector" )
	
	local function GetDigit( value )
		local fvalue = math.floor(value,0)
		
		local decimal = 1000 + (value - fvalue) * 1000
		
		local digit1 =  fvalue % 10
		local digit2 =  (fvalue - digit1) % 100
		local digit3 = (fvalue - digit1 - digit2) % 1000
		
		local digit4 =  decimal % 10
		local digit5 =  (decimal - digit4) % 100
		local digit6 = (decimal - digit4 - digit5) % 1000
		
		local digits = {
			[1] = math.Round( digit1, 0 ),
			[2] = math.Round( digit2 * .1, 0 ),
			[3] = math.Round( digit3 * .01, 0 ),
			[4] = math.Round( digit5 * .1, 0 ),
			[5] = math.Round( digit6 * .01, 0 ),
		}
		return digits
	end
	
	local color_black = Color( 0, 0, 0, 255 )
	local color_gray = Color( 100, 100, 100, 255 )
	local color_blue = Color( 0, 127, 255, 150 )
	local color_darkgray = Color( 50, 50, 50, 255 )
	local color_lightgray = Color( 200, 200, 200, 255 )

	local v1 = Vector( 10, 0, 45 )
	local a1 = Angle( 0, 90, 90 )
	local v2 = Vector( 0.06, -17.77, 55.48 )
	local v3 = Vector( 8, -17.77, 30 )
	local v4 = Vector( 0, -20, 30 )
	local v5 = Vector( 0.06, -20.3, 37 )

	function ENT:Draw()
		self:DrawModel()
		
		if LocalPlayer():GetPos():DistToSqr(self:GetPos()) > 350000 then return end
		
		local pos = self:LocalToWorld( v1 )
		local ang = self:LocalToWorldAngles( a1 )
		local ply = self:GetUser()
		
		local startPos = self:LocalToWorld( v2 )
		local p2 = self:LocalToWorld( v3 )
		local p3 = self:LocalToWorld( v4 )
		local endPos = self:LocalToWorld( v5 )
		
		if ply:IsValid() then
			local id = ply:LookupAttachment("anim_attachment_rh")
			local attachment = ply:GetAttachment( id )
			
			if not attachment then return end
			
			endPos = (attachment.Pos + attachment.Ang:Forward() * -3 + attachment.Ang:Right() * 2 + attachment.Ang:Up() * -3.5)
			p3 = endPos + attachment.Ang:Right() * 5 - attachment.Ang:Up() * 20
		end
		
		local active = ply:IsValid()
		local de = active and 1 or 2

		render.SetMaterial( cable )
		for i = 1,15 do
			if (not active and i > 1) or active then
				local sp = bezier(startPos, p2, p3, endPos, (i - de) / 15)
				local ep = bezier(startPos, p2, p3, endPos, i / 15)
				render.DrawBeam( sp, ep, 2, 1, 1, color_gray ) 
			end
		end
		
		cam.Start3D2D( self:LocalToWorld( v1 ), self:LocalToWorldAngles( a1 ), 0.1 )
			draw.NoTexture()
			surface.SetDrawColor( 0, 0, 0, 255 )
			surface.DrawRect( -150, -120, 300, 240 )
			
			draw.RoundedBox( 5, -130, -110, 260, 200, color_blue ) 
			draw.RoundedBox( 5, -129, -109, 258, 198, color_darkgray ) 
			
			draw.RoundedBox( 5, -91, -75, 182, 30, color_blue ) 
			draw.RoundedBox( 5, -90, -74, 180, 28, color_darkgray ) 
			draw.RoundedBox( 5, -88, -72, 19, 24, color_black )
			draw.RoundedBox( 5, -68, -72, 19, 24, color_black ) 
			draw.RoundedBox( 5, -48, -72, 19, 24, color_black ) 
			draw.RoundedBox( 5, -28, -72, 19, 24, color_black ) 
			draw.RoundedBox( 5, -8, -72, 19, 24, color_black ) 
			draw.RoundedBox( 5, 12, -72, 76, 24, color_black ) 
			
			surface.SetDrawColor( 0,127,255 )
			surface.SetMaterial( electric_meme )
			surface.DrawTexturedRect( -35, -12, 70, 70 )
		
			draw.SimpleText( "kW/h", "simfphys_gaspump", 50, -70, color_lightgray, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
			
			local kwh = self:GetFuelUsed() * 0.5
			local l_digits = GetDigit( math.Round( kwh, 2) )
			
			draw.SimpleText( l_digits[4], "simfphys_gaspump", 6, -70, color_lightgray, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP )
			draw.SimpleText( l_digits[5], "simfphys_gaspump", -14, -70, color_lightgray, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP )
			draw.SimpleText( ",", "simfphys_gaspump", -26, -65, color_lightgray, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP )
			draw.SimpleText( l_digits[1], "simfphys_gaspump", -34, -70, color_lightgray, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP )
			draw.SimpleText( l_digits[2], "simfphys_gaspump", -54, -70, color_lightgray, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP )
			draw.SimpleText( l_digits[3], "simfphys_gaspump", -74, -70, color_lightgray, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP )
			
			draw.SimpleText( "ELECTRIC", "simfphys_gaspump", 0, -100, color_blue, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
			
		cam.End3D2D()
	end
	return
end
	
function ENT:Use( ply )
	if not self:GetActive() then
		if not ply.gas_InUse then
			ply.usedFuel = 0
			self:SetActive( true )
			self:SetUser( ply )
			ply:Give( "weapon_simfillerpistol" )
			ply:SelectWeapon( "weapon_simfillerpistol" )
			ply.gas_InUse = true
			
			local weapon = ply:GetActiveWeapon()
			if weapon:IsValid() and weapon:GetClass() == "weapon_simfillerpistol" then
				weapon:SetFuelType( FUELTYPE_ELECTRIC )
			end
		end
	else
		if ply == self:GetUser() then
			ply:StripWeapon( "weapon_simfillerpistol" ) 
			self:SetActive( false )
			self:SetUser( NULL )
			ply.gas_InUse = false
		end
	end
end

function ENT:OnActiveChanged( name, old, new)
	if new == old then return end
	
	if new then
		if self.sound then
			self.sound:Stop()
			self.sound = nil
		end
		self.sound = CreateSound(self, "npc/scanner/combat_scan_loop6.wav")
		self.sound:PlayEx(0,0)
		self.sound:ChangeVolume( 0.8,1 )
		self.sound:ChangePitch( 130,2 )
		if self.PumpEnt:IsValid() then
			self.PumpEnt:SetNoDraw( true )
		end
	else
		if self.PumpEnt:IsValid() then
			self.PumpEnt:SetNoDraw( false )
		end
		
		if self.sound then
			self.sound:ChangeVolume( 0,2 )
			self.sound:ChangePitch( 0,3 )
		end
	end
end
	
function ENT:Initialize()
	self:SetModel( "models/props_wasteland/gaspump001a.mdl" )
	self:PhysicsInit( SOLID_VPHYSICS )
	self:SetMoveType( MOVETYPE_VPHYSICS )
	self:SetSolid( SOLID_VPHYSICS )
	self:SetUseType( SIMPLE_USE )
	
	self.PumpEnt = ents.Create( "prop_dynamic" )
	self.PumpEnt:SetModel( "models/props_equipment/gas_pump_p13.mdl" )
	self.PumpEnt:SetPos( self:LocalToWorld( Vector(-0.2,-14.6,45.7) ) )
	self.PumpEnt:SetAngles( self:LocalToWorldAngles( Angle(-0.3,92.3,-0.1) ) )
	self.PumpEnt:SetMoveType( MOVETYPE_NONE )
	self.PumpEnt:Spawn()
	self.PumpEnt:Activate()
	self.PumpEnt:SetNotSolid( true )
	self.PumpEnt:DrawShadow( false )
	self.PumpEnt:SetParent( self )
	
	local PObj = self:GetPhysicsObject()
	if PObj:IsValid() then PObj:EnableMotion( false ) end
end

function ENT:Think()
	if CLIENT then return end
	
	self:NextThink( CurTime() + 0.5 )
	
	local ply = self:GetUser()
	if ply:IsValid() then
		self:SetFuelUsed( ply.usedFuel )
		
		local Dist = (ply:GetPos() - self:GetPos()):Length()
		
		if ply:Alive() then
			if ply:InVehicle() then
				if ply:HasWeapon( "weapon_simfillerpistol" ) then
					ply:StripWeapon( "weapon_simfillerpistol" ) 
				end
				ply.gas_InUse = false
				self:Disable()
			else
				if ply:HasWeapon( "weapon_simfillerpistol" ) then
					if ply:GetActiveWeapon():GetClass() ~= "weapon_simfillerpistol" or Dist >= 200 then
						ply:StripWeapon( "weapon_simfillerpistol" ) 
						ply.gas_InUse = false
						self:Disable()
					end
				else
					ply.gas_InUse = false
					self:Disable()
				end
			end
		else
			ply.gas_InUse = false
			self:Disable()
		end
	end
	
	return true
end

function ENT:Disable()
	self:SetUser( NULL )
	self:SetActive( false )
end

function ENT:OnRemove()
	if self.sound then
		self.sound:Stop()
	end
	
	local ply = self:GetUser()
	if ply:IsValid() then
		ply.gas_InUse = false
		if ply:Alive() then
			if ply:HasWeapon( "weapon_simfillerpistol" ) then
				ply:StripWeapon( "weapon_simfillerpistol" ) 
			end
		end
	end
end

function ENT:OnTakeDamage( dmginfo )
	self:TakePhysicsDamage( dmginfo )
end

function ENT:PhysicsCollide( data, physobj )
end