---@class LootPointHelper
LootPointHelper = class "LootPointHelper"

require "MapsConfig"

function LootPointHelper:__init()
	Events:Subscribe("Extension:Loaded", self, self.OnExtensionLoaded)
end

function LootPointHelper:OnExtensionLoaded()
	self.m_Points = {}
	self.m_Center = ClientUtils:GetWindowSize() / 2

	self.m_SelectedIndex = nil
	self.m_ActiveIndex = nil
	self.m_SavedPosition = nil

    self.m_DrawDistance = 75
	self.m_RayCastRefresh = 0.45
	self.m_UpdateTicks = 0.0

    Events:Subscribe("Level:Loaded", self, self.OnLevelLoaded)
    Events:Subscribe("Player:UpdateInput", self, self.OnPlayerUpdateInput)
    Events:Subscribe("UpdateManager:Update", self, self.OnUpdateManagerUpdate)
end

function LootPointHelper:OnLevelLoaded()
	local s_LevelName = SharedUtils:GetLevelName()

	if s_LevelName == nil then
		return nil
	end

	s_LevelName = s_LevelName:gsub(".*/", "")

	if s_LevelName == nil then
		return
	end

    if MapsConfig[s_LevelName] == nil then
        return
    end

	self.m_Points = MapsConfig[s_LevelName]
end

function LootPointHelper:OnUIDrawHud()
    self.m_Center = ClientUtils:GetWindowSize() / 2

    local s_LocalPlayer = PlayerManager:GetLocalPlayer()

	if s_LocalPlayer == nil then
		return
	end

	if s_LocalPlayer.soldier == nil then
		return
	end
    
	for i, l_Point in pairs(self.m_Points) do
		if i ~= self.m_ActiveIndex then
            if s_LocalPlayer.soldier.worldTransform.trans:Distance(l_Point) < self.m_DrawDistance then
				DebugRenderer:DrawSphere(l_Point, 0.3, Vec4(1, 1, 1, 0.5), true, false)
			end
		end
	end

	-- Draw red SpawnPoint on the active point
	if self.m_ActiveIndex then
		DebugRenderer:DrawSphere(self.m_Points[self.m_ActiveIndex], 0.3, Vec4(1, 0, 0, 0.5), true, false)

	-- Draw blue SpawnPoint on the selected point
	elseif self.m_SelectedIndex then
		DebugRenderer:DrawSphere(self.m_Points[self.m_SelectedIndex], 0.3, Vec4(0, 0, 1, 0.5), true, false)
	end
end

function LootPointHelper:OnPlayerUpdateInput()
	local s_LocalPlayer = PlayerManager:GetLocalPlayer()

	if s_LocalPlayer == nil then
		return
	end

	if s_LocalPlayer.soldier == nil then
		return
	end

	-- Press F5 to start or stop moving points
	if InputManager:WentKeyDown(InputDeviceKeys.IDK_F5) then
		-- If the active point is the last, and unconfirmed, remove it
		if self.m_ActiveIndex == #self.m_Points and not self.m_SavedPosition then
			self.m_Points[self.m_ActiveIndex] = nil
			self.m_ActiveIndex = nil
		-- If a previous point was being moved, revert it back to the saved position
		elseif self.m_SavedPosition then
			self.m_Points[self.m_ActiveIndex] = self.m_SavedPosition:Clone()
			self.m_ActiveIndex = nil
			self.m_SavedPosition = nil
		-- If a point is being moved, stop moving it
		elseif self.m_ActiveIndex then
			self.m_ActiveIndex = nil
		-- Start or continue adding points
		else
			self.m_ActiveIndex = #self.m_Points + 1
			self.m_Points[self.m_ActiveIndex] = Vec3()
		end
	end

	-- Press F4 to clear point(s)
	if InputManager:WentKeyDown(InputDeviceKeys.IDK_F4) then
		-- If theres a point being moved, clear only it
		if self.m_ActiveIndex then
			table.remove(self.m_Points, self.m_ActiveIndex)
		-- If theres a point selected, clear only it
		elseif self.m_SelectedIndex then
			table.remove(self.m_Points, self.m_SelectedIndex)
		end

		self.m_ActiveIndex = nil
		self.m_SelectedIndex = nil
		self.m_SavedPosition = nil
	end

	-- Press F7 to select point or confirm point placement
	if InputManager:WentKeyDown(InputDeviceKeys.IDK_F7) then
		if self.m_ActiveIndex then
			-- If a point was being moved and it has now been confirmed
			if self.m_SavedPosition then
				self.m_ActiveIndex = nil
				self.m_SavedPosition = nil
			-- If the point that will be confirmed is the last, start drawing the next one
			elseif self.m_ActiveIndex == #self.m_Points then
				self.m_ActiveIndex = #self.m_Points + 1
				self.m_Points[self.m_ActiveIndex] = Vec3()
				self.m_SavedPosition = nil
			-- If theres no saved position and the point being moved is not the last, an inserted point was being placed and it has now been confirmed
			else
				self.m_ActiveIndex = nil
			end
		-- If E is pressed while a previous point is selected, that point becomes the active point
		elseif self.m_SelectedIndex then
			self.m_SavedPosition = self.m_Points[self.m_SelectedIndex]:Clone()
			self.m_ActiveIndex = self.m_SelectedIndex
			self.m_SelectedIndex = nil
		end
	end

	-- Press F2 to print points as Transforms
	if InputManager:WentKeyDown(InputDeviceKeys.IDK_F2) then
		self:PrintPointsAsTransforms()
	end
end

function LootPointHelper:OnUpdateManagerUpdate(p_DeltaTime, p_UpdatePass)
	-- Only do raycast on presimulation UpdatePass
	if p_UpdatePass ~= UpdatePass.UpdatePass_PreSim then
		if p_UpdatePass == UpdatePass.UpdatePass_PreFrame then
			self:OnUIDrawHud()
		end
		return
	end

	if self.m_UpdateTicks >= self.m_RayCastRefresh then
		self.m_UpdateTicks = 0.0

		local s_RaycastHit = self:Raycast()

		if s_RaycastHit == nil then
			return
		end
	
		local s_LocalPlayer = PlayerManager:GetLocalPlayer()
	
		if s_LocalPlayer == nil then
			return
		end
	
		if s_LocalPlayer.soldier == nil then
			return
		end
	
		local s_HitPosition = s_RaycastHit.position
		self.m_SelectedIndex = nil
	
		-- Move the active point to the "point of aim"
		if self.m_ActiveIndex and s_RaycastHit then
			self.m_Points[self.m_ActiveIndex] = s_HitPosition
		-- If theres no active point, check to see if the POA is near a point
		else
			local s_ClosestDistance = 1000.0
	
			for l_Index, l_Point in pairs(self.m_Points) do
				if s_LocalPlayer.soldier.worldTransform.trans:Distance(l_Point) > self.m_DrawDistance then
					goto continue
				end
	
				local s_PointScreenPos = ClientUtils:WorldToScreen(l_Point)
	
				-- Skip to the next point if this one isn't in view
				if s_PointScreenPos == nil then
					goto continue
				end
	
				-- Select point if its close to the hitPosition
				local s_Distance = self.m_Center:Distance(s_PointScreenPos)
	
				if s_Distance < s_ClosestDistance then
					s_ClosestDistance = s_Distance
					self.m_SelectedIndex = l_Index
				end
	
				::continue::
			end
		end
	end
	self.m_UpdateTicks = self.m_UpdateTicks + p_DeltaTime
end

-- stolen't https://github.com/EmulatorNexus/VEXT-Samples/blob/80cddf7864a2cdcaccb9efa810e65fae1baeac78/no-headglitch-raycast/ext/Client/__init__.lua
function LootPointHelper:Raycast()
	local s_LocalPlayer = PlayerManager:GetLocalPlayer()

	if s_LocalPlayer == nil then
		return
	end

	-- We get the camera transform, from which we will start the raycast. We get the direction from the forward vector. Camera transform
	-- is inverted, so we have to invert this vector.
	local s_Transform = ClientUtils:GetCameraTransform()
	local s_Direction = Vec3(-s_Transform.forward.x, -s_Transform.forward.y, -s_Transform.forward.z)

	if s_Transform.trans == Vec3(0,0,0) then
		return
	end

	local s_CastStart = s_Transform.trans

	-- We get the raycast end transform with the calculated direction and the max distance.
	local s_CastEnd = Vec3(
		s_Transform.trans.x + (s_Direction.x * 100),
		s_Transform.trans.y + (s_Direction.y * 100),
		s_Transform.trans.z + (s_Direction.z * 100)
    )

	-- Perform raycast, returns a RayCastHit object.
	local s_RaycastHit = RaycastManager:Raycast(s_CastStart, s_CastEnd, RayCastFlags.DontCheckWater | RayCastFlags.DontCheckCharacter | RayCastFlags.DontCheckRagdoll | RayCastFlags.CheckDetailMesh)

	return s_RaycastHit
end

function LootPointHelper:PrintPointsAsTransforms()
	local s_Result = "points = { "

	for _, l_Point in pairs(self.m_Points) do
		s_Result = s_Result .. "Vec3"..tostring(l_Point)..", "
	end

	print(s_Result.."}")
end

return LootPointHelper()
