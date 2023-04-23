-- level maintainer manager program
-- written by NeroOneTrueKing

-- init
component = require("component")

lvmSlots = {1,2,3,4,5};
qtySuffixes = {"K", "M", "G", "T"};
stockedItems = {};
openStockers = {};


function document( f, description )
	return setmetatable( {f}, {__call = function(_, ...) return f(...) end, __tostring = function() return description end})
end

-- checks that necessary components exist, and loads them
function load_components()
	-- need an ME Interface
	ae2 = component.getPrimary("me_interface");
	assert(ae2 ~= nil, "Requires an ME Interface");

	-- need a database
	db = component.getPrimary("database");
	assert(db ~= nil, "Requires a database");

	-- needs one or more level maintainers
	lvmList = component.list("level_maintainer");
	assert( next(lvmList) ~= nil, "Needs at least one level maintainer");
end

-- loads data from a single level maintainer
function load_lvm(lvmAddress)
	local lvm = component.proxy(lvmAddress);
	local outInfo = {nil, nil, nil, nil, nil};

	for i=1, #lvmSlots do
		local stockedItem = lvm.getSlot(i);
		if stockedItem ~= nil and lvm.isEnable(i) then
			outInfo[i] = stockedItem;
		end
	end
	return outInfo;
end

-- to store items as a lookuptable instead of a list
function itemID(item)
	return item.name ..":".. item.damage ..":".. item.label;
end

-- to query AE2 with
function itemFilter(item)
	return {name=item.name, damage=item.damage, label=item.label, isCraftable=true};
end

function load_all_lvms()
	stockedItems = {};
	openStockers = {};
	for k,v in pairs(lvmList) do
		local lvmItems = load_lvm(k);
		for i=1,#lvmSlots do
			if lvmItems[i] ~= nil then
				stockedItems[itemID(lvmItems[i])] = {
					name	=lvmItems[i].name,
					label	=lvmItems[i].label,
					damage	=lvmItems[i].damage,
					isDone	=lvmItems[i].isDone,
					quantity=lvmItems[i].quantity,
					batch	=lvmItems[i].batch,
					address	=k,
					slot	=i
				};
			else
				table.insert( openStockers, {
					address	=k,
					slot	=i
				});
			end
		end
	end
end


-- for debugging, I want to have the program query AE2 for current item quantities.
-- don't actually do this all the time, it'll cause TPS issues
function query_ae2(item)
	local result = ae2.getItemsInNetwork( itemFilter(item) );

	if next(result) then
		return result[1].size;
	else
		return -1;
	end
end

-- turns quantities into strings
function qtyStr(qtyNbr)
	if qtyNbr < 10000 then
		return string.format("  %4d", qtyNbr);
	else
		local e = math.floor(math.log(qtyNbr, 1000));
		return string.format("%4d %s",math.floor(qtyNbr/math.pow(1000,e)),qtySuffixes[e]);
	end
end

function print_item(item)
	print(string.format("%60s : %s / %s [%s]", item.label, qtyStr(query_ae2(item)), qtyStr(item.quantity),  qtyStr(item.batch)));
end

function print_items()
	for k,v in pairs(stockedItems) do
		print_item(v);
	end
end

-- returns address and slot of an open levelmaintainer, or nil/nil if none exist
function get_open_slot()
	if next(openStockers) then
		return openStockers[1].address, openStockers[1].slot;
	else
		return nil, nil;
	end
end

function consume_open_slot()
	table.remove(openStockers, 1)
end

-- stops stocking the given item
function stop_stocking_item(item)
	local stockedItem = stockedItems[itemID(item)];

	if stockedItem ~= nil then
		-- disable in level maintainer
		component.proxy(stockedItem.address).setEnable(stockedItem.slot, false);
		-- mark as available
		table.insert( openStockers, {
			address = stockedItem.address,
			slot = stockedItem.slot
		});
		-- remove from stockedItems
		stockedItems[itemID(item)] = nil
	end
end

function set_stock(item, quantity, batch)
	-- is it currently being stocked?
	if stockedItems[itemID(item)] then
		local address, slot = stockedItems[itemID(item)].address, stockedItems[itemID(item)].slot;
		component.invoke(address, "setSlot", slot, db.address, 1, quantity, batch);
	else
		local address, slot = get_open_slot();
		
		if address == nil then
			print("error, no open slots");
		else
			-- reuse database slot 1
			db.clear(1);

			if ae2.store( itemFilter(item), db.address, 1 ) then
				if component.invoke(address, "setSlot", slot, db.address, 1, quantity, batch) then
					consume_open_slot();
					print("success");
				else
					print("failed to set slot");
				end
			else
				print("error, could not store item into database");
			end
		end
	end
end

load_components();
load_all_lvms();
print_items();

return
{
	set_stock			=document(set_stock, "function(item:table, quantity:number, batch:number) -- starts stocking item"),
	print_items			=document(print_items, "function() -- prints all stocked items"),
	stop_stocking_item	=document(stop_stocking_item, "function(item:table) -- stops stocking item")
}
