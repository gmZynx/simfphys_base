AddCSLuaFile()

SWEP.Category			= "simfphys"
SWEP.Spawnable		= true
SWEP.AdminSpawnable	= false
SWEP.ViewModel		= "models/weapons/c_pistol.mdl"
SWEP.WorldModel		= "models/weapons/w_pistol.mdl"
SWEP.UseHands			= true
SWEP.ViewModelFlip		= false
SWEP.ViewModelFOV		= 53
SWEP.Weight 			= 42
SWEP.AutoSwitchTo 		= true
SWEP.AutoSwitchFrom 	= true
SWEP.HoldType			= "pistol"

SWEP.Primary.ClipSize		= -1
SWEP.Primary.DefaultClip		= -1
SWEP.Primary.Automatic		= false
SWEP.Primary.Ammo			= "none"

SWEP.Secondary.ClipSize		= -1
SWEP.Secondary.DefaultClip	= -1
SWEP.Secondary.Automatic		= false
SWEP.Secondary.Ammo		= "none"

function SWEP:SetupDataTables()
	self:NetworkVar( "Entity",0, "Car" )
	self:NetworkVar( "Bool",0, "Active" )
end

if (CLIENT) then
	SWEP.PrintName		= "Remote Controller"
	SWEP.Purpose			= "remote controls simfphys vehicles"
	SWEP.Instructions		= "Left-Click on a simfphys car to link. Press the Use-Key to start remote controlling."
	SWEP.Author			= "Blu"
	SWEP.Slot				= 1
	SWEP.SlotPos			= 10
	
	local color_blue = Color( 0, 127, 255 )
	hook.Add( "PreDrawHalos", "s_remote_halos", function()
		local ply = LocalPlayer()
		if ply:IsValid() and not ply:InVehicle() then
			local weapon = ply:GetActiveWeapon()
			if weapon:IsValid() and weapon:GetClass() == "weapon_simremote" and not weapon:GetActive() then	
				local car = weapon:GetCar()
				if car:IsValid() then halo.Add( { car }, color_blue ) end
			end
		end
	end )


	function SWEP:PrimaryAttack()
		if self:GetActive() then return false end

		local trace = self:GetOwner():GetEyeTrace()
		local ent = trace.Entity

		if not simfphys.IsCar( ent ) then return false end

		self.Weapon:EmitSound( "Weapon_Pistol.Empty" )

		return true
	end

	function SWEP:SecondaryAttack()
		if self:GetActive() then return false end

		self.Weapon:EmitSound( "Weapon_Pistol.Empty" )

		return true
	end

	return
end

function SWEP:Initialize()
	self.Weapon:SetHoldType( self.HoldType )
end

function SWEP:OwnerChanged()
end

function SWEP:Think()
	if self:GetOwner():KeyPressed( IN_USE ) then
		if self:GetActive() or not self:GetCar():IsValid() then
			self:Disable()
		else
			self:Enable()
		end
	end
end

function SWEP:PrimaryAttack()
	if self:GetActive() then return false end

	local ply = self:GetOwner()
	local trace = ply:GetEyeTrace()
	local ent = trace.Entity

	if not simfphys.IsCar( ent ) then return false end

	self:SetCar( ent )

	ply:ChatPrint("Remote Controller linked.")

	return true
end

function SWEP:SecondaryAttack()
	if self:GetActive() then return false end
	
	if self:GetCar():IsValid() then
		self:SetCar( NULL )
		self:GetOwner():ChatPrint("Remote Controller unlinked.")

		return true
	end

	return false
end

function SWEP:Enable()
	local car = self:GetCar()
	
	if car:IsValid() then
		local ply = self:GetOwner()
		if car:GetDriver():IsValid() then
			ply:ChatPrint("vehicle is already in use")
		else
			if car:GetIsVehicleLocked() then
				ply:ChatPrint("vehicle is locked")
			else
				self:SetActive( true )
				self.OldMoveType = ply:GetMoveType()

				ply:SetMoveType( MOVETYPE_NONE )
				ply:DrawViewModel( false )

				car.RemoteDriver = ply
			end
		end
	end
end

function SWEP:Disable()

	local ply = self:GetOwner()
	local car = self:GetCar()

	if self:GetActive() then
		if self.OldMoveType then
	    		ply:SetMoveType( self.OldMoveType )
		else
	    		ply:SetMoveType( MOVETYPE_WALK )
		end
	end

	self:SetActive( false )
	self.OldMoveType = nil
	ply:DrawViewModel( true )
	
	if car:IsValid() then
		car.RemoteDriver = nil
	end
end

function SWEP:Deploy()
	self.Weapon:SendWeaponAnim( ACT_VM_DRAW )
	return true
end

function SWEP:Holster()
	if self:GetCar():IsValid() then
		self:Disable()
	end
	return true
end

function SWEP:OnDrop()
	if self:GetCar():IsValid() then
		self:Disable()
		self.TheCar = nil
	end
end
