local modem = component.proxy(component.list('modem')())
local robot = component.proxy(component.list('robot')())
local address = '----'
modem.open(12345)
local status = 0
local signal = computer.pullSignal

function computer.pullSignal(...)
  local e = {signal(...)}
  if e[1] == 'modem_message' and e[3]:sub(1, 4) == address then
    status = tonumber(e[6])
  end
end
while true do
  computer.pullSignal(0.05)
  if status == 1 then
    if robot.suck(3) then
      robot.drop(0)
    end
  elseif status == 2 then
    if robot.suck(0) then
      robot.drop(3)
    end
  end
end
