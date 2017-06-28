--https://pastebin.com/buavY589
--wget "https://raw.githubusercontent.com/Krutoy242/Gopher-Programs/Packed/gml/lib/gml_full.lua" gml.lua
package.loaded.gml=nil
package.loaded.gfxbuffer=nil
local gml = require('gml')
local event = require('event')
local unicode = require('unicode')
local computer = require('computer')
local component = require('component')
local serialization = require('serialization')
local interface = component.me_interface
local chest = component.chest
local modem = component.modem
local gpu = component.gpu
local SIDE = 'UP'
local port = 50021
local BUFFER, uiBuffer, itemsNet, uiitemsNet = {}, {}, {}, {}
local Multiplier = 1000000 -- множитель реальной стоимости, необходим для целочисленного отображения цены
local Step = 1 -- шаг сделки, количество пунктов, на которые текущая цена должна приблизиться к реальной
local Set = 0.005 -- процент с продаж
local Operator = 'Doob' -- оператор системы
local maxlog = 30
local db = {
  last = {},
  users = {},
  wlist = {
    ['minecraft:diamond|0'] = true,
    ['minecraft:redstone|0'] = true,
    ['minecraft:iron_ingot|0'] = true,
    ['minecraft:gold_ingot|0'] = true,
    ['minecraft:coal|0'] = true,
    ['minecraft:emerald|0'] = true,
    ['minecraft:nether_star|0'] = true,
    ['minecraft:glowstone_dust|0'] = true,
    ['minecraft:dye|4'] = true,
    ['IC2:itemRubber|0'] = true,
    ['IC2:blockOreUran|0'] = true,
    ['IC2:itemOreIridium|0'] = true
  },
  items = {
    ['minecraft:diamond|0']={label='Алмаз',cost=1,o=0,i=0},
    ['minecraft:redstone|0']={label='Редстоун',cost=1,o=0,i=0},
    ['minecraft:iron_ingot|0']={label='Железный слиток',cost=1,o=0,i=0},
    ['minecraft:gold_ingot|0'] = {label='Золотой слиток',cost=1,o=0,i=0},
    ['minecraft:coal|0']={label='Уголь',cost=1,o=0,i=0},
    ['minecraft:emerald|0']={label='Изумруд',cost=1,o=0,i=0},
    ['minecraft:nether_star|0']={label='Звезда ада',cost=1,o=0,i=0},
    ['minecraft:glowstone_dust|0']={label='Светопыль',cost=1,o=0,i=0},
    ['minecraft:dye|4']={label='Лазурит',cost=1,o=0,i=0},
    ['IC2:itemRubber|0']={label='Резина',cost=1,o=0,i=0},
    ['IC2:blockOreUran|0']={label='Урановая руда',cost=1,o=0,i=0},
    ['IC2:itemOreIridium|0']={label='Иридиевая руда',cost=1,o=0,i=0}
  }
}
gpu.setResolution(46, 15)
local CURRENT_USER, BALANCE_TEXT, lastlogin
local nc = {x = 14, y = 4}
local buy_cost = 0
local size = 0
local sell_total = 0
local sell_items = {}
local dbname = 'market.db'

local function savedb()
  local file = io.open(dbname, 'w')
  file:write(serialization.serialize(db))
  file:close()
end

local function loaddb()
  local file = io.open(dbname, 'r')
  if not file then
    file = io.open(dbname, 'w')
    file:write(serialization.serialize(db))
  else
    local serdb = file:read('a')
    db = serialization.unserialize(serdb)
  end
  file:close()
end

local function addlog(str)
  local file = io.open('market.log', 'a')
  file:write(str..'\n')
  file:close()
end

local function bb()
  BALANCE_TEXT = CURRENT_USER..': '..db.users[CURRENT_USER]
end

local function addspace(str, n)
  if n-1 < unicode.len(str) then
    return unicode.sub(str, 1, n)
  else
    for i = 1, n-unicode.len(str) do
      str = str..' '
    end
    return str
  end
end

local function getFingerprint(item)
  local items = interface.getAvailableItems()
  for i = 1, #items do
    if items[i].fingerprint.id..'|'..items[i].fingerprint.dmg == item then
      return items[i].fingerprint
    end
  end
end

local function toBuffer(item, amount)
  local fp = getFingerprint(item)
  local counter, current, size = 0, amount
  if fp then
    for i = 1, math.ceil(amount/64) do
      size = interface.exportItem(fp, SIDE, current).size
      counter, current = counter + size, current - size
    end
  end
  return counter
end

local function toNet(item, amount)
  local counter = 0
  for s = 1, chest.getInventorySize() do
    local fitem = chest.getStackInSlot(s)
    if fitem then
      if item == fitem.id..'|'..fitem.dmg then
        if fitem.qty < amount then
          interface.pullItemIntoSlot(SIDE, s, fitem.qty)
          amount, counter = amount - fitem.qty, counter+fitem.qty
        elseif fitem.qty >= amount then
          interface.pullItemIntoSlot(SIDE, s, amount)
          amount, counter = 0, counter+amount
          break
        end
      end
    end
  end
  return counter
end

local function scanBuffer()
  BUFFER, uiBuffer = {}, {}
  for s = 1, chest.getInventorySize() do
    local item = chest.getStackInSlot(s)
    if item then
      local name = item.id..'|'..item.dmg
      if db.wlist[name] then
        if not db.items[name] then
          db.items[name] = {label=item.display_name,cost=1,o=0,i=0}
        end
        if not BUFFER[name] then
          BUFFER[name] = item.qty
        else
          BUFFER[name] = BUFFER[name] + item.qty
        end
      end
    end
  end
  uiBuffer[0] = {}
  for i, j in pairs(BUFFER) do
    if db.wlist[i] and db.items[i] then
      local txt = db.items[i].label
      txt = addspace(txt, 17)
      txt = txt..j
      txt = addspace(txt, 29)
      txt = txt..db.items[i].cost*j
      table.insert(uiBuffer, txt)
      uiBuffer[0][txt] = i
    end
  end
end

local function scanNet()
  local tbl = interface.getItemsInNetwork()
  itemsNet, uiitemsNet = {}, {}
  for i = 1, #tbl do
    local item = tbl[i].name..'|'..tbl[i].damage
    if db.wlist[item] then
      if itemsNet[item] then
        itemsNet[item] = itemsNet[item]+tbl[i].size
      else
        itemsNet[item] = tbl[i].size
      end
    end
  end
  uiitemsNet[0] = {}
  for i, j in pairs(itemsNet) do
    if db.wlist[i] and db.items[i] then
      local txt = db.items[i].label
      txt = addspace(txt, 17)
      txt = txt..j
      txt = addspace(txt, 29)
      txt = txt..db.items[i].cost
      table.insert(uiitemsNet, txt)
      uiitemsNet[0][txt] = i
    end
  end
end

local function getRealCost(item) -- рассчет реальной стоимости
  local real_cost = math.ceil(((db.items[item].o/(db.items[item].i-db.items[item].o))/db.items[item].i)*Multiplier)
  if real_cost <= 1 then
    real_cost = 1
  --elseif real_cost == math.huge then
  --  real_cost = Multiplier
  end
  return real_cost
end

local function setNewCurrentCost(item) -- установка новой текущей стоимости
  --db.items[item].cost = getRealCost(item)
  local cost = getRealCost(item)
  if cost > db.items[item].cost then
    db.items[item].cost = db.items[item].cost + Step
  elseif cost < db.items[item].cost then
    db.items[item].cost = db.items[item].cost - Step
  end
  if db.items[item].cost < 1 then
    db.items[item].cost = 1
  end
end

local function transfer(target, amount)
  if db.users[CURRENT_USER] and db.users[CURRENT_USER] >= amount then
    if not db.users[CURRENT_USER] then db.users[CURRENT_USER] = 0 end
    if not db.users[target] then db.users[target] = 0 end
    db.users[CURRENT_USER] = db.users[CURRENT_USER] - amount
    db.users[target] = db.users[target] + amount
    addlog(os.time()..'@'..CURRENT_USER..'@'..db.users[CURRENT_USER]..'@T@'..target..'@'..db.users[target]..'@'..amount)
    savedb()
  end
end

local function buy(titems) -- покупка предметов у пользователя
  local summ = 0
  for item, amount in pairs(titems) do
    local size = toNet(item, amount)
    if db.wlist[item] then
      db.items[item].i = db.items[item].i + size
      db.users[CURRENT_USER] = db.users[CURRENT_USER] + (db.items[item].cost * size)
      summ = summ + (db.items[item].cost * size)
      setNewCurrentCost(item)
      addlog(os.time()..'@'..CURRENT_USER..'@'..db.users[CURRENT_USER]..'@>@'..item..'@'..size..'@'..db.items[item].i-db.items[item].o..'@'..db.items[item].cost)
    end
  end
  if CURRENT_USER ~= Operator and summ > 1 then
    transfer(Operator, math.ceil(summ*Set))
  end
  savedb()
  bb()
end

local function sell(item, amount) -- продажа предметов пользователю
  local total = db.items[item].cost * amount
  if db.wlist[item] and db.users[CURRENT_USER] >= total then
    toBuffer(item, amount)
	db.items[item].o = db.items[item].o + amount
	db.users[CURRENT_USER] = db.users[CURRENT_USER] - total
    setNewCurrentCost(item)
    addlog(os.time()..'@'..CURRENT_USER..'@'..db.users[CURRENT_USER]..'@<@'..item..'@'..amount..'@'..db.items[item].i-db.items[item].o..'@'..db.items[item].cost)
    savedb()
  end
  bb()
end

local function logout()
  modem.broadcast(port, 2)
  computer.removeUser(CURRENT_USER)
  CURRENT_USER = nil
end

local function relogin()
  if os.time()-db.last[CURRENT_USER].login < 259200 then
    if db.last[CURRENT_USER].count <= maxlog then
      db.last[CURRENT_USER].count = db.last[CURRENT_USER].count + 1
    end
  else
    db.last[CURRENT_USER].count = 1
    db.last[CURRENT_USER].login = os.time()
  end
end

local main_menu = gml.create(1, 1, 46, 15)
local wallet_menu = gml.create(1, 1, 46, 15)
local sell_menu = gml.create(1, 1, 46, 15)
local buy_menu = gml.create(1, 1, 46, 15)
local info_dialog = gml.create(1, 1, 46, 15)
local buy_dialog = gml.create(1, 1, 46, 15)
local sell_confirm_dialog = gml.create(1, 1, 46, 15)

main_menu.style = gml.loadStyle('style')
sell_menu.style = main_menu.style
buy_menu.style = main_menu.style
wallet_menu.style = main_menu.style
info_dialog.style = main_menu.style
buy_dialog.style = main_menu.style
sell_confirm_dialog.style = main_menu.style

--------------------------------------BALANCE
local lbl_bal = wallet_menu:addLabel(1, 3, 1, 1)
local lbl2_bal = wallet_menu:addLabel(1, 5, 1, 1)
local lbl3_bal = wallet_menu:addLabel(1, 7, 1, 1)
local btn_exit_bal = wallet_menu:addButton('center', 10, 20, 3, 'Выход', function()
  logout()
  wallet_menu.close()
end)
local function balance()
  bb()
  lbl_bal.text = BALANCE_TEXT
  lbl_bal.width = #BALANCE_TEXT
  lbl_bal.posX = math.floor((45-lbl_bal.width)/2)
  local txt = 'Доступно операций: '.. maxlog-db.last[CURRENT_USER].count
  lbl2_bal.text = txt
  lbl2_bal.width = unicode.len(txt)
  lbl2_bal.posX = math.floor((45-lbl2_bal.width)/2)
  txt = 'Сброс через '..60-math.ceil((os.time()-db.last[CURRENT_USER].login)/4320)..' минут'
  lbl3_bal.text = txt
  lbl3_bal.width = unicode.len(txt)
  lbl3_bal.posX = math.floor((45-lbl3_bal.width)/2)
  wallet_menu:run()
end
--------------------------------------SELL CONFIRM
sell_confirm_dialog:addLabel(14, 1, 17, 'Продать предметы?')
local sc_kol = sell_confirm_dialog:addLabel(1, 4, 12, 0)
local sc_sum = sell_confirm_dialog:addLabel(1, 6, 10, 0)
sell_confirm_dialog:addButton('left', 11, 13, 3, 'Отмена', function()
  sell_total = 0
  logout()
  sell_menu.close()
  info_dialog.close()
  sell_confirm_dialog.close()
end)
sell_confirm_dialog:addButton('right', 11, 13, 3, 'Подтвердить', function()
  relogin()
  buy(sell_items)
  logout()
  sell_menu.close()
  info_dialog.close()
  sell_confirm_dialog.close()
end)
--------------------------------------SELL
local lbsell = sell_menu:addListBox('center', 3, 44, 9, {})
local sell_money = sell_menu:addLabel(1, 1, 1, 1)
local sell_colums = sell_menu:addLabel(1, 2, 36, 'Наименование     Количество  Сумма')
local sell_exit = sell_menu:addButton('left', 15, 13, 1, 'Отмена', function()
  logout()
  sell_menu.close()
  info_dialog.close()
end)
local sell_all = sell_menu:addButton(16, 15, 14, 1, 'Продать все', function()
  if #uiBuffer > 0 then
    local asize, amon = 0, 0
    sell_items = {}
    for k, v in pairs(BUFFER) do
      asize = asize + v
      amon = amon + (v*db.items[k].cost)
    end
    sc_kol.text = 'Количество: '..asize
    amon = amon-math.ceil(amon*Set)
    if amon == 0 then amon = 1 end
    sell_total = amon
    sc_sum.text = 'На сумму: '..amon..' (комиссия '..Set*100 ..'%)'
    sc_kol.width = unicode.len(sc_kol.text)
    sc_kol.posX = math.floor((46-sc_kol.width)/2)
    sc_sum.width = unicode.len(sc_sum.text)
    sc_sum.posX = math.floor((46-sc_sum.width)/2)
    sell_total = amon
    for i, j in pairs(BUFFER) do
      sell_items[i] = BUFFER[i]
    end
    sell_confirm_dialog:run()
  end
end)
local sell_one = sell_menu:addButton('right', 15, 13, 1, 'Продать', function()
  if #uiBuffer > 0 then
    sell_items = {}
    local item = uiBuffer[0][lbsell:getSelected()]
    sc_kol.text = 'Количество: '..BUFFER[item]
    local amon = BUFFER[item]*db.items[item].cost
    amon = amon-math.ceil(amon*Set)
    if amon == 0 then amon = 1 end
    sell_total = amon
    sc_sum.text = 'На сумму: '..amon..' (комиссия '..Set*100 ..'%)'
    sc_kol.width = unicode.len(sc_kol.text)
    sc_kol.posX = math.floor((46-sc_kol.width)/2)
    sc_sum.width = unicode.len(sc_sum.text)
    sc_sum.posX = math.floor((46-sc_sum.width)/2)
    sell_items[item] = BUFFER[item]
    sell_confirm_dialog:run()
  end
end)
--------------------------------------SELL INFO
local lbl_inf = info_dialog:addLabel(6, 5, 34, 'Кинь предметы для продажи роботу')
local btn_cncl_inf = info_dialog:addButton(6, 8, 13, 3, 'Отмена', function()
  logout()
  info_dialog.close()
end)
local btn_nxt_inf = info_dialog:addButton(26, 8, 13, 3, 'Далее', function()
  modem.broadcast(port, 0)
  scanBuffer()
  lbsell:updateList(uiBuffer)
  bb()
  sell_money.text = BALANCE_TEXT
  sell_money.width = #BALANCE_TEXT
  sell_money.posX = math.floor((45/2)-(sell_money.width/2))
  sell_menu:run()
end)
--------------------------------------
local itemname = buy_dialog:addLabel(1, 1, 22, '')
local itemcost = buy_dialog:addLabel(1, 1, 8, '')
local kol = buy_dialog:addLabel(1, 1+nc.y, 12, 'Количество: ')
local sum = buy_dialog:addLabel(1, nc.y-1, 7, 'Сумма: ')
local amou = buy_dialog:addLabel(1+nc.x, 1+nc.y, 30, 0)
local totalcoin = buy_dialog:addLabel(1+nc.x, nc.y-1, 30, 0)
--------------------------------------BUY
local buy_list = buy_menu:addListBox('center', 3, 44, 9, {})
local buy_money = buy_menu:addLabel(1, 1, 1, 1)
local buy_colums = buy_menu:addLabel(1, 2, 36, 'Наименование     Количество  Цена')
local buy_exit = buy_menu:addButton(1, 15, 13, 1, 'Отмена', function()
  logout()
  buy_menu:hide()
  buy_menu.close()
end)
local buy_c = buy_menu:addButton(32, 15, 13, 1, 'Далее', function()
  if #uiitemsNet > 0 then
    local item_label = db.items[uiitemsNet[0][buy_list:getSelected()]].label
    buy_cost = tostring(db.items[uiitemsNet[0][buy_list:getSelected()]].cost)
    itemname.width = unicode.len(item_label)+14
    itemname.text = 'Наименование: '..item_label
    itemcost.width = #buy_cost+6
    itemcost.posX = 45-itemcost.width
    itemcost.text = 'Цена: '..buy_cost
    amou.text = 0
    totalcoin.text = 0
    buy_dialog:run()
  end
end)
--------------------------------------
local function rebuild(n)
  if size == 0 then
    size = n
  else
    size = size*10+n
  end
  if size*buy_cost > db.users[CURRENT_USER] then -- ограничение количества по балансу
    size = math.floor(db.users[CURRENT_USER]/buy_cost)
  end
  local item = db.items[uiitemsNet[0][buy_list:getSelected()]]
  if size > item.i-item.o then -- ограничение максимального количества по рассчитанному
    size = item.i-item.o
  end
  amou.text = size
  totalcoin.text = size*buy_cost
  amou:draw()
  totalcoin:draw()
end
local num1 = buy_dialog:addButton(1+nc.x, 3+nc.y, 3, 1, '1',function()rebuild(1)end)
local num2 = buy_dialog:addButton(6+nc.x, 3+nc.y, 3, 1, '2',function()rebuild(2)end)
local num3 = buy_dialog:addButton(11+nc.x, 3+nc.y, 3, 1, '3',function()rebuild(3)end)
local num4 = buy_dialog:addButton(1+nc.x, 5+nc.y, 3, 1, '4',function()rebuild(4)end)
local num5 = buy_dialog:addButton(6+nc.x, 5+nc.y, 3, 1, '5',function()rebuild(5)end)
local num6 = buy_dialog:addButton(11+nc.x, 5+nc.y, 3, 1, '6',function()rebuild(6)end)
local num7 = buy_dialog:addButton(1+nc.x, 7+nc.y, 3, 1, '7',function()rebuild(7)end)
local num8 = buy_dialog:addButton(6+nc.x, 7+nc.y, 3, 1, '8',function()rebuild(8)end)
local num9 = buy_dialog:addButton(11+nc.x, 7+nc.y, 3, 1, '9',function()rebuild(9)end)
local num0 = buy_dialog:addButton(6+nc.x, 9+nc.y, 3, 1, '0',function()rebuild(0)end)
local numok = buy_dialog:addButton(11+nc.x, 9+nc.y, 3, 1, 'ok',function()
  local item = uiitemsNet[0][buy_list:getSelected()]
  sell(item, size)
  relogin()
  logout()
  buy_dialog.close()
  buy_menu:hide()
  buy_menu.close()
end)
local numD = buy_dialog:addButton(1+nc.x, 9+nc.y, 3, 1, '<',function()
  if size == 0 then
    buy_dialog.close()
  elseif #tostring(size) == 1 and size ~= 0 then
    size = 0
  elseif #tostring(size) > 1 then
    size = (size-math.fmod(size, 10))/10
  end
  amou.text = size
  totalcoin.text = size*buy_cost
  amou:draw()
  totalcoin:draw()
end)
--------------------------------------MAIN
local button_buy = main_menu:addButton('center', 2, 20, 3, 'Продать', function()
  if db.last[CURRENT_USER].count < maxlog then
    modem.broadcast(port, 1)
    info_dialog:run()
  end
end)
local button_sell = main_menu:addButton('center', 6, 20, 3, 'Купить', function()
  if db.last[CURRENT_USER].count < maxlog then
    scanNet()
    buy_list:updateList(uiitemsNet)
    bb()
    buy_money.text = BALANCE_TEXT
    buy_money.width = #BALANCE_TEXT
    buy_money.posX = math.floor((45/2)-(buy_money.width/2))
    buy_menu:run()
  end
end)
local button_bal = main_menu:addButton('center', 10, 20, 3, 'Информация', balance)

main_menu:addHandler('touch', function(...)
  local e = {...}
  CURRENT_USER = e[6]
  lastlogin = computer.uptime()
  computer.addUser(CURRENT_USER)
  if not db.users[CURRENT_USER] then
    db.users[CURRENT_USER] = 0
  end
  if not db.last[CURRENT_USER] then
    db.last[CURRENT_USER] = {login = os.time(), count = 0}
  end
  if os.time()-db.last[CURRENT_USER].login > 259200 then
    db.last[CURRENT_USER].login = os.time()
    db.last[CURRENT_USER].count = 0
  end
  bb()
end)

_G.m_timer = event.timer(60, function()
  if CURRENT_USER and computer.uptime()-lastlogin >= 120 then
    logout()
    sell_menu.close()
    buy_menu.close()
    wallet_menu.close()
    info_dialog.close()
    buy_dialog.close()
    sell_confirm_dialog.close()
  end
end, math.huge)

os.execute('cls')
loaddb()
main_menu:run()
