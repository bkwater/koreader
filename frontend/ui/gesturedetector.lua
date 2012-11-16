require "ui/inputevent"
require "ui/geometry"

-- Synchronization events (SYN.code).
SYN_REPORT = 0
SYN_CONFIG = 1
SYN_MT_REPORT = 2

-- For multi-touch events (ABS.code).
ABS_MT_SLOT = 47
ABS_MT_POSITION_X = 53
ABS_MT_POSITION_Y = 54
ABS_MT_TRACKING_ID = 57
ABS_MT_PRESSURE = 58


GestureRange = {
	ges = nil,
	range = nil,
}

function GestureRange:new(o)
	local o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function GestureRange:match(gs)
	if gs.ges ~= self.ges then
		return false
	end

	if self.range:contains(gs.pos) then
		return true
	end

	return false
end


--[[
Single tap event from kernel example:

MT_TRACK_ID: 0
MT_X: 222
MT_Y: 207
SYN REPORT
MT_TRACK_ID: -1
SYN REPORT
--]]

GestureDetector = {
	-- all the time parameters are in ms
	DOUBLE_TAP_TIME = 500,
	-- distance parameters
	DOUBLE_TAP_DISTANCE = 50,
	PAN_THRESHOLD = 50,

	track_id = {},
	ev_stack = {},
	cur_ev = {},
	ev_start = false,
	state = function(self, ev) 
		self.switchState("initialState", ev)
	end,
	
	last_ev_time = nil,

	-- for tap
	last_tap = nil,
}

function GestureDetector:feedEvent(ev) 
	if ev.type == EV_SYN then
		if ev.code == SYN_REPORT then
			self.cur_ev.time = ev.time
			local re = self.state(self, self.cur_ev)
			self.last_ev_time = ev.time
			if re ~= nil then
				return re
			end
			self.cur_ev = {}
		end
	elseif ev.type == EV_ABS then
		if ev.code == ABS_MT_SLOT then
			self.cur_ev.slot = ev.value
		elseif ev.code == ABS_MT_TRACKING_ID then
			self.cur_ev.id = ev.value
		elseif ev.code == ABS_MT_POSITION_X then
			self.cur_ev.x = ev.value
		elseif ev.code == ABS_MT_POSITION_Y then
			self.cur_ev.y = ev.value
		end
	end
end

--[[
tap2 is the later tap
]]
function GestureDetector:isDoubleTap(tap1, tap2)
	--@TODO this is a bug    (houqp)
	local msec_diff = (tap2.time.usec - tap1.time.usec) * 1000
	return (
		math.abs(tap1.x - tap2.x) < self.DOUBLE_TAP_DISTANCE and
		math.abs(tap1.y - tap2.y) < self.DOUBLE_TAP_DISTANCE and
		msec_diff < self.DOUBLE_TAP_TIME
	)
end

function GestureDetector:switchState(state, ev)
	--@TODO do we need to check whether state is valid?    (houqp)
	return self[state](self, ev)
end

function GestureDetector:clearState()
	self.cur_x = nil
	self.cur_y = nil
	self.state = self.initialState
	self.cur_ev = {}
	self.ev_start = false
end

function GestureDetector:initialState(ev)
	if ev.id then
		-- a event ends
		if ev.id == -1 then
			self.ev_start = false
		else
			self.track_id[ev.id] = ev.slot
		end
	end
	if ev.x and ev.y then
		-- a new event has just started
		if not self.ev_start then
			self.ev_start = true
			-- default to tap state
			return self:switchState("tapState", ev)
		end
	end
end

--[[
this method handles both single and double tap
]]
function GestureDetector:tapState(ev)
	if ev.id == -1 then
		-- end of tap event
		local ges_ev = {
			-- default to single tap
			ges = "tap", 
			pos = Geom:new{
				x = self.cur_x, 
				y = self.cur_y,
				w = 0, h = 0,
			}
		}
		-- cur_tap is used for double tap detection
		local cur_tap = {
			x = self.cur_x,
			y = self.cur_y,
			time = ev.time,
		}

		if self.last_tap and 
		self:isDoubleTap(self.last_tap, cur_tap) then
			ges_ev.ges = "double_tap"
			self.last_tap = nil
		end

		if ges_ev.ges == "tap" then
			-- set current tap to last tap
			self.last_tap = cur_tap
		end
	
		self:clearState()
		return ges_ev
	elseif self.state ~= self.tapState then
		-- switched from other state, probably from initialState
		-- we return nil in this case
		self.state = self.tapState
		self.cur_x = ev.x
		self.cur_y = ev.y
		--@TODO set up hold timer    (houqp)
		table.insert(Input.timer_callbacks, {
			callback = function()
				if self.state == self.tapState then
					-- timer set in tapState, so we switch to hold
					return self.switchState("holdState")
				end
			end, 
			time = ev.time, 
			time_out = HOLD_TIME
		})
	else
		-- it is not end of touch event, see if we need to switch to
		-- other states
		if math.abs(ev.x - self.cur_x) >= self.PAN_THRESHOLD or
		math.abs(ev.y - self.cur_y) >= self.PAN_THRESHOLD then
			-- if user's finger moved long enough in X or
			-- Y distance, we switch to pan state 
			return self:switchState("panState", ev)
		end
	end
end

function GestureDetector:panState(ev)
	if ev.id == -1 then
		-- end of pan, signal swipe gesture
	elseif self.state ~= self.panState then
		self.state = self.panState
		--@TODO calculate direction here    (houqp)
	else
	end
	self.cur_x = ev.x
	self.cur_y = ev.y
end

function GestureDetector:holdState(ev)
	if not ev and self.cur_x and self.cur_y then
		return {
			ges = "hold", 
			pos = Geom:new{
				x = self.cur_x, 
				y = self.cur_y,
				w = 0, h = 0,
			}
		}
	end
	if ev.id == -1 then
		-- end of hold, signal hold release?
	end
end


